import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../recipe/domain/entities/recipe.dart';
import '../../domain/entities/chat_message.dart';
import '../../infrastructure/services/recipe_recognizer.dart';
import '../../infrastructure/services/tip_recognizer.dart';
import 'recipe_card_widget.dart';
import 'tip_card_widget.dart';

/// 消息气泡组件
///
/// 用于显示聊天消息，支持：
/// - 左右布局（用户消息靠右，AI消息靠左）
/// - Markdown 渲染
/// - 图片展示
/// - 时间戳显示
/// - 操作按钮（复制、重试、编辑、删除）
/// - 模型头像显示
/// - 流式打字效果
/// - 菜谱卡片展示（包括内置和 AI 生成的食谱）
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onEdit;
  final String? modelName;
  final bool isStreaming;
  final String? streamingText;
  final String? streamingReasoningText; // 流式思考内容
  final String? aiStatusText;
  final bool isPending;
  final RecipeRecognizer? recipeRecognizer;
  final TipRecognizer? tipRecognizer;
  final Function(String recipeId)? onRecipeTap;
  final Function(String tipId, String category)? onTipTap;
  final Map<String, Recipe>? createdRecipes;

  const MessageBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onCopy,
    this.onRetry,
    this.onEdit,
    this.modelName,
    this.isStreaming = false,
    this.streamingText,
    this.streamingReasoningText,
    this.aiStatusText,
    this.isPending = false,
    this.recipeRecognizer,
    this.tipRecognizer,
    this.onRecipeTap,
    this.onTipTap,
    this.createdRecipes,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  List<RecipeCardData>? _recognizedRecipes;
  List<TipCardData>? _recognizedTips;
  bool _isReasoningExpanded = false;

  @override
  void initState() {
    super.initState();
    _recognizeContent();
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.content != oldWidget.message.content ||
        widget.streamingText != oldWidget.streamingText) {
      _recognizeContent();
    }
  }

  void _recognizeContent() {
    _recognizeRecipes();
    _recognizeTips();
  }

  /// 识别消息中的菜谱（包括内置和 AI 生成的）
  Future<void> _recognizeRecipes() async {
    // 只对 AI 消息进行菜谱识别
    if (widget.message.role != MessageRole.assistant) {
      return;
    }

    // 获取显示文本
    final displayText = widget.isStreaming && widget.streamingText != null
        ? widget.streamingText!
        : widget.message.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');

    final allRecipes = <RecipeCardData>[];

    try {
      // 1. 优先处理：该消息创建的食谱（不依赖文本匹配）
      if (widget.message.createdRecipeIds != null &&
          widget.message.createdRecipeIds!.isNotEmpty &&
          widget.createdRecipes != null) {
        for (final recipeId in widget.message.createdRecipeIds!) {
          final recipe = widget.createdRecipes![recipeId];
          if (recipe != null) {
            allRecipes.add(RecipeCardData.fromRecipe(recipe));
            debugPrint(
              '✅ Showing created recipe card: ${recipe.name} (ID: $recipeId)',
            );
          }
        }
      }

      // 2. 识别内置菜谱（通过 RecipeRecognizer，依赖文本匹配）
      if (displayText.isNotEmpty && widget.recipeRecognizer != null) {
        final builtinRecipes = await widget.recipeRecognizer!
            .extractRecipesFromText(displayText);
        for (final recipe in builtinRecipes) {
          // 避免重复添加（检查 ID 是否已存在）
          if (!allRecipes.any((r) => r.id == recipe.id)) {
            allRecipes.add(recipe);
          }
        }
      }

      if (mounted) {
        setState(() {
          _recognizedRecipes = allRecipes.isEmpty ? null : allRecipes;
        });
      }
    } catch (e) {
      // 识别失败不影响消息显示
      debugPrint('Recipe recognition error: $e');
    }
  }

  Future<void> _recognizeTips() async {
    if (widget.message.role != MessageRole.assistant) return;
    if (widget.tipRecognizer == null) return;

    final displayText = widget.isStreaming && widget.streamingText != null
        ? widget.streamingText!
        : widget.message.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');

    if (displayText.isEmpty) return;

    try {
      final tips = await widget.tipRecognizer!.extractTipsFromText(displayText);
      if (mounted) {
        setState(() {
          _recognizedTips = tips.isEmpty ? null : tips;
        });
      }
    } catch (e) {
      debugPrint('Tip recognition error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;

    // 获取显示文本：优先使用流式文本，否则使用消息内容
    final displayText = widget.isStreaming && widget.streamingText != null
        ? widget.streamingText!
        : widget.message.content
              .whereType<TextContent>()
              .map((c) => c.text)
              .join('\n');

    // 提取文本内容用于复制
    final textContent = displayText;
    final hasVisibleMessage = widget.isStreaming
        ? (widget.streamingText?.trim().isNotEmpty ?? false)
        : widget.message.content.any(
            (content) =>
                content is! TextContent || content.text.trim().isNotEmpty,
          );
    final statusText =
        widget.aiStatusText ??
        (widget.isPending && !hasVisibleMessage ? '正在处理...' : null);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isUser && statusText != null) _buildAiStatusLabel(statusText),
          if (!isUser) _buildReasoningBlock(),
          if (hasVisibleMessage)
            Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isUser
                      ? MediaQuery.of(context).size.width * 0.88
                      : double.infinity,
                ),
                child: Container(
                  padding: isUser
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                      : EdgeInsets.zero,
                  decoration: isUser
                      ? BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(
                            18,
                          ).copyWith(topRight: const Radius.circular(5)),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isStreaming && widget.streamingText != null)
                        _buildTextContent(widget.streamingText!, isUser)
                      else
                        ...widget.message.content.map(
                          (content) => content.when(
                            text: (text) => _buildTextContent(text, isUser),
                            image: (data, mimeType, localPath) =>
                                _buildImageContent(localPath ?? data, isUser),
                            toolUse: (toolUseId, name, input) =>
                                _buildToolUseContent(name, isUser),
                            toolResult: (toolUseId, result) =>
                                _buildToolResultContent(result, isUser),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (!isUser &&
              _recognizedRecipes != null &&
              _recognizedRecipes!.isNotEmpty)
            ..._recognizedRecipes!.map(
              (recipe) => RecipeCardWidget(
                recipe: recipe,
                onTap: widget.onRecipeTap != null
                    ? () => widget.onRecipeTap!(recipe.id)
                    : null,
              ),
            ),
          if (!isUser && _recognizedTips != null && _recognizedTips!.isNotEmpty)
            ..._recognizedTips!.map(
              (tip) => TipCardWidget(
                tip: tip,
                onTap: widget.onTipTap != null
                    ? () => widget.onTipTap!(tip.id, tip.category)
                    : null,
              ),
            ),
          if (!widget.isPending) ...[
            const SizedBox(height: 4),
            Text(
              _formatTime(widget.message.timestamp),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (!widget.isStreaming && !widget.isPending)
            _buildActionBar(context, textContent, isUser),
        ],
      ),
    );
  }

  /// 构建操作按钮栏
  Widget _buildActionBar(
    BuildContext context,
    String textContent,
    bool isUser,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 复制按钮
          if (textContent.isNotEmpty)
            _buildIconButton(
              icon: Icons.content_copy,
              tooltip: '复制',
              onTap: () {
                if (widget.onCopy != null) {
                  widget.onCopy!();
                } else {
                  Clipboard.setData(ClipboardData(text: textContent));
                  AppSnackBar.show(
                    context,
                    '已复制',
                    duration: const Duration(seconds: 1),
                    bottomOffset: AppSnackBar.kChatBottomOffset,
                  );
                }
              },
            ),

          // 重试按钮（仅AI消息）
          if (!isUser && widget.onRetry != null)
            _buildIconButton(
              icon: Icons.refresh,
              tooltip: '重试',
              onTap: widget.onRetry!,
            ),

          // 编辑按钮（仅用户消息）
          if (isUser && widget.onEdit != null)
            _buildIconButton(
              icon: Icons.edit_outlined,
              tooltip: '编辑',
              onTap: widget.onEdit!,
            ),

          // 删除按钮
          if (widget.onDelete != null)
            _buildIconButton(
              icon: Icons.delete_outline,
              tooltip: '删除',
              onTap: widget.onDelete!,
              color: AppColors.error,
            ),
        ],
      ),
    );
  }

  /// 构建图标按钮
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    final iconColor = color ?? AppColors.textSecondary;
    return IconButton(
      icon: Icon(icon, size: 18),
      color: iconColor,
      tooltip: tooltip,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }

  /// 构建文本内容
  Widget _buildTextContent(String text, bool isUser) {
    return MarkdownBody(
      data: text,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontSize: 15,
          height: 1.5,
        ),
        code: TextStyle(
          backgroundColor: isUser
              ? AppColors.surface.withValues(alpha: 0.2)
              : AppColors.surfaceAlt,
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: isUser
              ? AppColors.surface.withValues(alpha: 0.1)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        h1: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        listBullet: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
        ),
        tableBody: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
        ),
        blockquote: TextStyle(
          color: isUser
              ? AppColors.surface.withValues(alpha: 0.7)
              : AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
        strong: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        em: TextStyle(
          color: isUser ? AppColors.surface : AppColors.textPrimary,
          fontStyle: FontStyle.italic,
        ),
      ),
      onTapLink: (text, url, title) {
        // 处理链接点击（如果需要）
        if (url != null) {
          debugPrint('Link tapped: $url');
        }
      },
    );
  }

  /// 构建图片内容
  Widget _buildImageContent(String imagePath, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imagePath,
          width: 200,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 200,
              height: 150,
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.broken_image, size: 48),
            );
          },
        ),
      ),
    );
  }

  /// 构建工具使用内容
  Widget _buildToolUseContent(String toolName, bool isUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.surface.withValues(alpha: 0.1)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.settings,
            size: 16,
            color: isUser
                ? AppColors.surface.withValues(alpha: 0.7)
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            '调用工具: $toolName',
            style: TextStyle(
              color: isUser
                  ? AppColors.surface.withValues(alpha: 0.7)
                  : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建工具结果内容
  Widget _buildToolResultContent(Map<String, dynamic> result, bool isUser) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.surface.withValues(alpha: 0.1)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '工具结果: ${result.toString()}',
        style: TextStyle(
          color: isUser
              ? AppColors.surface.withValues(alpha: 0.7)
              : AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  /// 构建思考过程块
  Widget _buildReasoningBlock() {
    // 获取思考内容：优先使用流式思考内容（无论是否正在流式），否则使用消息中的 reasoningContent
    // 修复：不依赖 isStreaming 状态，避免流结束后到消息保存之间的空窗期丢失显示
    final reasoningText = (widget.streamingReasoningText?.isNotEmpty ?? false)
        ? widget.streamingReasoningText!
        : widget.message.reasoningContent;

    // 如果没有思考内容，不显示
    if (reasoningText == null || reasoningText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isReasoningExpanded = !_isReasoningExpanded;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行（可点击展开/收起）
                Row(
                  children: [
                    Icon(Icons.psychology, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '思考过程',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isReasoningExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: AppColors.warning,
                    ),
                  ],
                ),

                // 展开时显示完整内容
                if (_isReasoningExpanded) ...[
                  const SizedBox(height: 8),
                  Text(
                    reasoningText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ] else ...[
                  // 收起时显示预览（前50个字符）
                  const SizedBox(height: 4),
                  Text(
                    reasoningText.length > 50
                        ? '${reasoningText.substring(0, 50)}...'
                        : reasoningText,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      height: 1.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiStatusLabel(String statusText) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(statusText),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_statusIcon(statusText), size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                statusText,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String statusText) {
    if (statusText.contains('搜索') || statusText.contains('查询')) {
      return Icons.search;
    }
    if (statusText.contains('食谱') || statusText.contains('草稿')) {
      return Icons.menu_book_outlined;
    }
    if (statusText.contains('收藏')) return Icons.favorite_outline;
    if (statusText.contains('推荐') || statusText.contains('菜单')) {
      return Icons.restaurant_menu;
    }
    if (statusText.contains('思考') || statusText.contains('分析')) {
      return Icons.psychology_outlined;
    }
    if (statusText.contains('压缩')) return Icons.compress;
    return Icons.auto_awesome;
  }

  /// 格式化时间（HH:mm）
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
