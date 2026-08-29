import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../recipe/domain/entities/recipe.dart';
import '../../tips/domain/entities/tip.dart';
import '../domain/entities/manifest.dart';

/// 菜谱数据加载器。
///
/// 已激活的本地 V2 数据优先；本地数据不存在或不可用时，回退到 APK
/// 中打包的 V1 数据。类名保留为 [BundledDataLoader]，避免影响现有依赖注入。
class BundledDataLoader {
  static const String _localDataDirName = 'recipe_data';
  static const String _remoteBaseUrl =
      'https://anlifex.github.io/HowToCook-assets';

  _DataContext? _cachedContext;

  /// 同步完成后清理上下文，下次读取会切换到刚激活的数据版本。
  void clearCache() => _cachedContext = null;

  Future<Manifest> loadManifest() async => (await _loadContext()).manifest;

  Future<Recipe> loadRecipe(String recipeId) async {
    try {
      final context = await _loadContext();
      final index = _findRecipeIndex(context.manifest, recipeId);
      if (index == null) {
        throw ArgumentError('Unknown recipe ID: $recipeId');
      }

      final jsonData = context.isLocalV2
          ? await _readLocalJson(
              context,
              'recipes/${index.category}/${index.id}.json',
            )
          : await _readAssetJson(
              'assets/recipes/${index.category}/${index.id}.json',
            );

      _normalizeRecipeImages(jsonData, context);
      return Recipe.fromJson(jsonData);
    } catch (e) {
      throw Exception('Failed to load recipe $recipeId: $e');
    }
  }

  Future<List<Recipe>> loadRecipes(List<String> recipeIds) async {
    final recipes = <Recipe>[];
    for (final id in recipeIds) {
      try {
        recipes.add(await loadRecipe(id));
      } catch (e) {
        debugPrint('Warning: Failed to load recipe $id: $e');
      }
    }
    return recipes;
  }

  Future<List<Recipe>> loadAllRecipes() async {
    final manifest = await loadManifest();
    return loadRecipes(manifest.recipes.map((recipe) => recipe.id).toList());
  }

  Future<List<Recipe>> loadRecipesByCategory(String category) async {
    final manifest = await loadManifest();
    return loadRecipes(
      manifest.recipes
          .where((recipe) => recipe.category == category)
          .map((recipe) => recipe.id)
          .toList(),
    );
  }

  Future<Tip> loadTip(String category, String tipId) async {
    try {
      final context = await _loadContext();
      final jsonData = context.isLocalV2
          ? await _readLocalJson(context, 'tips/$category/$tipId.json')
          : await _readAssetJson('assets/tips/$category/$tipId.json');
      return Tip.fromJson(jsonData).copyWith(source: TipSource.bundled);
    } catch (e) {
      throw Exception('Failed to load tip $tipId: $e');
    }
  }

  Future<Tip?> loadTipById(String tipId) async {
    try {
      final manifest = await loadManifest();
      final target = manifest.tips.where((tip) => tip.id == tipId).firstOrNull;
      if (target == null) return null;
      return loadTip(target.category, target.id);
    } catch (e) {
      debugPrint('Warning: Failed to load tip $tipId: $e');
      return null;
    }
  }

  Future<List<Tip>> loadTips(List<TipIndex> indices) async {
    final tips = <Tip>[];
    for (final index in indices) {
      try {
        tips.add(await loadTip(index.category, index.id));
      } catch (e) {
        debugPrint('Warning: Failed to load tip ${index.id}: $e');
      }
    }
    return tips;
  }

  Future<List<Tip>> loadAllTips() async {
    final manifest = await loadManifest();
    return loadTips(manifest.tips);
  }

  Future<List<Tip>> loadTipsByCategory(String category) async {
    final manifest = await loadManifest();
    return loadTips(
      manifest.tips.where((tip) => tip.category == category).toList(),
    );
  }

  Future<_DataContext> _loadContext() async {
    final cached = _cachedContext;
    if (cached != null) return cached;

    if (!kIsWeb) {
      try {
        final documents = await getApplicationDocumentsDirectory();
        final dataRoot = Directory('${documents.path}/$_localDataDirName');
        var manifestFile = File('${dataRoot.path}/manifest.json');
        final previousManifest = File('${manifestFile.path}.previous');
        if (!await manifestFile.exists() && await previousManifest.exists()) {
          manifestFile = previousManifest;
        }
        if (await manifestFile.exists()) {
          final json =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final manifest = Manifest.fromJson(json);
          final versionRoot = Directory(
            '${dataRoot.path}/${manifest.basePath}',
          );
          if (manifest.schemaVersion == 2 &&
              manifest.basePath.isNotEmpty &&
              await versionRoot.exists()) {
            return _cachedContext = _DataContext(
              manifest: manifest,
              dataRoot: dataRoot,
              isLocalV2: true,
            );
          }
        }
      } catch (e) {
        debugPrint(
          'Warning: Failed to load active V2 data, using V1 assets: $e',
        );
      }
    }

    final bundledJson = await _readAssetJson('assets/manifest.json');
    return _cachedContext = _DataContext(
      manifest: Manifest.fromJson(bundledJson),
      isLocalV2: false,
    );
  }

  RecipeIndex? _findRecipeIndex(Manifest manifest, String requestedId) {
    for (final recipe in manifest.recipes) {
      if (recipe.id == requestedId || recipe.legacyIds.contains(requestedId)) {
        return recipe;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _readLocalJson(
    _DataContext context,
    String relativePath,
  ) async {
    final file = File(
      '${context.dataRoot!.path}/${context.manifest.basePath}/$relativePath',
    );
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _readAssetJson(String path) async {
    return jsonDecode(await rootBundle.loadString(path))
        as Map<String, dynamic>;
  }

  void _normalizeRecipeImages(
    Map<String, dynamic> jsonData,
    _DataContext context,
  ) {
    final images = jsonData['images'];
    if (images is! List) return;

    if (context.isLocalV2) {
      jsonData['images'] = images.map((image) {
        final path = image.toString().replaceAll('\\', '/');
        if (path.startsWith('http://') || path.startsWith('https://')) {
          return path;
        }
        return '$_remoteBaseUrl/${context.manifest.basePath}/$path';
      }).toList();
      return;
    }

    jsonData['images'] = images.map((image) {
      var path = image.toString().replaceAll('\\', '/');
      if (!path.startsWith('assets/')) path = 'assets/$path';
      return path;
    }).toList();
  }

  /// 保留给仍使用 V1 路径约定的旧调用方。
  String getRecipePath(String recipeId) {
    final category = _extractLegacyCategory(recipeId);
    return 'assets/recipes/$category/$recipeId.json';
  }

  String getTipPath(String category, String tipId) =>
      'assets/tips/$category/$tipId.json';

  String getImagePath(String relativePath) => relativePath.startsWith('assets/')
      ? relativePath
      : 'assets/$relativePath';

  String _extractLegacyCategory(String recipeId) {
    final parts = recipeId.split('_');
    if (parts.length < 2) {
      throw ArgumentError('Invalid legacy recipe ID: $recipeId');
    }
    return parts.sublist(0, parts.length - 1).join('_');
  }
}

class _DataContext {
  final Manifest manifest;
  final Directory? dataRoot;
  final bool isLocalV2;

  const _DataContext({
    required this.manifest,
    this.dataRoot,
    required this.isLocalV2,
  });
}
