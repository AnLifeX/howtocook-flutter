// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_model_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AIModelConfigImpl _$$AIModelConfigImplFromJson(Map<String, dynamic> json) =>
    _$AIModelConfigImpl(
      id: json['id'] as String,
      provider: $enumDecode(_$AIProviderEnumMap, json['provider']),
      modelId: json['modelId'] as String,
      displayName: json['displayName'] as String,
      description: json['description'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? true,
      useBuiltinKey: json['useBuiltinKey'] as bool? ?? false,
      customApiUrl: json['customApiUrl'] as String?,
      customApiKey: json['customApiKey'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      capabilities: json['capabilities'] == null
          ? const ModelCapabilities()
          : ModelCapabilities.fromJson(
              json['capabilities'] as Map<String, dynamic>),
      validationStatus: $enumDecodeNullable(
              _$ModelValidationStatusEnumMap, json['validationStatus']) ??
          ModelValidationStatus.pending,
      lastValidated: json['lastValidated'] == null
          ? null
          : DateTime.parse(json['lastValidated'] as String),
      validationError: json['validationError'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$$AIModelConfigImplToJson(_$AIModelConfigImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'provider': _$AIProviderEnumMap[instance.provider]!,
      'modelId': instance.modelId,
      'displayName': instance.displayName,
      'description': instance.description,
      'isEnabled': instance.isEnabled,
      'useBuiltinKey': instance.useBuiltinKey,
      'customApiUrl': instance.customApiUrl,
      'customApiKey': instance.customApiKey,
      'isDefault': instance.isDefault,
      'isBuiltin': instance.isBuiltin,
      'capabilities': instance.capabilities,
      'validationStatus':
          _$ModelValidationStatusEnumMap[instance.validationStatus]!,
      'lastValidated': instance.lastValidated?.toIso8601String(),
      'validationError': instance.validationError,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

const _$AIProviderEnumMap = {
  AIProvider.claude: 'claude',
  AIProvider.openai: 'openai',
  AIProvider.deepseek: 'deepseek',
};

const _$ModelValidationStatusEnumMap = {
  ModelValidationStatus.pending: 'pending',
  ModelValidationStatus.validating: 'validating',
  ModelValidationStatus.valid: 'valid',
  ModelValidationStatus.invalid: 'invalid',
};

_$ModelCapabilitiesImpl _$$ModelCapabilitiesImplFromJson(
        Map<String, dynamic> json) =>
    _$ModelCapabilitiesImpl(
      supportsImageInput: json['supportsImageInput'] as bool? ?? false,
      supportsFileInput: json['supportsFileInput'] as bool? ?? false,
      supportsMCP: json['supportsMCP'] as bool? ?? true,
      enableStreaming: json['enableStreaming'] as bool? ?? true,
      enableThinking: json['enableThinking'] as bool? ?? false,
      thinkingBudgetTokens:
          (json['thinkingBudgetTokens'] as num?)?.toInt() ?? 10000,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 128000,
    );

Map<String, dynamic> _$$ModelCapabilitiesImplToJson(
        _$ModelCapabilitiesImpl instance) =>
    <String, dynamic>{
      'supportsImageInput': instance.supportsImageInput,
      'supportsFileInput': instance.supportsFileInput,
      'supportsMCP': instance.supportsMCP,
      'enableStreaming': instance.enableStreaming,
      'enableThinking': instance.enableThinking,
      'thinkingBudgetTokens': instance.thinkingBudgetTokens,
      'maxTokens': instance.maxTokens,
      'contextWindow': instance.contextWindow,
    };
