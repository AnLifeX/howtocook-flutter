import '../entities/chat_message.dart';
import '../entities/ai_usage_metrics.dart';

/// AI 服务接口
///
/// 统一的 AI 服务抽象接口，支持 Claude、OpenAI、DeepSeek 等多种服务商
abstract class AIService {
  /// 发送消息（流式响应）
  ///
  /// [messages] 对话历史（包含当前消息）
  /// [tools] MCP 工具定义（可选）
  /// [maxTokens] 最大生成 token 数
  ///
  /// 返回: Stream\<String\> - 流式文本响应
  Stream<String> sendMessage({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    void Function(String reasoningContent)? onReasoningContent,
    void Function(AIUsageMetrics usage)? onUsage,
  });

  /// 发送消息（非流式响应）
  ///
  /// [messages] 对话历史（包含当前消息）
  /// [tools] MCP 工具定义（可选）
  /// [maxTokens] 最大生成 token 数
  /// [onTextChunk] 文本分块回调（可选，用于在等待完整响应时实时显示文本）
  /// [onReasoningContent] 推理内容回调（可选，用于显示 AI 的思考过程）
  ///
  /// 返回: ChatMessage - 完整的 AI 响应消息
  Future<ChatMessage> sendMessageSync({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    void Function(String textChunk)? onTextChunk,
    void Function(String reasoningContent)? onReasoningContent,
    void Function(AIUsageMetrics usage)? onUsage,
  });

  /// 验证 API Key 是否有效
  ///
  /// 返回: true 表示有效，false 表示无效
  Future<bool> validateApiKey();

  /// 获取模型信息
  ///
  /// 返回: Map\<String, dynamic\> - 模型信息（名称、能力等）
  Future<Map<String, dynamic>> getModelInfo();
}
