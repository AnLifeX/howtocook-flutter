import '../../domain/entities/ai_model_config.dart';
import '../../domain/services/ai_service.dart';
import '../adapters/claude_adapter.dart';
import '../adapters/openai_adapter.dart';
import '../adapters/deepseek_adapter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AI Service 工厂
///
/// 根据模型配置创建对应的 AI Service 实例
class AIServiceFactory {
  /// 创建 AI Service
  ///
  /// [config] 模型配置
  /// 返回: AIService 实例
  static AIService create(AIModelConfig config) {
    // 获取 API Key 和 URL
    final apiKey = _getApiKey(config);
    final apiUrl = _getApiUrl(config);

    final apiFormat = resolveAPIFormat(config);

    switch (apiFormat) {
      case AIAPIFormat.anthropicMessages:
        // 获取 MCP 服务器 URL (如果配置支持 MCP)
        final mcpUrl = config.capabilities.supportsMCP
            ? dotenv.env['MCP_BASE_URL']
            : null;

        return ClaudeAdapter(
          apiKey: apiKey,
          modelId: config.modelId,
          customApiUrl:
              apiUrl ??
              (config.provider == AIProvider.deepseek
                  ? 'https://api.deepseek.com/anthropic'
                  : null),
          mcpServerUrl: mcpUrl != null ? '$mcpUrl/mcp' : null,
          enableThinking: config.capabilities.enableThinking,
          thinkingBudgetTokens: config.capabilities.thinkingBudgetTokens,
        );

      case AIAPIFormat.responses:
        return OpenAIAdapter(
          apiKey: apiKey,
          modelId: config.modelId,
          customApiUrl:
              apiUrl ??
              (config.provider == AIProvider.deepseek
                  ? 'https://api.deepseek.com'
                  : null),
          apiFormat: AIAPIFormat.responses,
          enableThinking: config.capabilities.enableThinking,
          supportsImageInput: config.supportsImageInputEffective,
        );

      case AIAPIFormat.chatCompletions:
        if (config.provider == AIProvider.deepseek) {
          return DeepSeekAdapter(
            apiKey: apiKey,
            modelId: config.modelId,
            customApiUrl: apiUrl,
            enableThinking: config.capabilities.enableThinking,
            supportsImageInput: config.supportsImageInputEffective,
          );
        }
        return OpenAIAdapter(
          apiKey: apiKey,
          modelId: config.modelId,
          customApiUrl: apiUrl,
          apiFormat: AIAPIFormat.chatCompletions,
          enableThinking: config.capabilities.enableThinking,
          supportsImageInput: config.supportsImageInputEffective,
        );

      case AIAPIFormat.auto:
        throw StateError('API format must be resolved before creating service');
    }
  }

  /// 自动模式优先采用服务商原生且模型覆盖最广的协议。
  /// URL 中包含明确端点时尊重用户配置，方便接入兼容代理。
  static AIAPIFormat resolveAPIFormat(AIModelConfig config) {
    if (config.apiFormat != AIAPIFormat.auto) return config.apiFormat;

    final url = config.customApiUrl?.toLowerCase() ?? '';
    if (url.contains('/anthropic') || url.endsWith('/messages')) {
      return AIAPIFormat.anthropicMessages;
    }
    // OpenCode Go 为 DeepSeek V4 系列公开的是 Chat Completions 端点。
    // 自动模式下即使用户误填了 /responses，也按其模型路由表纠正；
    // 显式选择 Responses 时仍由上方的配置优先级尊重用户选择。
    if (url.contains('opencode.ai/zen/go') &&
        config.modelId.toLowerCase().contains('deepseek')) {
      return AIAPIFormat.chatCompletions;
    }
    if (url.endsWith('/responses') || url.contains('lljby.cn')) {
      return AIAPIFormat.responses;
    }
    if (config.provider == AIProvider.claude) {
      return AIAPIFormat.anthropicMessages;
    }
    return AIAPIFormat.chatCompletions;
  }

  /// 获取 API Key
  ///
  /// 仅使用用户在模型管理中配置的 Key。
  static String _getApiKey(AIModelConfig config) {
    final apiKey = config.customApiKey?.trim();
    if (apiKey != null && apiKey.isNotEmpty) return apiKey;
    throw Exception('Missing user API key for ${config.provider.name}');
  }

  /// 获取 API URL
  ///
  /// 使用用户自定义 URL；为空时由适配器使用服务商官方 URL。
  static String? _getApiUrl(AIModelConfig config) {
    if (config.customApiUrl != null && config.customApiUrl!.isNotEmpty) {
      return config.customApiUrl;
    }
    return null;
  }

  /// 验证模型配置
  ///
  /// [config] 模型配置
  /// 返回: true 表示配置有效并且 API 可用
  static Future<bool> validateConfig(AIModelConfig config) async {
    try {
      final service = create(config);
      return await service.validateApiKey();
    } catch (e) {
      return false;
    }
  }

  /// 新版本不再随 App 发布任何内置模型或共享 Key。
  static List<AIModelConfig> getBuiltinModels() {
    return const [];
  }
}
