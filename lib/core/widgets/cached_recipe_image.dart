import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:howtocook/core/services/image_cache_service.dart';

/// 缓存食谱图片组件
/// 优先从本地缓存加载，缓存不存在则从 assets 加载，都不存在则显示占位图
class CachedRecipeImage extends ConsumerWidget {
  final String category;
  final String? recipeName; // 封面图使用
  final String? recipeId; // 详情图使用
  final int? imageIndex; // 详情图索引
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  // 封面图降级时使用的 recipeId（去掉分类前缀后的短 ID）
  final String? _fallbackRecipeId;

  const CachedRecipeImage.cover({
    super.key,
    required this.category,
    required this.recipeName,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  }) : recipeId = null,
       imageIndex = null,
       _fallbackRecipeId = null;

  const CachedRecipeImage.detail({
    super.key,
    required this.category,
    required this.recipeId,
    required this.imageIndex,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  }) : recipeName = null,
       _fallbackRecipeId = null;

  /// 封面图，带详情图降级（封面不存在时显示详情图第一张）。
  const CachedRecipeImage.coverWithFallback({
    super.key,
    required this.category,
    required this.recipeName,
    required String fallbackRecipeId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  }) : recipeId = null,
       imageIndex = null,
       _fallbackRecipeId = fallbackRecipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageCacheService = ref.read(imageCacheServiceProvider.notifier);

    return FutureBuilder<String?>(
      future: _getCachePath(imageCacheService),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return _buildFileImage(context, snapshot.data!, imageCacheService);
        }

        final assetPath = _getAssetPath();
        if (assetPath != null) {
          return _buildAssetImage(context, assetPath, imageCacheService);
        }

        // 封面图降级：尝试详情图第一张
        if (_fallbackRecipeId != null) {
          return CachedRecipeImage.detail(
            category: category,
            recipeId: _fallbackRecipeId,
            imageIndex: 0,
            width: width,
            height: height,
            fit: fit,
            borderRadius: borderRadius,
            errorWidget: errorWidget ?? _buildDefaultPlaceholder(context),
          );
        }

        return errorWidget ?? _buildDefaultPlaceholder(context);
      },
    );
  }

  Future<String?> _getCachePath(ImageCacheService service) async {
    if (recipeName != null) {
      return await service.getCoverImagePath(category, recipeName!);
    } else if (recipeId != null && imageIndex != null) {
      return await service.getDetailImagePath(category, recipeId!, imageIndex!);
    }
    return null;
  }

  String? _getAssetPath() {
    if (recipeName != null) {
      return 'assets/covers/$category/$recipeName.webp';
    } else if (recipeId != null && imageIndex != null) {
      return 'assets/images/$category/${recipeId}_$imageIndex.webp';
    }
    return null;
  }

  Widget _buildFileImage(
    BuildContext context,
    String filePath,
    ImageCacheService service,
  ) {
    Widget image = Image.file(
      File(filePath),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        final assetPath = _getAssetPath();
        if (assetPath != null) {
          return _buildAssetImage(context, assetPath, service);
        }
        if (_fallbackRecipeId != null) {
          return CachedRecipeImage.detail(
            category: category,
            recipeId: _fallbackRecipeId,
            imageIndex: 0,
            width: width,
            height: height,
            fit: fit,
            borderRadius: borderRadius,
            errorWidget: errorWidget ?? _buildDefaultPlaceholder(context),
          );
        }
        return errorWidget ?? _buildDefaultPlaceholder(context);
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _buildAssetImage(
    BuildContext context,
    String assetPath,
    ImageCacheService service,
  ) {
    Widget image = Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (_fallbackRecipeId != null) {
          return CachedRecipeImage.detail(
            category: category,
            recipeId: _fallbackRecipeId,
            imageIndex: 0,
            width: width,
            height: height,
            fit: fit,
            borderRadius: borderRadius,
            errorWidget: errorWidget ?? _buildDefaultPlaceholder(context),
          );
        }
        return errorWidget ?? _buildDefaultPlaceholder(context);
      },
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _buildDefaultPlaceholder(BuildContext context) {
    return RecipePlaceholderImage.notDownloaded(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

enum RecipeImagePlaceholderType { noImage, notDownloaded, loadFailed }

/// 占位图Widget - 用于显示默认占位图
class RecipePlaceholderImage extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final IconData icon;
  final String? text;
  final String? subtitle;
  final bool compact;
  final RecipeImagePlaceholderType type;

  const RecipePlaceholderImage({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.icon = Icons.restaurant_menu,
    this.text,
    this.subtitle,
    this.compact = false,
    this.type = RecipeImagePlaceholderType.noImage,
  });

  const RecipePlaceholderImage.noImage({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.compact = false,
  }) : icon = Icons.add_photo_alternate_outlined,
       text = '暂无图片',
       subtitle = '点击编辑上传一张',
       type = RecipeImagePlaceholderType.noImage;

  const RecipePlaceholderImage.notDownloaded({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.compact = false,
  }) : icon = Icons.cloud_download_outlined,
       text = '图片未下载',
       subtitle = '可前往数据同步页面下载',
       type = RecipeImagePlaceholderType.notDownloaded;

  const RecipePlaceholderImage.loadFailed({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.compact = false,
  }) : icon = Icons.broken_image_outlined,
       text = '图片加载失败',
       subtitle = '请检查图片文件或网络连接',
       type = RecipeImagePlaceholderType.loadFailed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
        borderRadius: borderRadius,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: compact ? 40 : 64,
            color: Theme.of(
              context,
            ).colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
          ),
          if (!compact && text != null) ...[
            const SizedBox(height: 8),
            Text(
              text!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
