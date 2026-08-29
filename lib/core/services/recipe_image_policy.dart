import '../../features/recipe/domain/entities/recipe.dart';

/// 菜谱 JSON 中的图片字段分为“用户封面”和“静态详情图”。
///
/// V1/V2 静态数据的 `images` 全部是详情图；用户创建的菜谱仍沿用第一张
/// 作为封面的约定。把判断集中在这里，避免卡片、详情和编辑页各自猜测。
class RecipeImageParts {
  final String? customCover;
  final List<String> details;

  const RecipeImageParts({required this.customCover, required this.details});
}

RecipeImageParts splitRecipeImages(Recipe recipe) {
  if (recipe.images.isEmpty) {
    return const RecipeImageParts(customCover: null, details: []);
  }

  final first = recipe.images.first;
  final firstIsManagedDetail = isManagedRecipeDetailPath(first);
  final userOwnedSource = switch (recipe.source) {
    RecipeSource.userCreated ||
    RecipeSource.userModified ||
    RecipeSource.scanned ||
    RecipeSource.aiGenerated => true,
    _ => false,
  };

  // 本地文件和 base64 一定是用户显式设置的封面，即使菜谱最初来自内置数据。
  final explicitLocalCover =
      first.startsWith('data:image/') ||
      first.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(first);
  final hasCustomCover =
      explicitLocalCover || (userOwnedSource && !firstIsManagedDetail);

  return RecipeImageParts(
    customCover: hasCustomCover ? first : null,
    details: hasCustomCover ? recipe.images.sublist(1) : List.of(recipe.images),
  );
}

/// 是否为 V1/V2 数据仓库管理的详情图引用。
bool isManagedRecipeDetailPath(String value) {
  final path = value.replaceAll('\\', '/');
  if (path.startsWith('assets/images/') || path.startsWith('images/')) {
    return true;
  }
  if (!path.startsWith('http://') && !path.startsWith('https://')) {
    return false;
  }
  final uri = Uri.tryParse(path);
  if (uri == null) return false;
  return uri.path.contains('/images/');
}

/// V1 使用“分类_短ID”，缓存文件只保留短 ID；V2 UUID 原样使用。
String cachedDetailRecipeId(Recipe recipe) {
  final prefix = '${recipe.category}_';
  return recipe.id.startsWith(prefix)
      ? recipe.id.substring(prefix.length)
      : recipe.id;
}
