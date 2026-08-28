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
      '搜索当前数据模式的菜谱。返回最多 20 条精简摘要；需要做法时再调用 getRecipeById。',
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

  static final Map<String, dynamic> _favoritesTool = _tool(
    'getFavoriteRecipes',
    '读取用户在本机收藏的菜谱摘要。仅本地数据模式允许。',
    {
      'type': 'object',
      'properties': {
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxListResults},
      },
    },
  );

  List<Map<String, dynamic>> definitionsFor(RecipeDataMode mode) {
    final tools =
        [
            ..._commonTools,
            if (mode == RecipeDataMode.local) _favoritesTool,
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
    final limit = _int(input['limit'], 10, 1, maxListResults);
    final items = recipes.take(limit).map(_summary).toList();
    return {
      'success': true,
      if (query != null) 'query': query,
      if (category != null) 'category': category,
      if (peopleCount != null) 'peopleCount': peopleCount,
      'recipes': items,
      'count': items.length,
      'totalMatches': recipes.length,
      'truncated': recipes.length > items.length,
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
