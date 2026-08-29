// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../application/providers/recipe_providers.dart';
import '../../domain/entities/recipe.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/widgets/cached_recipe_image.dart';
import '../../../../core/services/cover_manifest_service.dart';
import '../../../../core/services/recipe_image_policy.dart';
import '../widgets/share_bottom_sheet.dart';
import '../../../ai_chat/infrastructure/repositories/conversation_repository.dart';

/// 菜谱详情页面
///
/// 显示单个菜谱的完整信息，包括图片、食材、步骤等
class RecipeDetailScreen extends ConsumerStatefulWidget {
  final String recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen>
    with TickerProviderStateMixin {
  final TextEditingController _noteController = TextEditingController();
  bool _isDeleting = false;

  // 图片轮播相关
  PageController? _pageController;
  AnimationController? _progressController;
  Timer? _resumeTimer;
  int _currentPage = 0;
  int _totalImages = 0;
  int? _pendingCarouselCount;
  bool _isProgrammaticScroll = false;
  bool _isAutoScrollPaused = false;
  final Map<String, Future<String?>> _aiCoverFutures = {};

  @override
  void dispose() {
    _noteController.dispose();
    _progressController?.dispose();
    _resumeTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _initImageCarousel(int imageCount) {
    if (imageCount <= 1) return;

    _pageController?.dispose();
    _progressController?.dispose();
    _currentPage = 0;
    _totalImages = imageCount;
    _pageController = PageController(initialPage: 0);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progressController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _advanceToNextPage();
      }
    });
    _progressController!.forward();
    _pendingCarouselCount = null;
  }

  void _advanceToNextPage() {
    if (_pageController == null || !_pageController!.hasClients) return;
    _isProgrammaticScroll = true;
    final nextPage = (_currentPage + 1) % _totalImages;
    _pageController!
        .animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .then((_) {
          _isProgrammaticScroll = false;
        });
  }

  void _restartProgress() {
    _isAutoScrollPaused = false;
    _progressController?.forward(from: 0.0);
  }

  void _pauseAutoScrollForInteraction() {
    _progressController?.stop();
    _isAutoScrollPaused = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _restartProgress();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(recipeByIdProvider(widget.recipeId));

    return Scaffold(
      body: recipeAsync.when(
        data: (recipe) => recipe == null
            ? _buildEmptyState(context)
            : _buildContent(context, recipe),
        loading: () => _buildLoadingState(),
        error: (error, stack) => _buildErrorState(context, error),
      ),
    );
  }

  /// 构建内容
  Widget _buildContent(BuildContext context, Recipe recipe) {
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, recipe),
            SliverToBoxAdapter(child: _buildContentSheet(recipe)),
          ],
        ),
        // 底部固定操作栏
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomActionBar(context, recipe),
        ),
      ],
    );
  }

  /// 构建圆角内容面板
  Widget _buildContentSheet(Recipe recipe) {
    return Transform.translate(
      offset: const Offset(0, -24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽手柄
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDisabled.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((recipe.description?.trim().isNotEmpty ?? false) ||
                      recipe.estimatedCaloriesKcal != null) ...[
                    _buildOverview(recipe),
                    const SizedBox(height: 24),
                  ],
                  if (recipe.requirements.isNotEmpty) ...[
                    _buildRequirements(recipe),
                    const SizedBox(height: 24),
                  ],
                  _buildIngredients(recipe),
                  const SizedBox(height: 24),
                  if (recipe.tools.isNotEmpty &&
                      recipe.requirements.isEmpty) ...[
                    _buildTools(recipe),
                    const SizedBox(height: 24),
                  ],
                  _buildSteps(recipe),
                  const SizedBox(height: 24),
                  if (recipe.tips != null && recipe.tips!.isNotEmpty) ...[
                    _buildTips(recipe),
                    const SizedBox(height: 24),
                  ],
                  if (recipe.warnings.isNotEmpty) ...[
                    _buildWarnings(recipe),
                    const SizedBox(height: 24),
                  ],
                  _buildUserNote(recipe),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部操作栏
  Widget _buildBottomActionBar(BuildContext context, Recipe recipe) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -4),
            blurRadius: 16,
            color: AppColors.textPrimary.withValues(alpha: 0.06),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.edit_outlined,
              label: '编辑',
              color: AppColors.textPrimary,
              backgroundColor: AppColors.surfaceAlt,
              onTap: () => context.push('/recipe/${recipe.id}/edit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              icon: Icons.share_outlined,
              label: '分享',
              color: AppColors.surface,
              backgroundColor: AppColors.primary,
              onTap: () => _showShareDialog(context, recipe),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _isDeleting
                ? Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _ActionButton(
                    icon: Icons.delete_outline,
                    label: '删除',
                    color: AppColors.primary,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                    onTap: () => _confirmDeleteRecipe(context, recipe),
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建沉浸式应用栏
  Widget _buildSliverAppBar(BuildContext context, Recipe recipe) {
    final isFavoriteAsync = ref.watch(isFavoriteProvider(recipe.id));
    final coverFuture = _aiCoverFutures.putIfAbsent(
      recipe.id,
      () => CoverManifestService().resolveAiCoverPath(
        recipeId: recipe.id,
        legacyIds: recipe.legacyIds,
        recipeName: recipe.name,
        category: recipe.category,
      ),
    );

    return FutureBuilder<String?>(
      future: coverFuture,
      builder: (context, coverSnapshot) {
        final gallery = _galleryImages(recipe, coverSnapshot.data);
        return SliverAppBar(
          expandedHeight: 380,
          pinned: true,
          backgroundColor: AppColors.primary,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.surface),
                onPressed: () => context.pop(),
              ),
            ),
          ),
          actions: [
            // 收藏爱心
            Padding(
              padding: const EdgeInsets.all(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: isFavoriteAsync.when(
                  data: (isFavorite) => IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite
                          ? const Color(0xFFFF6B6B)
                          : AppColors.surface,
                    ),
                    onPressed: () => _toggleFavorite(recipe.id),
                  ),
                  loading: () => const IconButton(
                    icon: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.surface,
                      ),
                    ),
                    onPressed: null,
                  ),
                  error: (_, __) => IconButton(
                    icon: const Icon(
                      Icons.favorite_border,
                      color: AppColors.surface,
                    ),
                    onPressed: () => _toggleFavorite(recipe.id),
                  ),
                ),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                _buildHeaderImage(recipe, gallery),
                // 渐变遮罩（不拦截触摸，让手势穿透到 PageView）
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.textPrimary.withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.transparent,
                          AppColors.textPrimary.withValues(alpha: 0.75),
                        ],
                        stops: const [0.0, 0.25, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                // 底部信息（不拦截触摸，仅来源标签可点击）
                Positioned(
                  bottom: 32,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: const TextStyle(
                          color: AppColors.surface,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 8,
                              color: Color(0x4D000000),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (recipe.source != RecipeSource.bundled &&
                              recipe.source != RecipeSource.cloud)
                            GestureDetector(
                              onTap: recipe.source == RecipeSource.aiGenerated
                                  ? () => _navigateToSourceConversation(recipe)
                                  : null,
                              child: _GlassTag(
                                label: _getSourceLabel(recipe.source),
                                highlight: true,
                              ),
                            ),
                          _GlassTag(label: recipe.categoryName),
                          if (recipe.estimatedCaloriesKcal != null)
                            _GlassTag(
                              label: '约 ${recipe.estimatedCaloriesKcal} 千卡',
                            ),
                          _GlassTag(label: '★' * recipe.difficulty.clamp(1, 5)),
                          _GlassTag(label: '${recipe.steps.length} 步骤'),
                        ],
                      ),
                    ],
                  ),
                ),
                // 轮播指示器（多图时显示，不拦截触摸）
                if (gallery.length > 1) ...[
                  Positioned(
                    bottom: 108,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(gallery.length, (index) {
                          final isActive = _currentPage == index;
                          if (isActive && _progressController != null) {
                            return _buildActiveDotWithProgress();
                          }
                          return _buildInactiveDot();
                        }),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 80,
                    right: 16,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentPage + 1} / ${gallery.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建头部图片
  Widget _buildHeaderImage(Recipe recipe, List<_GalleryImage> gallery) {
    final imageCount = gallery.length;

    if (imageCount > 1 &&
        imageCount != _totalImages &&
        _pendingCarouselCount != imageCount) {
      _pendingCarouselCount = imageCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initImageCarousel(imageCount);
          setState(() {});
        }
      });
    }

    if (imageCount == 0) {
      return const RecipePlaceholderImage.noImage();
    }

    if (imageCount == 1) {
      return _buildGalleryImage(recipe, gallery.single);
    }

    // 多图轮播
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_isProgrammaticScroll) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _progressController?.stop();
        } else if (notification is ScrollEndNotification) {
          _pauseAutoScrollForInteraction();
        }
        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: imageCount,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
          if (_isProgrammaticScroll) {
            _restartProgress();
          }
        },
        itemBuilder: (context, index) {
          return _buildGalleryImage(recipe, gallery[index]);
        },
      ),
    );
  }

  List<_GalleryImage> _galleryImages(Recipe recipe, String? aiCoverPath) {
    final parts = splitRecipeImages(recipe);
    final result = <_GalleryImage>[];
    if (parts.customCover != null) {
      result.add(_GalleryImage.direct(parts.customCover!));
    } else if (aiCoverPath != null) {
      result.add(_GalleryImage.direct(aiCoverPath));
    }
    for (final entry in parts.details.indexed) {
      result.add(
        isManagedRecipeDetailPath(entry.$2)
            ? _GalleryImage.managedDetail(entry.$1)
            : _GalleryImage.direct(entry.$2),
      );
    }
    return result;
  }

  Widget _buildGalleryImage(Recipe recipe, _GalleryImage image) {
    final path = image.path;
    if (path != null) return _buildImageWidget(path);
    return CachedRecipeImage.detail(
      category: recipe.category,
      recipeId: cachedDetailRecipeId(recipe),
      imageIndex: image.detailIndex!,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorWidget: const RecipePlaceholderImage.notDownloaded(),
    );
  }

  Widget _buildActiveDotWithProgress() {
    return AnimatedBuilder(
      animation: _progressController!,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 18,
          height: 18,
          child: CustomPaint(
            painter: _DotProgressPainter(
              progress: _isAutoScrollPaused ? 0.0 : _progressController!.value,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInactiveDot() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.5),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
    );
  }

  /// 构建图片组件（支持本地、网络、资源、Base64图片）
  Widget _buildImageWidget(String imagePath) {
    // 规范化路径：在Web端将反斜杠转换为正斜杠
    final normalizedPath = kIsWeb ? imagePath.replaceAll('\\', '/') : imagePath;

    // 错误时显示的占位符
    const errorWidget = RecipePlaceholderImage.loadFailed();

    // 判断图片类型
    if (normalizedPath.startsWith('data:image/')) {
      // Base64图片
      try {
        final base64String = normalizedPath.split(',')[1];
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => errorWidget,
        );
      } catch (e) {
        return errorWidget;
      }
    } else if (normalizedPath.startsWith('http://') ||
        normalizedPath.startsWith('https://')) {
      // 网络图片
      return CachedNetworkImage(
        imageUrl: normalizedPath,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppColors.surface,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => errorWidget,
      );
    } else if (normalizedPath.startsWith('assets/')) {
      // 资源图片
      return Image.asset(
        normalizedPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => errorWidget,
      );
    } else if (!kIsWeb) {
      // 本地文件图片（仅非Web端）
      final file = File(normalizedPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => errorWidget,
        );
      } else {
        return errorWidget;
      }
    } else {
      return errorWidget;
    }
  }

  String _getSourceLabel(RecipeSource source) {
    return switch (source) {
      RecipeSource.aiGenerated => 'AI 生成',
      RecipeSource.userCreated => '用户创建',
      RecipeSource.userModified => '已修改',
      RecipeSource.scanned => '扫码导入',
      _ => '',
    };
  }

  Future<void> _navigateToSourceConversation(Recipe recipe) async {
    final repo = ConversationRepository();
    final convId = await repo.findConversationByRecipeId(recipe.id);
    if (!mounted) return;
    if (convId == null) {
      AppSnackBar.show(context, '关联会话已被删除或不存在');
      return;
    }
    // 设置活跃会话并跳转到聊天页
    await repo.setActiveConversationId(convId);
    if (!mounted) return;
    context.go('/ai-chat');
  }

  bool _canDeleteRecipe(Recipe recipe) {
    return switch (recipe.source) {
      RecipeSource.userCreated ||
      RecipeSource.userModified ||
      RecipeSource.scanned ||
      RecipeSource.aiGenerated => true,
      _ => false,
    };
  }

  Future<void> _confirmDeleteRecipe(BuildContext context, Recipe recipe) async {
    if (!_canDeleteRecipe(recipe)) {
      final message = recipe.source == RecipeSource.bundled
          ? '【${recipe.name}】为内置菜谱，无法删除'
          : '【${recipe.name}】暂不支持删除';
      AppSnackBar.show(
        context,
        message,
        backgroundColor: AppColors.warning,
        bottomOffset: AppSnackBar.kDetailBottomOffset,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除菜谱'),
        content: Text('确定要删除「${recipe.name}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteRecipe(context, recipe);
    }
  }

  Future<void> _deleteRecipe(BuildContext context, Recipe recipe) async {
    setState(() => _isDeleting = true);

    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.deleteRecipe(recipe.id);
      ref
        ..invalidate(allRecipesProvider)
        ..invalidate(favoriteRecipesProvider)
        ..invalidate(favoriteIdsProvider)
        ..invalidate(recipeByIdProvider(recipe.id));

      if (!mounted) return;
      AppSnackBar.show(
        context,
        '已删除「${recipe.name}」',
        bottomOffset: AppSnackBar.kDetailBottomOffset,
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '删除失败: $e',
          backgroundColor: AppColors.error,
          bottomOffset: AppSnackBar.kDetailBottomOffset,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  /// 构建食材清单
  Widget _buildOverview(Recipe recipe) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('菜谱简介', style: AppTextStyles.h3),
                const Spacer(),
                if (recipe.estimatedCaloriesKcal != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '约 ${recipe.estimatedCaloriesKcal} 千卡',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (recipe.description?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Text(
                recipe.description!.trim(),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.65,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequirements(Recipe recipe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.secondary),
            const SizedBox(width: 8),
            Text('必备原料和工具', style: AppTextStyles.h2),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: recipe.requirements.map((item) {
                final isTool = item.kind == 'tool';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 21,
                        child: Center(
                          child: Icon(
                            isTool ? Icons.kitchen_outlined : Icons.circle,
                            size: isTool ? 19 : 7,
                            color: isTool
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MarkdownBody(
                          data: item.markdown,
                          shrinkWrap: true,
                          selectable: true,
                          fitContent: true,
                          styleSheet: MarkdownStyleSheet(
                            p: AppTextStyles.bodyMedium,
                          ),
                        ),
                      ),
                      if (isTool)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '工具',
                            style: AppTextStyles.badge.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIngredients(Recipe recipe) {
    final tableIngredients = recipe.ingredients
        .where((ingredient) => ingredient.table.isNotEmpty)
        .toList();
    final listIngredients = recipe.ingredients
        .where((ingredient) => ingredient.table.isEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.restaurant, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(
              recipe.schemaVersion >= 2 ? '用量与计算' : '食材清单',
              style: AppTextStyles.h2,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (recipe.calculationNotes.isNotEmpty) ...[
                  ...recipe.calculationNotes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        note,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                ],
                ...listIngredients.map((ingredient) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 25.2,
                          child: Center(
                            child: Icon(
                              Icons.check_circle_outline,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MarkdownBody(
                            data: ingredient.displayText,
                            shrinkWrap: true,
                            selectable: true,
                            fitContent: true,
                            styleSheet: MarkdownStyleSheet(
                              p: AppTextStyles.ingredient,
                            ),
                            onTapLink: (text, href, title) {
                              if (href == null) return;
                              final uri = Uri.tryParse(href);
                              if (uri != null) {
                                launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                        ),
                        if (ingredient.optional)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '可选',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                if (tableIngredients.isNotEmpty) ...[
                  if (listIngredients.isNotEmpty) const Divider(height: 24),
                  _buildIngredientTable(tableIngredients),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientTable(List<Ingredient> ingredients) {
    final headers = ingredientTableColumns(ingredients);
    if (headers.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 42,
        dataRowMaxHeight: 64,
        horizontalMargin: 8,
        columnSpacing: 24,
        columns: headers
            .map(
              (header) => DataColumn(
                label: Text(
                  header,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
        rows: ingredients
            .map(
              (ingredient) => DataRow(
                cells: headers
                    .map(
                      (header) => DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            ingredientTableCell(ingredient, header),
                            softWrap: true,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 构建工具列表
  Widget _buildTools(Recipe recipe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.kitchen, color: AppColors.secondary, size: 24),
            const SizedBox(width: 8),
            Text('所需工具', style: AppTextStyles.h2),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: recipe.tools.map((tool) {
            return Chip(
              label: Text(
                tool,
                style: TextStyle(fontSize: 13, color: AppColors.secondary),
              ),
              avatar: Icon(Icons.check, size: 16, color: AppColors.secondary),
              backgroundColor: AppColors.secondary.withValues(alpha: 0.12),
              side: BorderSide(
                color: AppColors.secondary.withValues(alpha: 0.4),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 构建制作步骤
  Widget _buildSteps(Recipe recipe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.format_list_numbered,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text('制作步骤', style: AppTextStyles.h2),
          ],
        ),
        const SizedBox(height: 16),
        ..._buildStepWidgets(recipe.steps),
      ],
    );
  }

  List<Widget> _buildStepWidgets(List<CookingStep> steps) {
    final widgets = <Widget>[];
    int stepNumber = 0;
    for (final step in steps) {
      final desc = step.description;
      if (step.kind == 'section') {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 12, bottom: 4),
            child: Text(
              step.title?.trim().isNotEmpty == true ? step.title! : desc,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        );
        continue;
      }
      if (step.kind == 'note') {
        widgets.add(
          Card(
            color: AppColors.info.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: MarkdownBody(data: desc, selectable: true),
            ),
          ),
        );
        continue;
      }
      final headingMatch = RegExp(r'^#{1,4}\s+(.+)$').firstMatch(desc);
      if (headingMatch != null) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 12, bottom: 4),
            child: Text(
              headingMatch.group(1)!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      } else {
        stepNumber++;
        widgets.add(_StepCard(stepNumber: stepNumber, description: desc));
      }
    }
    return widgets;
  }

  /// 构建小贴士
  Widget _buildTips(Recipe recipe) {
    return Card(
      color: AppColors.info.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: AppColors.info, size: 24),
                const SizedBox(width: 8),
                Text('小贴士', style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 12),
            MarkdownBody(
              data: recipe.tips!,
              shrinkWrap: true,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              onTapLink: (text, href, title) {
                if (href == null) return;
                final uri = Uri.tryParse(href);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建警告信息
  Widget _buildWarnings(Recipe recipe) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warning, size: 24),
                const SizedBox(width: 8),
                Text('注意事项', style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 12),
            ...recipe.warnings.map((warning) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MarkdownBody(
                        data: warning,
                        shrinkWrap: true,
                        selectable: true,
                        fitContent: true,
                        styleSheet: MarkdownStyleSheet(
                          p: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          final uri = Uri.tryParse(href);
                          if (uri != null) {
                            launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建用户备注
  Widget _buildUserNote(Recipe recipe) {
    final noteAsync = ref.watch(userNoteProvider(recipe.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note, color: AppColors.secondary, size: 24),
                const SizedBox(width: 8),
                Text('我的备注', style: AppTextStyles.h3),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showNoteDialog(recipe),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('编辑'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            noteAsync.when(
              data: (note) => Text(
                note ?? '暂无备注，点击右上角编辑按钮添加备注',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: note == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontStyle: note == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => Text(
                '加载备注失败',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建加载状态
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在加载菜谱...'),
        ],
      ),
    );
  }

  /// 构建错误状态
  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text('加载失败', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(recipeByIdProvider(widget.recipeId));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.pop(), child: const Text('返回')),
          ],
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text('菜谱不存在', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '该菜谱可能已被删除',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回列表'),
            ),
          ],
        ),
      ),
    );
  }

  /// 切换收藏状态
  Future<void> _toggleFavorite(String recipeId) async {
    try {
      final repository = ref.read(recipeRepositoryProvider);
      await repository.toggleFavorite(recipeId);

      // 刷新相关provider
      ref.invalidate(isFavoriteProvider(recipeId));
      ref.invalidate(favoriteRecipesProvider);
      ref.invalidate(favoriteIdsProvider);
      ref.invalidate(recipeByIdProvider(recipeId));

      if (mounted) {
        AppSnackBar.show(
          context,
          '收藏状态已更新',
          duration: const Duration(seconds: 1),
          bottomOffset: AppSnackBar.kDetailBottomOffset,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '操作失败: $e',
          backgroundColor: AppColors.error,
          bottomOffset: AppSnackBar.kDetailBottomOffset,
        );
      }
    }
  }

  /// 显示备注编辑对话框
  void _showNoteDialog(Recipe recipe) async {
    final currentNote = await ref.read(userNoteProvider(recipe.id).future);
    _noteController.text = currentNote ?? '';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑备注'),
        content: TextField(
          controller: _noteController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '在这里记录你的烹饪心得...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => _saveNote(recipe),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 保存备注
  Future<void> _saveNote(Recipe recipe) async {
    try {
      final repository = ref.read(recipeRepositoryProvider);
      final note = _noteController.text.trim();

      await repository.updateUserNote(recipe.id, note.isEmpty ? null : note);

      // 刷新备注
      ref.invalidate(userNoteProvider(recipe.id));
      ref.invalidate(recipeByIdProvider(widget.recipeId));

      if (mounted) {
        Navigator.of(context).pop();
        AppSnackBar.show(
          context,
          '备注已保存',
          duration: const Duration(seconds: 1),
          bottomOffset: AppSnackBar.kDetailBottomOffset,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '保存失败: $e',
          backgroundColor: AppColors.error,
          bottomOffset: AppSnackBar.kDetailBottomOffset,
        );
      }
    }
  }

  /// 处理菜单操作
  // ignore: unused_element
  void _handleMenuAction(BuildContext context, Recipe recipe, String action) {
    switch (action) {
      case 'edit':
        context.push('/recipe/${recipe.id}/edit');
        break;
      case 'share':
        _showShareDialog(context, recipe);
        break;
    }
  }

  void _showShareDialog(BuildContext context, Recipe recipe) {
    showRecipeShareSheet(context: context, ref: ref, recipe: recipe);
  }
}

class _GalleryImage {
  final String? path;
  final int? detailIndex;

  const _GalleryImage.direct(this.path) : detailIndex = null;
  const _GalleryImage.managedDetail(this.detailIndex) : path = null;
}

/// 毛玻璃标签（图片上的信息标签）
class _GlassTag extends StatelessWidget {
  final String label;
  final bool highlight;

  const _GlassTag({required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.6)
            : AppColors.textPrimary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.surface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 底部操作栏按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 步骤卡片组件
class _StepCard extends StatelessWidget {
  final int stepNumber;
  final String description;

  const _StepCard({required this.stepNumber, required this.description});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 步骤编号
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  '$stepNumber',
                  style: const TextStyle(
                    color: AppColors.surface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 步骤描述
            Expanded(
              child: MarkdownBody(
                data: description,
                shrinkWrap: true,
                selectable: true,
                fitContent: true,
                styleSheet: MarkdownStyleSheet(p: AppTextStyles.cookingStep),
                onTapLink: (text, href, title) {
                  if (href == null) return;
                  final uri = Uri.tryParse(href);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotProgressPainter extends CustomPainter {
  final double progress;

  _DotProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      7.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    canvas.drawCircle(center, 5.0, Paint()..color = Colors.white);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 7.5),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DotProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
