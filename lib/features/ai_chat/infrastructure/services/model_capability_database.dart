import '../../domain/entities/ai_model_config.dart';

/// 模型能力数据库
///
/// 维护常见 AI 模型的能力信息，用于自动填充和匹配
class ModelCapabilityDatabase {
  /// 获取模型能力（根据模型 ID 和服务商）
  ///
  /// [provider] AI 服务商
  /// [modelId] 模型 ID
  /// 返回: 模型能力配置，如果未找到则返回默认配置
  static ModelCapabilities getCapabilities(
    AIProvider provider,
    String modelId,
  ) {
    final key = _normalizeModelId(provider, modelId);

    // 先查找精确匹配
    if (_capabilityMap.containsKey(key)) {
      return _capabilityMap[key]!;
    }

    // 模糊匹配（根据前缀）
    for (final entry in _capabilityMap.entries) {
      if (key.startsWith(entry.key) || entry.key.startsWith(key)) {
        return entry.value;
      }
    }

    // 未找到，返回默认配置
    return _getDefaultCapabilities(provider);
  }

  /// 标准化模型 ID（用于匹配）
  static String _normalizeModelId(AIProvider provider, String modelId) {
    return '${provider.name}:${modelId.toLowerCase().trim()}';
  }

  /// 获取默认能力（根据服务商）
  static ModelCapabilities _getDefaultCapabilities(AIProvider provider) {
    switch (provider) {
      case AIProvider.claude:
        return const ModelCapabilities(
          supportsImageInput: true,
          maxTokens: 4096,
          contextWindow: 200000,
        );
      case AIProvider.openai:
        return const ModelCapabilities(
          supportsImageInput: true,
          maxTokens: 4096,
          contextWindow: 128000,
        );
      case AIProvider.deepseek:
        return const ModelCapabilities(
          supportsImageInput: false,
          maxTokens: 8192,
          contextWindow: 64000,
        );
    }
  }

  /// 模型能力映射表（持续更新）
  static final Map<String, ModelCapabilities> _capabilityMap = {
    // ========== Claude 模型 ==========
    // Claude 3.5 Sonnet 系列
    'claude:claude-3-5-sonnet-20241022': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 8192,
      contextWindow: 200000,
    ),
    'claude:claude-3-5-sonnet-20240620': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 8192,
      contextWindow: 200000,
    ),

    // Claude Sonnet 4 系列（2025 最新）
    'claude:claude-sonnet-4-20250514': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 8192,
      contextWindow: 200000,
    ),
    'claude:claude-sonnet-4-5-20250929': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 8192,
      contextWindow: 200000,
    ),

    // Claude 3 Opus
    'claude:claude-3-opus-20240229': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 200000,
    ),

    // Claude 3 Haiku
    'claude:claude-3-haiku-20240307': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 200000,
    ),

    // ========== OpenAI 模型 ==========
    // GPT-4o 系列
    'openai:gpt-4o': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 128000,
    ),
    'openai:gpt-4o-mini': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 16384,
      contextWindow: 128000,
    ),
    'openai:gpt-4o-2024-11-20': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 16384,
      contextWindow: 128000,
    ),
    'openai:gpt-4o-2024-08-06': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 16384,
      contextWindow: 128000,
    ),

    // GPT-4 Turbo 系列
    'openai:gpt-4-turbo': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 128000,
    ),
    'openai:gpt-4-turbo-preview': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 128000,
    ),

    // GPT-4 Vision
    'openai:gpt-4-vision-preview': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 4096,
      contextWindow: 128000,
    ),

    // GPT-4 标准版
    'openai:gpt-4': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 8192,
      contextWindow: 8192,
    ),

    // GPT-3.5 系列
    'openai:gpt-3.5-turbo': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 4096,
      contextWindow: 16385,
    ),

    // GPT-5 (未来模型，预留)
    'openai:gpt-5': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 16384,
      contextWindow: 256000,
    ),
    'openai:gpt-5-2025-08-07': const ModelCapabilities(
      supportsImageInput: true,
      maxTokens: 16384,
      contextWindow: 256000,
    ),

    // ========== DeepSeek 模型 ==========
    'deepseek:deepseek-v4-flash': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 8192,
      contextWindow: 1000000,
    ),
    'deepseek:deepseek-v4-pro': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 8192,
      contextWindow: 1000000,
    ),
    // 旧模型 ID（兼容期至 2026-07-24，之后将停用）
    'deepseek:deepseek-chat': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 8192,
      contextWindow: 1000000,
    ),
    'deepseek:deepseek-reasoner': const ModelCapabilities(
      supportsImageInput: false,
      maxTokens: 8192,
      contextWindow: 1000000,
    ),
  };

  /// 检查模型 ID 是否在数据库中
  static bool isKnownModel(AIProvider provider, String modelId) {
    final key = _normalizeModelId(provider, modelId);
    return _capabilityMap.containsKey(key) ||
        _capabilityMap.keys.any((k) => key.startsWith(k) || k.startsWith(key));
  }

  /// 获取服务商的所有已知模型
  static List<String> getKnownModels(AIProvider provider) {
    final prefix = '${provider.name}:';
    return _capabilityMap.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toList();
  }
}
