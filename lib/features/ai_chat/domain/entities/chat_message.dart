import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// 聊天消息实体
@freezed
class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required MessageRole role,
    required List<MessageContent> content,
    required DateTime timestamp,
    @Default(MessageStatus.sent) MessageStatus status,
    String? modelId, // 消息使用的模型ID（用于显示模型名称）
    String?
    reasoningContent, // AI思考过程（仅deepseek-reasoner等模型, JSON序列化为reasoning_content）
    String? runtimeContext, // 创建消息时附加给模型的动态上下文，不在消息气泡中显示
    List<RecipeCard>? recipeCards, // 菜谱卡片（UI 展示用）
    List<String>? createdRecipeIds, // 该消息创建的食谱ID列表（用于持久化关联）
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

/// 消息内容（支持多模态）
@freezed
class MessageContent with _$MessageContent {
  /// 文本内容
  const factory MessageContent.text({required String text}) = TextContent;

  /// 图片内容
  const factory MessageContent.image({
    required String data, // Base64 编码的图片数据
    String? mimeType, // MIME 类型（如 image/jpeg）
    String? localPath, // 本地路径（用于历史记录）
  }) = ImageContent;

  /// 工具使用（AI 调用工具）
  const factory MessageContent.toolUse({
    required String toolUseId,
    required String name,
    required Map<String, dynamic> input,
  }) = ToolUseContent;

  /// 工具结果（工具调用返回结果）
  const factory MessageContent.toolResult({
    required String toolUseId,
    required Map<String, dynamic> result,
  }) = ToolResultContent;

  factory MessageContent.fromJson(Map<String, dynamic> json) =>
      _$MessageContentFromJson(json);
}

/// 消息角色
enum MessageRole {
  @JsonValue('user')
  user,
  @JsonValue('assistant')
  assistant,
  @JsonValue('system')
  system,
}

/// 消息状态
enum MessageStatus {
  sending, // 发送中
  sent, // 已发送
  error, // 发送失败
}

/// 菜谱卡片实体（嵌入在聊天消息中）
@freezed
class RecipeCard with _$RecipeCard {
  const factory RecipeCard({
    required String recipeId,
    required String recipeName,
    String? imageUrl,
    String? category,
  }) = _RecipeCard;

  factory RecipeCard.fromJson(Map<String, dynamic> json) =>
      _$RecipeCardFromJson(json);
}
