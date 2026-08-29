import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/recipe.dart';
import '../../application/providers/recipe_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/cached_recipe_image.dart';
import '../../../../core/services/recipe_image_policy.dart';
import 'share_bottom_sheet.dart';

/// 菜谱卡片组件
///
/// 用于在列表中展示菜谱预览信息
class RecipeCard extends ConsumerWidget {
  final Recipe recipe;

  const RecipeCard({super.key, required this.recipe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: AppColors.textPrimary.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          context.push('/recipe/${recipe.id}');
        },
        onLongPress: () => _showLongPressMenu(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片区域 - 使用Expanded让其灵活适应空间
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(),
                  if (_hasSourceBadge())
                    Positioned(top: 6, right: 6, child: _buildSourceBadge()),
                ],
              ),
            ),

            // 内容区域
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 菜谱名称 - 固定单行，保证所有卡片对齐
                  Text(
                    recipe.name,
                    style: AppTextStyles.recipeTitle.copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),

                  // 难度和收藏
                  Row(
                    children: [
                      // 难度星星
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          recipe.difficulty.clamp(1, 5),
                          (index) => const Icon(
                            Icons.star,
                            color: AppColors.butter,
                            size: 10,
                          ),
                        ),
                      ),

                      const Spacer(),

                      // 收藏图标
                      _buildFavoriteIcon(ref),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 长按弹出操作菜单
  void _showLongPressMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                recipe.name,
                style: AppTextStyles.h5,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/recipe/${recipe.id}/edit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(sheetContext);
                showRecipeShareSheet(
                  context: context,
                  ref: ref,
                  recipe: recipe,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('删除', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteRecipe(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建图片区域 - 使用缓存图片加载
  Widget _buildImage() {
    final imageParts = splitRecipeImages(recipe);

    // 用户显式设置的封面优先。V2 远程详情图不会再被误判为封面。
    final customCover = imageParts.customCover;
    if (customCover != null && _isDirectImagePath(customCover)) {
      return _buildDirectImage(customCover);
    }

    return CachedRecipeImage.coverWithFallback(
      category: recipe.category,
      recipeName: recipe.name,
      fallbackRecipeId: cachedDetailRecipeId(recipe),
      width: double.infinity,
      fit: BoxFit.cover,
      errorWidget: imageParts.details.isEmpty
          ? const RecipePlaceholderImage.noImage(compact: true)
          : const RecipePlaceholderImage.notDownloaded(compact: true),
    );
  }

  bool _isDirectImagePath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('data:image/')) return true;
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    if (path.startsWith('/')) return true;
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) return true;
    return false;
  }

  Widget _buildDirectImage(String path) {
    Widget image;
    if (path.startsWith('data:image/')) {
      final bytes = Uri.parse(path).data!.contentAsBytes();
      image = Image.memory(
        bytes,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _loadFailedPlaceholder(),
      );
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      image = Image.network(
        path,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _loadFailedPlaceholder(),
      );
    } else {
      image = Image.file(
        File(path),
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _loadFailedPlaceholder(),
      );
    }
    return image;
  }

  Widget _loadFailedPlaceholder() =>
      const RecipePlaceholderImage.loadFailed(compact: true);

  /// 构建收藏图标
  Widget _buildFavoriteIcon(WidgetRef ref) {
    final isFavoriteAsync = ref.watch(isFavoriteProvider(recipe.id));

    return isFavoriteAsync.when(
      data: (isFavorite) => IconButton(
        icon: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: isFavorite ? AppColors.error : AppColors.textSecondary,
          size: 16,
        ),
        onPressed: () async {
          // 切换收藏状态
          final repository = ref.read(recipeRepositoryProvider);
          await repository.toggleFavorite(recipe.id);
          // 刷新收藏状态
          ref.invalidate(isFavoriteProvider(recipe.id));
          ref.invalidate(favoriteRecipesProvider);
          ref.invalidate(favoriteIdsProvider);
        },
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, stack) =>
          Icon(Icons.favorite_border, color: AppColors.textSecondary, size: 16),
    );
  }

  /// 检查是否可以删除
  bool _canDeleteRecipe(Recipe recipe) {
    return switch (recipe.source) {
      RecipeSource.userCreated ||
      RecipeSource.userModified ||
      RecipeSource.scanned ||
      RecipeSource.aiGenerated => true,
      _ => false,
    };
  }

  /// 确认删除菜谱
  Future<void> _confirmDeleteRecipe(BuildContext context, WidgetRef ref) async {
    if (!_canDeleteRecipe(recipe)) {
      final message = recipe.source == RecipeSource.bundled
          ? '【${recipe.name}】为内置菜谱，无法删除'
          : '【${recipe.name}】暂不支持删除';
      AppSnackBar.show(context, message, backgroundColor: AppColors.warning);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除菜谱'),
        content: Text('确定要删除「${recipe.name}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _deleteRecipe(context, ref);
    }
  }

  /// 删除菜谱
  Future<void> _deleteRecipe(BuildContext context, WidgetRef ref) async {
    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.deleteRecipe(recipe.id);

      // 刷新相关数据
      ref.invalidate(allRecipesProvider);
      ref.invalidate(favoriteRecipesProvider);

      if (!context.mounted) return;

      AppSnackBar.show(context, '已删除「${recipe.name}」');
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(context, '删除失败: $e', backgroundColor: AppColors.error);
      }
    }
  }

  bool _hasSourceBadge() {
    return recipe.source != RecipeSource.bundled &&
        recipe.source != RecipeSource.cloud;
  }

  Widget _buildSourceBadge() {
    final (IconData icon, String label, Color color) = switch (recipe.source) {
      RecipeSource.aiGenerated => (
        Icons.auto_awesome,
        'AI',
        AppColors.secondary,
      ),
      RecipeSource.userCreated => (Icons.person, '自建', AppColors.primary),
      RecipeSource.scanned => (Icons.qr_code_scanner, '扫码', AppColors.primary),
      RecipeSource.userModified => (Icons.edit, '改', AppColors.plum),
      _ => (Icons.label, '', AppColors.textDisabled),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
