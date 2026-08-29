import 'package:flutter/foundation.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/repositories/recipe_repository.dart';
import '../../../sync/infrastructure/bundled_data_loader.dart';
import '../../../../core/storage/hive_service.dart';

/// 菜谱仓储实现类
///
/// 整合内置数据（BundledDataLoader）和本地数据（Hive）
class RecipeRepositoryImpl implements RecipeRepository {
  final BundledDataLoader _bundledLoader;

  RecipeRepositoryImpl(this._bundledLoader);

  @override
  Future<List<Recipe>> getAllRecipes() async {
    try {
      final List<Recipe> recipes = [];
      final Set<String> loadedIds = {};

      // 1. 加载所有用户创建/修改的菜谱
      final modifiedBox = HiveService.getModifiedRecipesBox();
      for (final id in modifiedBox.keys) {
        try {
          final recipeJson = modifiedBox.get(id) as Map<dynamic, dynamic>;
          final convertedJson = _deepConvertMap(recipeJson);
          final recipe = Recipe.fromJson(convertedJson);

          // 合并收藏和笔记信息
          final isFav = await isFavorite(recipe.id);
          final note = await getUserNote(recipe.id);

          recipes.add(recipe.copyWith(isFavorite: isFav, userNote: note));
          loadedIds.add(id.toString());
        } catch (e) {
          debugPrint('Warning: Failed to load modified recipe $id: $e');
        }
      }

      // 2. 加载所有内置菜谱（跳过已被用户修改的）
      final manifest = await _bundledLoader.loadManifest();
      for (final recipeIndex in manifest.recipes) {
        // 跳过已被用户修改的菜谱（避免重复）
        if (loadedIds.contains(recipeIndex.id)) {
          continue;
        }

        try {
          final recipe = await _bundledLoader.loadRecipe(recipeIndex.id);

          // 合并收藏和笔记信息
          final isFav = await isFavorite(recipe.id);
          final note = await getUserNote(recipe.id);

          recipes.add(recipe.copyWith(isFavorite: isFav, userNote: note));
        } catch (e) {
          // 跳过加载失败的菜谱
          debugPrint('Warning: Failed to load recipe ${recipeIndex.id}: $e');
        }
      }

      return recipes;
    } catch (e) {
      throw Exception('Failed to get all recipes: $e');
    }
  }

  @override
  Future<Recipe?> getRecipeById(String id) async {
    try {
      // 1. 优先从Hive读取修改后的菜谱
      final modifiedBox = HiveService.getModifiedRecipesBox();
      if (modifiedBox.containsKey(id)) {
        final recipeJson = modifiedBox.get(id) as Map<dynamic, dynamic>;
        // 深度转换Map<dynamic, dynamic>为Map<String, dynamic>
        final convertedJson = _deepConvertMap(recipeJson);
        final recipe = Recipe.fromJson(convertedJson);

        // 2. 合并收藏和笔记信息
        final isFav = await isFavorite(id);
        final note = await getUserNote(id);

        return recipe.copyWith(isFavorite: isFav, userNote: note);
      }

      // 3. 否则从内置数据加载
      try {
        final recipe = await _bundledLoader.loadRecipe(id);

        // 4. 合并收藏和笔记信息
        final isFav = await isFavorite(id);
        final note = await getUserNote(id);

        return recipe.copyWith(isFavorite: isFav, userNote: note);
      } catch (_) {
        return null;
      }
    } catch (e) {
      throw Exception('Failed to get recipe $id: $e');
    }
  }

  /// 深度转换Map\<dynamic, dynamic\>为Map\<String, dynamic\>
  Map<String, dynamic> _deepConvertMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map<dynamic, dynamic>) {
        result[stringKey] = _deepConvertMap(value);
      } else if (value is List) {
        result[stringKey] = _deepConvertList(value);
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  /// 深度转换List中的Map
  List<dynamic> _deepConvertList(List<dynamic> source) {
    return source.map((item) {
      if (item is Map<dynamic, dynamic>) {
        return _deepConvertMap(item);
      } else if (item is List) {
        return _deepConvertList(item);
      } else {
        return item;
      }
    }).toList();
  }

  @override
  Future<List<Recipe>> getRecipesByCategory(String category) async {
    try {
      // 必须从合并后的菜谱库筛选，否则用户新增或修改的菜谱会被漏掉。
      final normalized = category.trim().toLowerCase();
      final recipes = await getAllRecipes();
      return recipes.where((recipe) {
        return recipe.category.toLowerCase() == normalized ||
            recipe.categoryName.toLowerCase() == normalized;
      }).toList();
    } catch (e) {
      throw Exception('Failed to get recipes by category $category: $e');
    }
  }

  @override
  Future<List<Recipe>> searchRecipes(String query) async {
    try {
      if (query.trim().isEmpty) {
        return getAllRecipes();
      }

      // 1. 获取所有菜谱
      final allRecipes = await getAllRecipes();

      // 2. 过滤：名称、分类名称、食材包含关键词
      final searchTerms = _searchVariants(query);
      return allRecipes.where((recipe) {
        final haystack = _normalizeSearchText(
          [
            recipe.name,
            recipe.categoryName,
            recipe.description ?? '',
            ...recipe.ingredients.map((ingredient) => ingredient.text),
          ].join(' '),
        );
        return searchTerms.any(haystack.contains);
      }).toList();
    } catch (e) {
      throw Exception('Failed to search recipes: $e');
    }
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

  @override
  Future<List<Recipe>> getFavoriteRecipes() async {
    try {
      // 1. 获取收藏 ID 列表
      final favoriteIds = await getFavoriteIds();

      // 2. 加载对应的菜谱
      final List<Recipe> favorites = [];
      for (final id in favoriteIds) {
        try {
          final recipe = await getRecipeById(id);
          if (recipe != null) {
            favorites.add(recipe);
          }
        } catch (e) {
          debugPrint('Warning: Failed to load favorite recipe $id: $e');
        }
      }

      return favorites;
    } catch (e) {
      throw Exception('Failed to get favorite recipes: $e');
    }
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    try {
      // 将Recipe转换为纯Map（Hive可以序列化的基本类型）
      final modifiedBox = HiveService.getModifiedRecipesBox();

      // 手动构建Map，确保所有值都是基本类型
      final recipeMap = <String, dynamic>{
        'schemaVersion': recipe.schemaVersion,
        'id': recipe.id,
        'legacyIds': recipe.legacyIds,
        'name': recipe.name,
        'description': recipe.description,
        'category': recipe.category,
        'categoryName': recipe.categoryName,
        'difficulty': recipe.difficulty,
        'estimatedCaloriesKcal': recipe.estimatedCaloriesKcal,
        'images': recipe.images,
        'externalImages': recipe.externalImages,
        'requirements': recipe.requirements
            .map(
              (item) => {
                'text': item.text,
                'markdown': item.markdown,
                'group': item.group,
                'kind': item.kind,
              },
            )
            .toList(),
        'requirementsMarkdown': recipe.requirementsMarkdown,
        'ingredients': recipe.ingredients
            .map(
              (i) => {
                'name': i.name,
                'text': i.text,
                'optional': i.optional,
                'source': i.source,
                'table': i.table,
              },
            )
            .toList(),
        'tools': recipe.tools,
        'calculationMarkdown': recipe.calculationMarkdown,
        'calculationNotes': recipe.calculationNotes,
        'steps': recipe.steps
            .map(
              (s) => {
                'kind': s.kind,
                'title': s.title,
                'description': s.description,
              },
            )
            .toList(),
        'operationMarkdown': recipe.operationMarkdown,
        'tips': recipe.tips,
        'warnings': recipe.warnings,
        'additionalMarkdown': recipe.additionalMarkdown,
        'hash': recipe.hash,
        'source': recipe.source.name,
        'isFavorite': recipe.isFavorite,
        'userNote': recipe.userNote,
        'createdAt': recipe.createdAt?.toIso8601String(),
        'updatedAt': recipe.updatedAt?.toIso8601String(),
      };

      await modifiedBox.put(recipe.id, recipeMap);
    } catch (e) {
      throw Exception('Failed to save recipe: $e');
    }
  }

  @override
  Future<void> deleteRecipe(String id) async {
    try {
      final modifiedBox = HiveService.getModifiedRecipesBox();

      // 检查该食谱是否存在于用户食谱中
      if (!modifiedBox.containsKey(id)) {
        // 不存在，可能是内置食谱或不存在的食谱
        throw Exception('Recipe not found: $id');
      }

      // 删除用户食谱
      await modifiedBox.delete(id);

      // 同时清理相关的收藏和笔记
      final favBox = HiveService.getFavoritesBox();
      if (favBox.containsKey(id)) {
        await favBox.delete(id);
      }

      final noteBox = HiveService.getUserNotesBox();
      if (noteBox.containsKey(id)) {
        await noteBox.delete(id);
      }
    } catch (e) {
      throw Exception('Failed to delete recipe $id: $e');
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    try {
      final favBox = HiveService.getFavoritesBox();

      if (favBox.containsKey(id)) {
        // 已收藏 → 取消收藏
        await favBox.delete(id);
      } else {
        // 未收藏 → 添加收藏
        await favBox.put(id, id);
      }
    } catch (e) {
      throw Exception('Failed to toggle favorite for $id: $e');
    }
  }

  @override
  Future<bool> isFavorite(String id) async {
    try {
      final favBox = HiveService.getFavoritesBox();
      return favBox.containsKey(id);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateUserNote(String id, String? note) async {
    try {
      final noteBox = HiveService.getUserNotesBox();
      if (note == null || note.isEmpty) {
        // 删除笔记
        await noteBox.delete(id);
      } else {
        // 更新笔记
        await noteBox.put(id, note);
      }
    } catch (e) {
      throw Exception('Failed to update user note for $id: $e');
    }
  }

  @override
  Future<String?> getUserNote(String id) async {
    try {
      final noteBox = HiveService.getUserNotesBox();
      return noteBox.get(id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> getFavoriteIds() async {
    try {
      final favBox = HiveService.getFavoritesBox();
      return favBox.keys.cast<String>().toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> saveRecipes(List<Recipe> recipes) async {
    // T102 不实现批量保存功能
    // 内置菜谱无需导入数据库，直接从 assets 加载即可
    throw UnimplementedError('Batch save is not needed for bundled recipes');
  }
}
