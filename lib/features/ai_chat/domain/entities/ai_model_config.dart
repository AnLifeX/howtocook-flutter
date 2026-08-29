import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

part 'ai_model_config.freezed.dart';
part 'ai_model_config.g.dart';

/// AI 模型配置实体
/// 支持用户在应用内动态添加和管理 AI 模型
///
/// 注意：Hive 序列化使用 ai_providers.dart 中的 _serializeModelConfig() 手动处理
/// 以确保嵌套对象（如 capabilities）被正确转换为 Map
@freezed
class AIModelConfig with _$AIModelConfig {
  const factory AIModelConfig({
    required String id, // 唯一标识（UUID）
    required AIProvider provider, // 服务商
    required String modelId, // 模型 ID（如 claude-3-5-sonnet-20241022）
    required String displayName, // 显示名称
    String? description, // 描述
    @Default(true) bool isEnabled, // 是否启用
    @Default(false) bool useBuiltinKey, // 兼容旧数据；新版本始终使用用户 Key
    String? customApiUrl, // 用户自定义 API 地址
    String? customApiKey, // 用户自定义 API Key
    @Default(AIAPIFormat.auto) AIAPIFormat apiFormat, // 请求/响应协议
    @Default(false) bool isDefault, // 是否为默认模型
    @Default(false) bool isBuiltin, // 是否为内置模型（不可删除）
    // 模型能力（根据官方文档或验证结果填充）
    @Default(ModelCapabilities()) ModelCapabilities capabilities,

    // 验证状态
    @Default(ModelValidationStatus.pending)
    ModelValidationStatus validationStatus,
    DateTime? lastValidated, // 最后验证时间
    String? validationError, // 验证错误信息

    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _AIModelConfig;

  factory AIModelConfig.fromJson(Map<String, dynamic> json) =>
      _$AIModelConfigFromJson(json);
}

/// AI 服务商
enum AIProvider {
  @JsonValue('claude')
  claude,
  @JsonValue('openai')
  openai,
  @JsonValue('deepseek')
  deepseek,
}

/// 模型接口协议。auto 会按服务商和 URL 选择兼容性最好的格式。
enum AIAPIFormat {
  @JsonValue('auto')
  auto,
  @JsonValue('chat_completions')
  chatCompletions,
  @JsonValue('responses')
  responses,
  @JsonValue('anthropic_messages')
  anthropicMessages,
}

extension AIAPIFormatSerialization on AIAPIFormat {
  String get wireValue {
    switch (this) {
      case AIAPIFormat.auto:
        return 'auto';
      case AIAPIFormat.chatCompletions:
        return 'chat_completions';
      case AIAPIFormat.responses:
        return 'responses';
      case AIAPIFormat.anthropicMessages:
        return 'anthropic_messages';
    }
  }
}

/// 模型能力
@freezed
class ModelCapabilities with _$ModelCapabilities {
  const factory ModelCapabilities({
    @Default(false) bool supportsImageInput, // 支持图片输入
    @Default(false) bool supportsFileInput, // 支持文件输入
    @Default(true) bool supportsMCP, // 支持 MCP 工具调用
    @Default(true) bool enableStreaming, // 启用流式输出
    @Default(false) bool enableThinking, // 启用思考链（Extended Thinking）
    @Default(10000) int thinkingBudgetTokens, // 思考预算 token 数
    @Default(4096) int maxTokens, // 最大 token 数
    @Default(128000) int contextWindow, // 上下文窗口大小
  }) = _ModelCapabilities;

  factory ModelCapabilities.fromJson(Map<String, dynamic> json) =>
      _$ModelCapabilitiesFromJson(json);
}

/// 模型验证状态
enum ModelValidationStatus {
  pending, // 待验证
  validating, // 验证中
  valid, // 验证通过
  invalid, // 验证失败
}

/// API 调用记录实体（用于限流统计）
/// 使用 Hive 存储（TypeId: 2）
class APICallRecord extends HiveObject {
  String id;
  String modelId;
  DateTime timestamp;
  bool usedBuiltinKey;
  AIProvider provider;

  APICallRecord({
    required this.id,
    required this.modelId,
    required this.timestamp,
    required this.usedBuiltinKey,
    required this.provider,
  });
}

extension AIModelConfigCapabilities on AIModelConfig {
  bool get supportsImageInputEffective =>
      capabilities.supportsImageInput ||
      modelId.toLowerCase().contains('vision');
}
