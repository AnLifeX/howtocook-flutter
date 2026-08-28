import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import '../../../recipe/domain/entities/recipe.dart';

/// MCP (Model Context Protocol) 服务
///
/// 封装与 MCP 服务的交互
/// 响应格式: SSE (Server-Sent Events) with JSON-RPC 2.0
class MCPService {
  final Dio _dio;
  final Dio _catalogDio = Dio();
  late final String baseUrl;
  int _requestId = 0;
  Map<String, dynamic>? _v2Manifest;
  String? _v2CatalogBaseUrl;

  static const _v2CatalogCandidates = [
    'https://gaq152.github.io/HowToCook-assets',
    'https://cdn.jsdelivr.net/gh/Gaq152/HowToCook-assets@main',
    'https://fastly.jsdelivr.net/gh/Gaq152/HowToCook-assets@main',
    'https://ghfast.top/https://raw.githubusercontent.com/Gaq152/HowToCook-assets/refs/heads/main',
  ];

  MCPService() : _dio = Dio() {
    try {
      baseUrl = dotenv.env['MCP_BASE_URL']?.trim() ?? '';
    } catch (_) {
      // 单元测试或极早启动阶段 dotenv 可能尚未初始化。
      baseUrl = '';
    }
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };
    _catalogDio.options.connectTimeout = const Duration(seconds: 8);
    _catalogDio.options.receiveTimeout = const Duration(seconds: 12);
  }

  bool get isConfigured => baseUrl.isNotEmpty;

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      return jsonDecode(value) as Map<String, dynamic>;
    }
    throw const FormatException('Unexpected JSON response');
  }

  /// App 端 MCP 查询直读与静态仓库同源的 V2 稳定通道。
  /// 这样线上 MCP 容器延迟部署时，索引和详情不会停留在 322 份旧数据。
  Future<Map<String, dynamic>?> _loadV2Manifest() async {
    if (_v2Manifest != null) return _v2Manifest;
    for (final base in _v2CatalogCandidates) {
      try {
        final channelResponse = await _catalogDio.get(
          '$base/channels/v2-stable.json',
          queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        );
        final channel = _asJsonMap(channelResponse.data);
        if (channel['schemaVersion'] != 2 || channel['channel'] != 'stable') {
          continue;
        }
        final manifestPath = channel['manifestPath']?.toString();
        if (manifestPath == null || manifestPath.isEmpty) continue;
        final manifestResponse = await _catalogDio.get('$base/$manifestPath');
        final manifest = _asJsonMap(manifestResponse.data);
        if (manifest['schemaVersion'] != 2 || manifest['recipes'] is! List) {
          continue;
        }
        _v2CatalogBaseUrl = base;
        return _v2Manifest = manifest;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<Recipe?> _getV2Recipe(String query) async {
    final manifest = await _loadV2Manifest();
    if (manifest == null) return null;
    final recipes = (manifest['recipes'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final normalized = query.trim().toLowerCase();
    Map<String, dynamic>? target;
    for (final item in recipes) {
      final legacyIds = (item['legacyIds'] as List? ?? const []).map(
        (id) => id.toString(),
      );
      if (item['id'] == query ||
          legacyIds.contains(query) ||
          item['name']?.toString().toLowerCase() == normalized) {
        target = item;
        break;
      }
    }
    target ??= recipes.where((item) {
      return item['name']?.toString().toLowerCase().contains(normalized) ==
          true;
    }).firstOrNull;
    if (target == null || _v2CatalogBaseUrl == null) return null;
    final basePath = manifest['basePath']?.toString();
    if (basePath == null || basePath.isEmpty) return null;
    try {
      final response = await _catalogDio.get(
        '$_v2CatalogBaseUrl/$basePath/recipes/${target['category']}/${target['id']}.json',
      );
      return _mcpToRecipe(_asJsonMap(response.data));
    } catch (_) {
      return null;
    }
  }

  /// 调用 MCP 工具（JSON-RPC 2.0 格式）
  ///
  /// [toolName] 工具名称（带 mcp_howtocook_ 前缀）
  /// [arguments] 工具参数
  Future<dynamic> _callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    try {
      if (!isConfigured) {
        throw StateError('未配置 MCP_BASE_URL，当前云端工具不可用');
      }
      _requestId++;

      // JSON-RPC 2.0 请求格式
      final requestData = {
        'jsonrpc': '2.0',
        'id': _requestId,
        'method': 'tools/call',
        'params': {
          'name': 'mcp_howtocook_$toolName', // 添加前缀
          'arguments': arguments,
        },
      };

      final response = await _dio.post('/mcp', data: requestData);

      // 解析 SSE 响应
      return _parseSSEResponse(response.data);
    } on DioException catch (e) {
      throw Exception('MCP tool call failed: ${e.message}');
    }
  }

  /// 解析 SSE (Server-Sent Events) 响应
  ///
  /// SSE 格式: event: message\ndata: {...JSON-RPC...}
  dynamic _parseSSEResponse(String data) {
    try {
      // 解析 SSE 格式
      final lines = data.split('\n');
      String? jsonData;

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          jsonData = line.substring(6);
          break;
        }
      }

      if (jsonData == null) {
        throw Exception('No data found in SSE response');
      }

      // 解析 JSON-RPC 响应
      final jsonrpcResponse = jsonDecode(jsonData) as Map<String, dynamic>;

      // 检查错误
      if (jsonrpcResponse.containsKey('error')) {
        final error = jsonrpcResponse['error'];
        throw Exception('MCP tool error: ${error['message']}');
      }

      // 提取 result
      final result = jsonrpcResponse['result'];
      if (result == null) {
        throw Exception('MCP response missing "result" field');
      }

      // 解析 result.content
      return _parseToolResult(result);
    } catch (e) {
      throw Exception('Failed to parse SSE response: $e');
    }
  }

  /// 解析工具调用结果
  ///
  /// MCP 标准格式: { content: [{ type: "text", text: "..." }] }
  dynamic _parseToolResult(Map<String, dynamic> result) {
    try {
      final content = result['content'] as List<dynamic>?;
      if (content == null || content.isEmpty) {
        throw Exception('MCP result content is empty');
      }

      // 提取第一个 content 项的 text 字段
      final firstContent = content[0] as Map<String, dynamic>;
      final text = firstContent['text'] as String?;
      if (text == null) {
        throw Exception('MCP content missing "text" field');
      }

      // 尝试 JSON 解码（如果返回的是 JSON 字符串）
      try {
        return jsonDecode(text);
      } catch (e) {
        // 如果不是 JSON，直接返回文本
        return text;
      }
    } catch (e) {
      throw Exception('Failed to parse MCP tool result: $e');
    }
  }

  /// 将 MCP 菜谱数据转换为 Recipe 实体
  ///
  /// MCP 返回的数据格式与 Recipe 实体不完全匹配，需要进行字段映射和补充
  Recipe _mcpToRecipe(Map<String, dynamic> mcpData) {
    try {
      final name = (mcpData['name'] as String? ?? '未知菜谱').replaceFirst(
        RegExp(r'的做法$'),
        '',
      );
      final id = mcpData['id'] as String? ?? 'recipe_${name.hashCode.abs()}';
      const categoryNameMap = {
        'meat_dish': '荤菜',
        'vegetable_dish': '素菜',
        'breakfast': '早餐',
        'staple': '主食',
        'soup': '汤粥',
        'dessert': '甜品',
        'drink': '饮料',
        'semi-finished': '半成品',
        'condiment': '调料',
        'aquatic': '水产',
      };
      const categoryIdMap = {
        '水产': 'aquatic',
        '早餐': 'breakfast',
        '调料': 'condiment',
        '甜品': 'dessert',
        '饮料': 'drink',
        '饮品': 'drink',
        '荤菜': 'meat_dish',
        '半成品': 'semi-finished',
        '半成品加工': 'semi-finished',
        '汤': 'soup',
        '汤粥': 'soup',
        '汤羹': 'soup',
        '主食': 'staple',
        '素菜': 'vegetable_dish',
      };
      final rawCategory = mcpData['category']?.toString() ?? 'other';
      final category = categoryNameMap.containsKey(rawCategory)
          ? rawCategory
          : (categoryIdMap[rawCategory] ?? 'other');

      final ingredients = (mcpData['ingredients'] as List<dynamic>? ?? []).map((
        item,
      ) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final rawText =
              (map['text'] ?? map['text_quantity'] ?? map['name'] ?? '')
                  .toString();
          final name = (map['name'] ?? rawText.split(RegExp(r'\s+')).first)
              .toString();
          return {
            'name': name,
            'text': completeIngredientText(name, rawText),
            'optional': map['optional'] == true,
            if (map['source'] != null) 'source': map['source'],
            if (map['table'] is Map) 'table': map['table'],
          };
        }
        final text = item.toString();
        return {'name': text.split(RegExp(r'\s+')).first, 'text': text};
      }).toList();

      final steps = (mcpData['steps'] as List<dynamic>? ?? []).map((item) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          return {
            'kind': map['kind'] ?? 'step',
            if (map['title'] != null) 'title': map['title'],
            'description':
                (map['description'] ?? map['text'] ?? map['content'] ?? '')
                    .toString(),
          };
        }
        return {'kind': 'step', 'description': item.toString()};
      }).toList();

      final additionalNotes = mcpData['additional_notes'];
      final tips =
          mcpData['tips'] ??
          (additionalNotes is List
              ? additionalNotes.join('\n')
              : additionalNotes);

      final recipeJson = {
        'schemaVersion': mcpData['schemaVersion'] ?? 2,
        'id': id,
        'legacyIds': mcpData['legacyIds'] ?? const <String>[],
        'name': name,
        'description': mcpData['description'],
        'category': category,
        'categoryName':
            mcpData['categoryName'] ?? categoryNameMap[category] ?? '其他',
        'difficulty': mcpData['difficulty'] ?? 3,
        'estimatedCaloriesKcal': mcpData['estimatedCaloriesKcal'],
        'images': mcpData['images'] as List<dynamic>? ?? [],
        'externalImages': mcpData['externalImages'] as List<dynamic>? ?? [],
        'requirements': mcpData['requirements'] as List<dynamic>? ?? [],
        'requirementsMarkdown': mcpData['requirementsMarkdown'],
        'ingredients': ingredients,
        'tools': mcpData['tools'] as List<dynamic>? ?? [],
        'calculationMarkdown': mcpData['calculationMarkdown'],
        'calculationNotes': mcpData['calculationNotes'] as List<dynamic>? ?? [],
        'steps': steps,
        'operationMarkdown': mcpData['operationMarkdown'],
        'tips': tips?.toString(),
        'warnings': mcpData['warnings'] as List<dynamic>? ?? [],
        'additionalMarkdown': mcpData['additionalMarkdown'],
        'hash': mcpData['hash'] as String? ?? id.hashCode.toString(),
        'source': mcpData['source'] ?? 'cloud',
      };

      return Recipe.fromJson(recipeJson);
    } catch (e) {
      throw Exception('Failed to convert MCP data to Recipe: $e');
    }
  }

  /// 1. 获取所有菜谱
  ///
  /// 对应 MCP 工具: mcp_howtocook_getAllRecipes
  Future<List<Recipe>> getAllRecipes() async {
    try {
      final manifest = await _loadV2Manifest();
      if (manifest != null) {
        return (manifest['recipes'] as List<dynamic>).map((item) {
          final index = Map<String, dynamic>.from(item as Map);
          return _mcpToRecipe({
            ...index,
            'schemaVersion': 2,
            'ingredients': const [],
            'steps': const [],
            'source': 'cloud',
          });
        }).toList();
      }
      final result = await _callTool('getAllRecipes', {
        'no_param': '', // 工具要求的无参数标记
      });

      if (result is List) {
        return result
            .map((json) => _mcpToRecipe(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Invalid getAllRecipes result format');
    } catch (e) {
      throw Exception('Failed to get all recipes: $e');
    }
  }

  /// 2. 按分类获取菜谱
  ///
  /// [category] 分类名称（中文：水产、早餐、调料、甜品、饮品、荤菜、半成品加工、汤、主食、素菜）
  /// 对应 MCP 工具: mcp_howtocook_getRecipesByCategory
  Future<List<Recipe>> getRecipesByCategory(String category) async {
    try {
      final manifest = await _loadV2Manifest();
      if (manifest != null) {
        final categories = Map<String, dynamic>.from(
          manifest['categories'] as Map,
        );
        final categoryId = categories.containsKey(category)
            ? category
            : categories.entries
                  .where((entry) {
                    final value = entry.value;
                    return value is Map && value['name'] == category;
                  })
                  .map((entry) => entry.key)
                  .firstOrNull;
        return (manifest['recipes'] as List<dynamic>)
            .where(
              (item) =>
                  item is Map && item['category'] == (categoryId ?? category),
            )
            .map((item) {
              final index = Map<String, dynamic>.from(item as Map);
              return _mcpToRecipe({
                ...index,
                'schemaVersion': 2,
                'ingredients': const [],
                'steps': const [],
                'source': 'cloud',
              });
            })
            .toList();
      }
      final result = await _callTool('getRecipesByCategory', {
        'category': category,
      });

      if (result is List) {
        return result
            .map((json) => _mcpToRecipe(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Invalid getRecipesByCategory result format');
    } catch (e) {
      throw Exception('Failed to get recipes by category: $e');
    }
  }

  /// 3. 按名称或 ID 查询菜谱详情
  ///
  /// [query] 菜谱名称或 ID（支持模糊匹配）
  /// 对应 MCP 工具: mcp_howtocook_getRecipeById
  ///
  /// 返回 [Recipe]（精确匹配）或 [Map]（模糊匹配/错误建议，直接透传给 AI）
  Future<dynamic> getRecipeById(String query) async {
    try {
      final v2Recipe = await _getV2Recipe(query);
      if (v2Recipe != null) return v2Recipe;
      final result = await _callTool('getRecipeById', {'query': query});

      if (result is Map<String, dynamic>) {
        // 精确匹配：MCP 直接返回完整菜谱数据（含 name 字段）
        if (result.containsKey('name') && result.containsKey('id')) {
          return _mcpToRecipe(result);
        }

        // 模糊匹配建议或错误信息：透传给 AI 决策
        if (result.containsKey('possibleMatches') ||
            result.containsKey('error') ||
            result.containsKey('suggestion')) {
          return result;
        }
      } else if (result is List &&
          result.isNotEmpty &&
          result[0] is Map<String, dynamic>) {
        return _mcpToRecipe(result[0] as Map<String, dynamic>);
      }

      return {'error': '未找到匹配「$query」的菜谱', 'query': query};
    } catch (e) {
      throw Exception('Failed to get recipe by ID: $e');
    }
  }

  /// 4. 推荐菜谱
  ///
  /// [peopleCount] 用餐人数（1-10）
  /// [allergies] 过敏原列表（可选）
  /// [avoidItems] 忌口食材列表（可选）
  /// 对应 MCP 工具: mcp_howtocook_recommendMeals
  Future<Map<String, dynamic>> recommendMeals({
    required int peopleCount,
    List<String>? allergies,
    List<String>? avoidItems,
  }) async {
    try {
      final arguments = <String, dynamic>{'peopleCount': peopleCount};

      if (allergies != null && allergies.isNotEmpty) {
        arguments['allergies'] = allergies;
      }

      if (avoidItems != null && avoidItems.isNotEmpty) {
        arguments['avoidItems'] = avoidItems;
      }

      final result = await _callTool('recommendMeals', arguments);

      if (result is Map<String, dynamic>) {
        return result;
      }

      throw Exception('Invalid recommendMeals result format');
    } catch (e) {
      throw Exception('Failed to recommend meals: $e');
    }
  }

  /// 5. 今天吃什么
  ///
  /// [peopleCount] 用餐人数（1-10）
  /// 对应 MCP 工具: mcp_howtocook_whatToEat
  /// 返回格式: { peopleCount, meatDishCount, vegetableDishCount, dishes: [...], message }
  Future<List<Recipe>> whatToEat({required int peopleCount}) async {
    try {
      final result = await _callTool('whatToEat', {'peopleCount': peopleCount});

      if (result is Map<String, dynamic>) {
        // 提取 dishes 数组
        final dishes = result['dishes'] as List<dynamic>?;
        if (dishes == null) {
          throw Exception('whatToEat result missing "dishes" field');
        }

        // 使用 _mcpToRecipe 转换 MCP 数据为 Recipe 实体
        return dishes
            .map((json) => _mcpToRecipe(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Invalid whatToEat result format');
    } catch (e) {
      throw Exception('Failed to get what to eat: $e');
    }
  }

  /// 搜索菜谱（通过 getAllRecipes 然后本地过滤）
  ///
  /// [query] 搜索关键词
  Future<List<Recipe>> searchRecipes(String query) async {
    try {
      final allRecipes = await getAllRecipes();

      // 本地过滤
      final results = allRecipes.where((recipe) {
        return recipe.name.contains(query) ||
            recipe.categoryName.contains(query) ||
            (recipe.tips?.contains(query) ?? false);
      }).toList();

      return results;
    } catch (e) {
      throw Exception('Failed to search recipes: $e');
    }
  }

  /// 获取随机菜谱（通过 whatToEat）
  ///
  /// [count] 数量（通过 peopleCount 参数控制）
  Future<List<Recipe>> getRandomRecipes({int count = 5}) async {
    // whatToEat 使用 peopleCount，我们用它来近似控制数量
    return whatToEat(peopleCount: count.clamp(1, 10));
  }

  /// 获取菜谱详情（通过 getRecipeById）
  ///
  /// [recipeId] 菜谱 ID 或名称
  /// 注意：如果传入的是通过 getAllRecipes 生成的 ID（格式：recipe_xxx），
  /// 则无法查询详情。建议使用菜谱名称进行查询。
  Future<Recipe> getRecipeDetail(String recipeId) async {
    if (recipeId.startsWith('recipe_')) {
      throw Exception(
        'Generated ID cannot be used for detail query. '
        'Please use recipe name instead. '
        'Generated IDs are only from getAllRecipes which returns minimal data.',
      );
    }
    final result = await getRecipeById(recipeId);
    if (result is Recipe) return result;
    throw Exception('未找到菜谱: $recipeId');
  }

  /// 获取收藏的菜谱（通过多次调用 getRecipeById）
  ///
  /// [favoriteIds] 收藏的菜谱 ID 列表
  Future<List<Recipe>> getFavoriteRecipes(List<String> favoriteIds) async {
    try {
      final recipes = <Recipe>[];

      final futures = favoriteIds.map((id) => getRecipeById(id));
      final results = await Future.wait(futures, eagerError: false);

      for (final r in results) {
        if (r is Recipe) recipes.add(r);
      }
      return recipes;
    } catch (e) {
      throw Exception('Failed to get favorite recipes: $e');
    }
  }

  /// 健康检查
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      final response = await _dio.get('/health');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Health check failed: $e');
    }
  }

  /// 获取服务器信息
  Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await _dio.get('/info');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to get server info: $e');
    }
  }

  /// 6. 创建新食谱
  ///
  /// [recipe] 推荐的 V2 结构化食谱
  /// [recipeText] 兼容旧版的自然语言食谱文本
  /// [checkDuplicate] 是否检查重复（默认 true）
  /// [similarityThreshold] 相似度检测阈值（0-1，默认 0.75）
  /// 对应 MCP 工具: mcp_howtocook_createRecipe
  ///
  /// 返回格式: {
  ///   recipe: {...},  // 创建的食谱对象
  ///   warnings: [...] // 警告信息（如相似度检测结果）
  /// }
  Future<Map<String, dynamic>> createRecipe({
    String? recipeText,
    Map<String, dynamic>? recipe,
    bool checkDuplicate = true,
    double similarityThreshold = 0.75,
  }) async {
    try {
      final arguments = <String, dynamic>{
        if (recipeText != null && recipeText.trim().isNotEmpty)
          'recipeText': recipeText,
        if (recipe != null) 'recipe': recipe,
        'checkDuplicate': checkDuplicate,
        'similarityThreshold': similarityThreshold,
      };
      if (!arguments.containsKey('recipeText') && recipe == null) {
        throw ArgumentError('recipe 和 recipeText 至少需要一个');
      }

      final result = await _callTool('createRecipe', arguments);

      if (result is Map<String, dynamic>) {
        // 检查是否有错误
        if (result.containsKey('error')) {
          throw Exception('创建食谱失败: ${result['error']}');
        }

        return result;
      }

      throw Exception('Invalid createRecipe result format');
    } catch (e) {
      throw Exception('Failed to create recipe: $e');
    }
  }

  /// 获取可用的工具列表
  Future<List<Map<String, dynamic>>> listTools() async {
    try {
      _requestId++;

      final requestData = {
        'jsonrpc': '2.0',
        'id': _requestId,
        'method': 'tools/list',
      };

      final response = await _dio.post('/mcp', data: requestData);

      // tools/list 返回格式特殊，需要单独解析
      final data = response.data as String;
      final lines = data.split('\n');
      String? jsonData;

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          jsonData = line.substring(6);
          break;
        }
      }

      if (jsonData == null) {
        throw Exception('No data found in SSE response');
      }

      final jsonrpcResponse = jsonDecode(jsonData) as Map<String, dynamic>;

      if (jsonrpcResponse.containsKey('error')) {
        final error = jsonrpcResponse['error'];
        throw Exception('MCP error: ${error['message']}');
      }

      final result = jsonrpcResponse['result'] as Map<String, dynamic>?;
      if (result == null) {
        throw Exception('MCP response missing result field');
      }

      final tools = result['tools'] as List<dynamic>?;
      if (tools == null) {
        throw Exception('MCP response missing tools field');
      }

      return tools.map((tool) => tool as Map<String, dynamic>).toList();
    } catch (e) {
      throw Exception('Failed to list tools: $e');
    }
  }
}
