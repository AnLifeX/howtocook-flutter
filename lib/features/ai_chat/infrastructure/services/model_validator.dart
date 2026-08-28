import 'package:flutter/foundation.dart';
import '../../domain/entities/ai_model_config.dart';
import 'ai_service_factory.dart';
import 'model_capability_database.dart';

/// 模型验证结果
class ModelValidationResult {
  final bool isValid;
  final String? errorMessage;
  final ModelCapabilities? detectedCapabilities;
  final Map<String, dynamic>? modelInfo;

  const ModelValidationResult({
    required this.isValid,
    this.errorMessage,
    this.detectedCapabilities,
    this.modelInfo,
  });

  factory ModelValidationResult.success({
    ModelCapabilities? capabilities,
    Map<String, dynamic>? modelInfo,
  }) {
    return ModelValidationResult(
      isValid: true,
      detectedCapabilities: capabilities,
      modelInfo: modelInfo,
    );
  }

  factory ModelValidationResult.failure(String errorMessage) {
    return ModelValidationResult(isValid: false, errorMessage: errorMessage);
  }
}

/// 模型验证器
///
/// 功能：
/// - 验证 API Key 和模型 ID 是否有效
/// - 自动检测模型能力
/// - 从数据库匹配已知模型能力
class ModelValidator {
  /// 验证模型配置
  ///
  /// [config] 模型配置
  /// [timeout] 验证超时时间（默认 10 秒）
  /// 返回: 验证结果
  static Future<ModelValidationResult> validate(
    AIModelConfig config, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      debugPrint('🔍 开始验证模型: ${config.displayName} (${config.modelId})');

      // 1. 新版本仅接受用户自己的 API Key。
      if (config.customApiKey == null || config.customApiKey!.trim().isEmpty) {
        return ModelValidationResult.failure('请提供 API Key');
      }

      // 2. 创建 AI Service 并验证
      final service = AIServiceFactory.create(config);

      // 带超时的验证
      final isValidKey = await service.validateApiKey().timeout(
        timeout,
        onTimeout: () => false,
      );

      if (!isValidKey) {
        debugPrint('❌ API Key 验证失败');
        return ModelValidationResult.failure('API Key 无效或网络连接失败');
      }

      debugPrint('✅ API Key 验证成功');

      // 4. 尝试获取模型信息（可能失败，不影响整体验证）
      Map<String, dynamic>? modelInfo;
      try {
        modelInfo = await service.getModelInfo().timeout(
          timeout,
          onTimeout: () => <String, dynamic>{},
        );
        debugPrint('✅ 获取模型信息成功: $modelInfo');
      } catch (e) {
        debugPrint('⚠️  获取模型信息失败（不影响验证）: $e');
      }

      // 5. 检测或匹配模型能力
      final capabilities = _detectCapabilities(config, modelInfo);

      debugPrint('✅ 模型验证成功');
      return ModelValidationResult.success(
        capabilities: capabilities,
        modelInfo: modelInfo,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 模型验证异常: $e');
      debugPrint('Stack trace: $stackTrace');
      return ModelValidationResult.failure('验证失败: $e');
    }
  }

  /// 检测模型能力
  ///
  /// 优先级：
  /// 1. 从 API 返回的 modelInfo 解析
  /// 2. 从能力数据库匹配
  /// 3. 使用默认能力
  static ModelCapabilities _detectCapabilities(
    AIModelConfig config,
    Map<String, dynamic>? modelInfo,
  ) {
    // 1. 尝试从 API 响应解析能力
    if (modelInfo != null && modelInfo.isNotEmpty) {
      final apiCapabilities = _parseCapabilitiesFromApi(
        config.provider,
        modelInfo,
      );
      if (apiCapabilities != null) {
        debugPrint('✅ 从 API 响应解析到能力');
        return apiCapabilities;
      }
    }

    // 2. 从数据库匹配
    final dbCapabilities = ModelCapabilityDatabase.getCapabilities(
      config.provider,
      config.modelId,
    );

    final isKnown = ModelCapabilityDatabase.isKnownModel(
      config.provider,
      config.modelId,
    );

    if (isKnown) {
      debugPrint('✅ 从数据库匹配到已知模型能力');
    } else {
      debugPrint('⚠️  未知模型，使用默认能力');
    }

    return dbCapabilities;
  }

  /// 从 API 响应解析能力
  ///
  /// 不同服务商的响应格式不同，需要分别处理
  static ModelCapabilities? _parseCapabilitiesFromApi(
    AIProvider provider,
    Map<String, dynamic> modelInfo,
  ) {
    try {
      switch (provider) {
        case AIProvider.openai:
          return _parseOpenAICapabilities(modelInfo);
        case AIProvider.claude:
          return _parseClaudeCapabilities(modelInfo);
        case AIProvider.deepseek:
          return _parseDeepSeekCapabilities(modelInfo);
      }
    } catch (e) {
      debugPrint('⚠️  解析 API 能力失败: $e');
      return null;
    }
  }

  /// 解析 OpenAI API 响应
  static ModelCapabilities? _parseOpenAICapabilities(
    Map<String, dynamic> info,
  ) {
    // OpenAI API 返回的 model info 示例：
    // {
    //   "id": "gpt-4o",
    //   "object": "model",
    //   "created": 1234567890,
    //   "owned_by": "openai"
    // }
    // 注意：OpenAI 不直接返回能力信息，需要根据模型 ID 判断
    return null; // 目前无法从 API 直接解析，使用数据库匹配
  }

  /// 解析 Claude API 响应
  static ModelCapabilities? _parseClaudeCapabilities(
    Map<String, dynamic> info,
  ) {
    // Claude API 可能返回模型能力信息
    // 具体格式需要查看实际 API 响应
    return null; // 目前无法从 API 直接解析，使用数据库匹配
  }

  /// 解析 DeepSeek API 响应
  static ModelCapabilities? _parseDeepSeekCapabilities(
    Map<String, dynamic> info,
  ) {
    // DeepSeek API 响应格式
    return null; // 目前无法从 API 直接解析，使用数据库匹配
  }

  /// 快速验证（仅检查配置完整性，不调用 API）
  ///
  /// [config] 模型配置
  /// 返回: (isValid, errorMessage)
  static (bool, String?) quickValidate(AIModelConfig config) {
    // 检查必填字段
    if (config.displayName.trim().isEmpty) {
      return (false, '请输入显示名称');
    }

    if (config.modelId.trim().isEmpty) {
      return (false, '请输入模型 ID');
    }

    // 检查 API Key
    if (config.customApiKey == null || config.customApiKey!.trim().isEmpty) {
      return (false, '请输入 API Key');
    }

    return (true, null);
  }
}
