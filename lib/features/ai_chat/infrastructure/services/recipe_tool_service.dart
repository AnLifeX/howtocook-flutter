import 'dart:convert';
import 'dart:math';

import '../../../recipe/domain/entities/recipe.dart';
import '../../../recipe/domain/repositories/recipe_repository.dart';
import '../../domain/entities/recipe_data_mode.dart';
import 'mcp_service.dart';

/// App 内置菜谱工具目录与执行器。
///
/// 工具目录决定模型能看到什么，execute 会按当前模式再次校验，防止模型伪造
/// 未授权的工具名。所有列表类结果仅返回摘要，避免把整库灌入上下文。
class RecipeToolService {
  RecipeToolService({
    required RecipeRepository localRepository,
    required MCPService cloudService,
    Random? random,
  }) : _localRepository = localRepository,
       _cloudService = cloudService,
       _random = random ?? Random();

  final RecipeRepository _localRepository;
  final MCPService _cloudService;
  final Random _random;

  static const int maxListResults = 20;

  static const Map<String, dynamic> createRecipeInputSchema = {
    'type': 'object',
    'properties': {
      'recipe': {
        'type': 'object',
        'description': '完整结构化菜谱；食材 text 必须包含名称和用量，步骤 description 不要自带序号。',
        'properties': {
          'name': {'type': 'string'},
          'description': {'type': 'string'},
          'category': {'type': 'string'},
          'categoryName': {'type': 'string'},
          'difficulty': {'type': 'integer', 'minimum': 1, 'maximum': 5},
          'estimatedCaloriesKcal': {'type': 'integer', 'minimum': 1},
          'requirements': {
            'type': 'array',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'text': {'type': 'string'},
                    'kind': {
                      'type': 'string',
                      'enum': ['ingredient', 'tool', 'unknown'],
                    },
                    'group': {'type': 'string'},
                  },
                  'required': ['text'],
                },
              ],
            },
          },
          'ingredients': {
            'type': 'array',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'text': {'type': 'string'},
                    'optional': {'type': 'boolean'},
                    'source': {'type': 'string'},
                    'table': {
                      'type': 'object',
                      'additionalProperties': {'type': 'string'},
                    },
                  },
                  'required': ['name', 'text'],
                },
              ],
            },
          },
          'tools': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'calculationNotes': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'steps': {
            'type': 'array',
            'items': {
              'oneOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'kind': {
                      'type': 'string',
                      'enum': ['step', 'heading'],
                    },
                    'title': {'type': 'string'},
                    'description': {'type': 'string'},
                  },
                  'required': ['description'],
                },
              ],
            },
          },
          'tips': {'type': 'string'},
          'warnings': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['name', 'ingredients', 'steps'],
      },
      'recipeText': {
        'type': 'string',
        'description': '仅用于兼容旧模型；支持工具调用时应优先提供 recipe。',
      },
      'checkDuplicate': {'type': 'boolean', 'default': true},
      'similarityThreshold': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'default': 0.75,
      },
    },
    'anyOf': [
      {
        'required': ['recipe'],
      },
      {
        'required': ['recipeText'],
      },
    ],
  };

  static final List<Map<String, dynamic>> _commonTools = [
    _tool(
      'searchRecipes',
      '搜索当前数据模式的菜谱。返回最多 20 条精简摘要；truncated=true 表示结果不完整，不得据此断言某菜谱不存在。零结果时先用精简菜名或主要食材复查，需要做法时再调用 getRecipeById。',
      {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '菜名、分类或食材关键词；可留空浏览。'},
          'category': {'type': 'string', 'description': '可选分类 ID 或中文名。'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
        },
      },
    ),
    _tool('getRecipeById', '按 searchRecipes 返回的原始 ID 获取完整菜谱；也兼容输入准确菜名。', {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'query': {'type': 'string'},
      },
      'anyOf': [
        {
          'required': ['id'],
        },
        {
          'required': ['query'],
        },
      ],
    }),
    _tool('getRecipesByCategory', '按分类获取菜谱摘要，返回数量受限；需要详情时再调用 getRecipeById。', {
      'type': 'object',
      'properties': {
        'category': {'type': 'string'},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
      },
      'required': ['category'],
    }),
    _tool('recommendMeals', '按人数、过敏和忌口推荐菜谱摘要。', {
      'type': 'object',
      'properties': {
        'peopleCount': {'type': 'integer', 'minimum': 1, 'maximum': 10},
        'allergies': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'avoidItems': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    }),
    _tool('whatToEat', '随机搭配一组菜谱摘要，适合“今天吃什么”。', {
      'type': 'object',
      'properties': {
        'peopleCount': {'type': 'integer', 'minimum': 1, 'maximum': 10},
      },
    }),
    _tool(
      'createRecipe',
      '创建可在聊天中预览、由用户确认后保存到本地的菜谱草稿；调用本身不会直接写入本地菜谱库。',
      createRecipeInputSchema,
    ),
  ];

  static final List<Map<String, dynamic>> _localTools = [
    _tool('getFavoriteRecipes', '读取用户在本机收藏的菜谱摘要。仅本地数据模式允许。', {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
      },
    }),
    _tool('listRecipeCategories', '列出本地菜谱分类、分类 ID 和数量，用于浏览前确认可用分类。', {
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    _tool('findRecipesByIngredients', '根据用户现有食材匹配本地菜谱，优先返回缺少必需食材更少的结果。', {
      'type': 'object',
      'properties': {
        'ingredients': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
        },
        'excludeIngredients': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '过敏、忌口或明确不想使用的食材。',
        },
        'category': {'type': 'string', 'description': '可选分类 ID 或中文名。'},
        'maxDifficulty': {'type': 'integer', 'minimum': 1, 'maximum': 5},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
      },
      'required': ['ingredients'],
    }),
    _tool('getMyRecipes', '读取用户自建、修改、扫码导入或已保存的 AI 菜谱摘要。', {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': '可选菜名、分类或食材关键词。'},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
      },
    }),
    _tool('getRecipePersonalInfo', '按菜谱原始 ID 读取本机收藏状态和用户笔记。', {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    }),
  ];

  List<Map<String, dynamic>> definitionsFor(RecipeDataMode mode) {
    final tools =
        [
            ..._commonTools,
            if (mode == RecipeDataMode.local) ..._localTools,
          ].map((item) => _canonicalize(item) as Map<String, dynamic>).toList()
          ..sort(
            (a, b) => a['name'].toString().compareTo(b['name'].toString()),
          );
    return tools;
  }

  Future<Map<String, dynamic>> execute({
    required RecipeDataMode mode,
    required String toolName,
    required Map<String, dynamic> input,
  }) async {
    final normalizedName = _normalizeToolName(toolName);
    final allowed = definitionsFor(
      mode,
    ).map((tool) => tool['name']).contains(normalizedName);
    if (!allowed) {
      return {
        'success': false,
        'error': '工具 $normalizedName 在${mode.label}模式下未授权',
        'code': 'tool_not_allowed',
      };
    }

    try {
      return mode == RecipeDataMode.local
          ? await _executeLocal(normalizedName, input)
          : await _executeCloud(normalizedName, input);
    } catch (error) {
      return {
        'success': false,
        'error': error.toString().replaceFirst('Exception: ', ''),
        'code': 'tool_execution_failed',
      };
    }
  }

  Future<Map<String, dynamic>> _executeLocal(
    String name,
    Map<String, dynamic> input,
  ) async {
    switch (name) {
      case 'searchRecipes':
        final query = _string(input['query'] ?? input['keyword']);
        var recipes = query.isEmpty
            ? await _localRepository.getAllRecipes()
            : await _localRepository.searchRecipes(query);
        if (query.isNotEmpty && recipes.isEmpty) {
          recipes = _fallbackLocalSearch(
            await _localRepository.getAllRecipes(),
            query,
          );
        }
        recipes = _filterCategory(recipes, _string(input['category']));
        return _listResult(recipes, input, query: query);
      case 'getRecipesByCategory':
        final category = _requiredString(
          input['category'] ?? input['categoryName'],
          'category',
        );
        final recipes = await _localRepository.getRecipesByCategory(category);
        return _listResult(recipes, input, category: category);
      case 'getRecipeById':
        final query = _requiredString(
          input['id'] ??
              input['query'] ??
              input['recipeId'] ??
              input['recipeName'],
          'id/query',
        );
        final direct = await _localRepository.getRecipeById(query);
        if (direct != null) return _detailResult(direct);
        final matches = await _localRepository.searchRecipes(query);
        if (matches.length == 1) return _detailResult(matches.first);
        return {
          'success': false,
          'query': query,
          'error': matches.isEmpty ? '未找到匹配菜谱' : '找到多个结果，请使用返回的原始 ID 再查询',
          'possibleMatches': matches.take(8).map(_summary).toList(),
        };
      case 'getFavoriteRecipes':
        return _listResult(await _localRepository.getFavoriteRecipes(), input);
      case 'listRecipeCategories':
        final counts = <String, Map<String, dynamic>>{};
        for (final recipe in await _localRepository.getAllRecipes()) {
          final category = counts.putIfAbsent(
            recipe.category,
            () => {
              'id': recipe.category,
              'name': recipe.categoryName,
              'count': 0,
            },
          );
          category['count'] = (category['count'] as int) + 1;
        }
        final categories = counts.values.toList()
          ..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
        return {
          'success': true,
          'categories': categories,
          'count': categories.length,
        };
      case 'findRecipesByIngredients':
        return _findLocalRecipesByIngredients(input);
      case 'getMyRecipes':
        var recipes = (await _localRepository.getAllRecipes())
            .where(_isMyRecipe)
            .toList();
        final query = _string(input['query']);
        if (query.isNotEmpty) recipes = _fallbackLocalSearch(recipes, query);
        return _listResult(recipes, input, query: query);
      case 'getRecipePersonalInfo':
        final id = _requiredString(input['id'], 'id');
        final recipe = await _localRepository.getRecipeById(id);
        if (recipe == null) {
          return {'success': false, 'id': id, 'error': '未找到菜谱'};
        }
        return {
          'success': true,
          'id': recipe.id,
          'name': recipe.name,
          'isFavorite': recipe.isFavorite,
          'userNote': recipe.userNote,
        };
      case 'recommendMeals':
        return _localRecommendations(input, randomize: false);
      case 'whatToEat':
        return _localRecommendations(input, randomize: true);
      case 'createRecipe':
        return _localCreate(input);
    }
    throw StateError('未知工具: $name');
  }

  Future<Map<String, dynamic>> _executeCloud(
    String name,
    Map<String, dynamic> input,
  ) async {
    switch (name) {
      case 'searchRecipes':
        final query = _string(input['query'] ?? input['keyword']);
        var recipes = query.isEmpty
            ? await _cloudService.getAllRecipes()
            : await _cloudService.searchRecipes(query);
        recipes = _filterCategory(recipes, _string(input['category']));
        return _listResult(recipes, input, query: query);
      case 'getRecipesByCategory':
        final category = _requiredString(
          input['category'] ?? input['categoryName'],
          'category',
        );
        return _listResult(
          await _cloudService.getRecipesByCategory(category),
          input,
          category: category,
        );
      case 'getRecipeById':
        final query = _requiredString(
          input['id'] ??
              input['query'] ??
              input['recipeId'] ??
              input['recipeName'],
          'id/query',
        );
        final value = await _cloudService.getRecipeById(query);
        if (value is Recipe) return _detailResult(value);
        if (value is Map) {
          return {'success': false, ...Map<String, dynamic>.from(value)};
        }
        return {'success': false, 'error': value.toString(), 'query': query};
      case 'recommendMeals':
        final result = await _cloudService.recommendMeals(
          peopleCount: _int(input['peopleCount'] ?? input['people'], 2, 1, 10),
          allergies: _strings(input['allergies']),
          avoidItems: _strings(input['avoidItems']),
        );
        return {'success': true, ...result};
      case 'whatToEat':
        final people = _int(input['peopleCount'] ?? input['people'], 2, 1, 10);
        final recipes = await _cloudService.whatToEat(peopleCount: people);
        return _listResult(recipes, input, peopleCount: people);
      case 'createRecipe':
        final recipe = _map(input['recipe']);
        final recipeText = _string(input['recipeText'] ?? input['text']);
        if (recipe == null && recipeText.isEmpty) {
          throw const FormatException('recipe 或 recipeText 至少需要一个');
        }
        final result = await _cloudService.createRecipe(
          recipe: recipe,
          recipeText: recipeText.isEmpty
              ? (recipe == null ? null : jsonEncode(recipe))
              : recipeText,
          checkDuplicate: input['checkDuplicate'] != false,
          similarityThreshold:
              (input['similarityThreshold'] as num?)?.toDouble() ?? 0.75,
        );
        if (recipe != null && result['recipe'] is Map) {
          return {
            ...result,
            'success': true,
            'recipe': {
              ...Map<String, dynamic>.from(result['recipe'] as Map),
              ...recipe,
            },
          };
        }
        return {'success': true, ...result};
    }
    throw StateError('未知工具: $name');
  }

  Future<Map<String, dynamic>> _localRecommendations(
    Map<String, dynamic> input, {
    required bool randomize,
  }) async {
    final people = _int(input['peopleCount'] ?? input['people'], 2, 1, 10);
    final blocked =
        {..._strings(input['allergies']), ..._strings(input['avoidItems'])}
            .map((item) => item.toLowerCase())
            .where((item) => item.isNotEmpty)
            .toList();
    var recipes = await _localRepository.getAllRecipes();
    recipes = recipes.where((recipe) {
      final haystack = [
        recipe.name,
        recipe.categoryName,
        ...recipe.ingredients.map((item) => item.text),
      ].join(' ').toLowerCase();
      return blocked.every((item) => !haystack.contains(item));
    }).toList();
    if (randomize) recipes.shuffle(_random);
    final count = (people + 2).clamp(3, 8);
    final selected = recipes.take(count).toList();
    return {
      'success': true,
      'peopleCount': people,
      'recipes': selected.map(_summary).toList(),
      'count': selected.length,
      if (blocked.isNotEmpty) 'excluded': blocked,
    };
  }

  Future<Map<String, dynamic>> _findLocalRecipesByIngredients(
    Map<String, dynamic> input,
  ) async {
    final available = _strings(input['ingredients']);
    if (available.isEmpty) {
      throw const FormatException('ingredients 至少需要一项');
    }
    final excluded = _strings(input['excludeIngredients']);
    final category = _string(input['category']);
    final maxDifficulty = input['maxDifficulty'] == null
        ? 5
        : _int(input['maxDifficulty'], 5, 1, 5);
    var recipes = _filterCategory(
      await _localRepository.getAllRecipes(),
      category,
    ).where((recipe) => recipe.difficulty <= maxDifficulty);

    final matches = <Map<String, dynamic>>[];
    for (final recipe in recipes) {
      if (excluded.any(
        (term) => recipe.ingredients.any(
          (ingredient) => _ingredientMatches(ingredient, term),
        ),
      )) {
        continue;
      }
      final matched = available
          .where(
            (term) => recipe.ingredients.any(
              (ingredient) => _ingredientMatches(ingredient, term),
            ),
          )
          .toSet()
          .toList();
      if (matched.isEmpty) continue;
      final missing = recipe.ingredients
          .where(
            (ingredient) =>
                !ingredient.optional &&
                !available.any((term) => _ingredientMatches(ingredient, term)),
          )
          .map((ingredient) => ingredient.name)
          .where((name) => name.trim().isNotEmpty)
          .toSet()
          .toList();
      matches.add({
        ..._summary(recipe),
        'matchedIngredients': matched,
        'missingIngredients': missing.take(8).toList(),
        'missingIngredientCount': missing.length,
      });
    }
    matches.sort((a, b) {
      final byMissing = (a['missingIngredientCount'] as int).compareTo(
        b['missingIngredientCount'] as int,
      );
      if (byMissing != 0) return byMissing;
      final byMatched = (b['matchedIngredients'] as List).length.compareTo(
        (a['matchedIngredients'] as List).length,
      );
      if (byMatched != 0) return byMatched;
      return a['name'].toString().compareTo(b['name'].toString());
    });
    final limit = _int(input['limit'], maxListResults, 1, maxListResults);
    return {
      'success': true,
      'ingredients': available,
      if (excluded.isNotEmpty) 'excluded': excluded,
      if (category.isNotEmpty) 'category': category,
      'recipes': matches.take(limit).toList(),
      'count': matches.length.clamp(0, limit),
      'totalMatches': matches.length,
      'truncated': matches.length > limit,
    };
  }

  bool _ingredientMatches(Ingredient ingredient, String query) {
    final haystack = _normalizeSearchText('${ingredient.name} ${ingredient.text}');
    return _searchVariants(query).any(haystack.contains);
  }

  bool _isMyRecipe(Recipe recipe) => switch (recipe.source) {
    RecipeSource.userCreated ||
    RecipeSource.userModified ||
    RecipeSource.scanned ||
    RecipeSource.aiGenerated => true,
    _ => false,
  };

  Map<String, dynamic> _localCreate(Map<String, dynamic> input) {
    final recipe = _map(input['recipe']);
    if (recipe == null) {
      return {
        'success': false,
        'error': '本地创建需要结构化 recipe，请按工具 schema 重新调用',
        'code': 'structured_recipe_required',
      };
    }
    if (_string(recipe['name']).isEmpty ||
        recipe['ingredients'] is! List ||
        recipe['steps'] is! List) {
      return {
        'success': false,
        'error': 'recipe 必须包含 name、ingredients 和 steps',
        'code': 'invalid_recipe',
      };
    }
    return {
      'success': true,
      'recipe': recipe,
      'warnings': const <String>[],
      'draftOnly': true,
    };
  }

  Map<String, dynamic> _listResult(
    List<Recipe> recipes,
    Map<String, dynamic> input, {
    String? query,
    String? category,
    int? peopleCount,
  }) {
    final limit = _int(input['limit'], maxListResults, 1, maxListResults);
    final items = recipes.take(limit).map(_summary).toList();
    final truncated = recipes.length > items.length;
    return {
      'success': true,
      if (query != null) 'query': query,
      if (category != null) 'category': category,
      if (peopleCount != null) 'peopleCount': peopleCount,
      'recipes': items,
      'count': items.length,
      'totalMatches': recipes.length,
      'truncated': truncated,
      'resultCoverage': truncated ? 'partial' : 'complete',
      if (truncated) 'warning': '结果已截断，不能据此判断未返回的菜谱不存在',
    };
  }

  Map<String, dynamic> _summary(Recipe recipe) => {
    'id': recipe.id,
    'name': recipe.name,
    'category': recipe.category,
    'categoryName': recipe.categoryName,
    'difficulty': recipe.difficulty,
    if (recipe.description?.trim().isNotEmpty == true)
      'description': recipe.description,
    if (recipe.estimatedCaloriesKcal != null)
      'estimatedCaloriesKcal': recipe.estimatedCaloriesKcal,
    'source': recipe.source.name,
  };

  Map<String, dynamic> _detailResult(Recipe recipe) {
    final json = Map<String, dynamic>.from(recipe.toJson())
      ..remove('userNote')
      ..remove('isFavorite')
      ..remove('images');
    return {'success': true, 'recipe': json};
  }

  List<Recipe> _filterCategory(List<Recipe> recipes, String category) {
    if (category.isEmpty) return recipes;
    final normalized = category.toLowerCase();
    return recipes.where((recipe) {
      return recipe.category.toLowerCase() == normalized ||
          recipe.categoryName.toLowerCase() == normalized;
    }).toList();
  }

  List<Recipe> _fallbackLocalSearch(List<Recipe> recipes, String query) {
    final variants = _searchVariants(query);
    return recipes.where((recipe) {
      final haystack = _normalizeSearchText(
        [
          recipe.name,
          recipe.categoryName,
          recipe.description ?? '',
          ...recipe.ingredients.map((ingredient) => ingredient.text),
        ].join(' '),
      );
      return variants.any(haystack.contains);
    }).toList();
  }

  Set<String> _searchVariants(String query) {
    final normalized = _normalizeSearchText(query);
    final variants = <String>{normalized};
    const aliases = <String, String>{
      '西红柿': '番茄',
      '番茄': '西红柿',
      '马铃薯': '土豆',
      '土豆': '马铃薯',
      '花菜': '菜花',
      '菜花': '花菜',
    };
    for (final entry in aliases.entries) {
      if (normalized.contains(entry.key)) {
        variants.add(normalized.replaceAll(entry.key, entry.value));
      }
    }
    return variants.where((term) => term.isNotEmpty).toSet();
  }

  String _normalizeSearchText(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
    '',
  );

  static Map<String, dynamic> _tool(
    String name,
    String description,
    Map<String, dynamic> inputSchema,
  ) => {'name': name, 'description': description, 'input_schema': inputSchema};

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static String _normalizeToolName(String value) {
    final name = value.replaceFirst('mcp_howtocook_', '');
    return switch (name) {
      'getAllRecipes' => 'searchRecipes',
      'getRecipeDetail' => 'getRecipeById',
      _ => name,
    };
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static String _requiredString(dynamic value, String key) {
    final result = _string(value);
    if (result.isEmpty) throw FormatException('缺少必填参数: $key');
    return result;
  }

  static int _int(dynamic value, int fallback, int min, int max) {
    final parsed = value is num ? value.toInt() : int.tryParse(_string(value));
    return (parsed ?? fallback).clamp(min, max);
  }

  static List<String> _strings(dynamic value) {
    if (value is List) {
      return value.map(_string).where((item) => item.isNotEmpty).toList();
    }
    final text = _string(value);
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'[,，、;；]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().startsWith('{')) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }
}
