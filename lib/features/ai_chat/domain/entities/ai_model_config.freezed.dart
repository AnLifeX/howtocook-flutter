// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ai_model_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AIModelConfig _$AIModelConfigFromJson(Map<String, dynamic> json) {
  return _AIModelConfig.fromJson(json);
}

/// @nodoc
mixin _$AIModelConfig {
  String get id => throw _privateConstructorUsedError; // 唯一标识（UUID）
  AIProvider get provider => throw _privateConstructorUsedError; // 服务商
  String get modelId =>
      throw _privateConstructorUsedError; // 模型 ID（如 claude-3-5-sonnet-20241022）
  String get displayName => throw _privateConstructorUsedError; // 显示名称
  String? get description => throw _privateConstructorUsedError; // 描述
  bool get isEnabled => throw _privateConstructorUsedError; // 是否启用
  bool get useBuiltinKey =>
      throw _privateConstructorUsedError; // 兼容旧数据；新版本始终使用用户 Key
  String? get customApiUrl =>
      throw _privateConstructorUsedError; // 用户自定义 API 地址
  String? get customApiKey =>
      throw _privateConstructorUsedError; // 用户自定义 API Key
  AIAPIFormat get apiFormat => throw _privateConstructorUsedError; // 请求/响应协议
  bool get isDefault => throw _privateConstructorUsedError; // 是否为默认模型
  bool get isBuiltin => throw _privateConstructorUsedError; // 是否为内置模型（不可删除）
// 模型能力（根据官方文档或验证结果填充）
  ModelCapabilities get capabilities =>
      throw _privateConstructorUsedError; // 验证状态
  ModelValidationStatus get validationStatus =>
      throw _privateConstructorUsedError;
  DateTime? get lastValidated => throw _privateConstructorUsedError; // 最后验证时间
  String? get validationError => throw _privateConstructorUsedError; // 验证错误信息
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AIModelConfigCopyWith<AIModelConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AIModelConfigCopyWith<$Res> {
  factory $AIModelConfigCopyWith(
          AIModelConfig value, $Res Function(AIModelConfig) then) =
      _$AIModelConfigCopyWithImpl<$Res, AIModelConfig>;
  @useResult
  $Res call(
      {String id,
      AIProvider provider,
      String modelId,
      String displayName,
      String? description,
      bool isEnabled,
      bool useBuiltinKey,
      String? customApiUrl,
      String? customApiKey,
      AIAPIFormat apiFormat,
      bool isDefault,
      bool isBuiltin,
      ModelCapabilities capabilities,
      ModelValidationStatus validationStatus,
      DateTime? lastValidated,
      String? validationError,
      DateTime? createdAt,
      DateTime? updatedAt});

  $ModelCapabilitiesCopyWith<$Res> get capabilities;
}

/// @nodoc
class _$AIModelConfigCopyWithImpl<$Res, $Val extends AIModelConfig>
    implements $AIModelConfigCopyWith<$Res> {
  _$AIModelConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? provider = null,
    Object? modelId = null,
    Object? displayName = null,
    Object? description = freezed,
    Object? isEnabled = null,
    Object? useBuiltinKey = null,
    Object? customApiUrl = freezed,
    Object? customApiKey = freezed,
    Object? apiFormat = null,
    Object? isDefault = null,
    Object? isBuiltin = null,
    Object? capabilities = null,
    Object? validationStatus = null,
    Object? lastValidated = freezed,
    Object? validationError = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      provider: null == provider
          ? _value.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as AIProvider,
      modelId: null == modelId
          ? _value.modelId
          : modelId // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      isEnabled: null == isEnabled
          ? _value.isEnabled
          : isEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      useBuiltinKey: null == useBuiltinKey
          ? _value.useBuiltinKey
          : useBuiltinKey // ignore: cast_nullable_to_non_nullable
              as bool,
      customApiUrl: freezed == customApiUrl
          ? _value.customApiUrl
          : customApiUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      customApiKey: freezed == customApiKey
          ? _value.customApiKey
          : customApiKey // ignore: cast_nullable_to_non_nullable
              as String?,
      apiFormat: null == apiFormat
          ? _value.apiFormat
          : apiFormat // ignore: cast_nullable_to_non_nullable
              as AIAPIFormat,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuiltin: null == isBuiltin
          ? _value.isBuiltin
          : isBuiltin // ignore: cast_nullable_to_non_nullable
              as bool,
      capabilities: null == capabilities
          ? _value.capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as ModelCapabilities,
      validationStatus: null == validationStatus
          ? _value.validationStatus
          : validationStatus // ignore: cast_nullable_to_non_nullable
              as ModelValidationStatus,
      lastValidated: freezed == lastValidated
          ? _value.lastValidated
          : lastValidated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      validationError: freezed == validationError
          ? _value.validationError
          : validationError // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ModelCapabilitiesCopyWith<$Res> get capabilities {
    return $ModelCapabilitiesCopyWith<$Res>(_value.capabilities, (value) {
      return _then(_value.copyWith(capabilities: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$AIModelConfigImplCopyWith<$Res>
    implements $AIModelConfigCopyWith<$Res> {
  factory _$$AIModelConfigImplCopyWith(
          _$AIModelConfigImpl value, $Res Function(_$AIModelConfigImpl) then) =
      __$$AIModelConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      AIProvider provider,
      String modelId,
      String displayName,
      String? description,
      bool isEnabled,
      bool useBuiltinKey,
      String? customApiUrl,
      String? customApiKey,
      AIAPIFormat apiFormat,
      bool isDefault,
      bool isBuiltin,
      ModelCapabilities capabilities,
      ModelValidationStatus validationStatus,
      DateTime? lastValidated,
      String? validationError,
      DateTime? createdAt,
      DateTime? updatedAt});

  @override
  $ModelCapabilitiesCopyWith<$Res> get capabilities;
}

/// @nodoc
class __$$AIModelConfigImplCopyWithImpl<$Res>
    extends _$AIModelConfigCopyWithImpl<$Res, _$AIModelConfigImpl>
    implements _$$AIModelConfigImplCopyWith<$Res> {
  __$$AIModelConfigImplCopyWithImpl(
      _$AIModelConfigImpl _value, $Res Function(_$AIModelConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? provider = null,
    Object? modelId = null,
    Object? displayName = null,
    Object? description = freezed,
    Object? isEnabled = null,
    Object? useBuiltinKey = null,
    Object? customApiUrl = freezed,
    Object? customApiKey = freezed,
    Object? apiFormat = null,
    Object? isDefault = null,
    Object? isBuiltin = null,
    Object? capabilities = null,
    Object? validationStatus = null,
    Object? lastValidated = freezed,
    Object? validationError = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
  }) {
    return _then(_$AIModelConfigImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      provider: null == provider
          ? _value.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as AIProvider,
      modelId: null == modelId
          ? _value.modelId
          : modelId // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
      isEnabled: null == isEnabled
          ? _value.isEnabled
          : isEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      useBuiltinKey: null == useBuiltinKey
          ? _value.useBuiltinKey
          : useBuiltinKey // ignore: cast_nullable_to_non_nullable
              as bool,
      customApiUrl: freezed == customApiUrl
          ? _value.customApiUrl
          : customApiUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      customApiKey: freezed == customApiKey
          ? _value.customApiKey
          : customApiKey // ignore: cast_nullable_to_non_nullable
              as String?,
      apiFormat: null == apiFormat
          ? _value.apiFormat
          : apiFormat // ignore: cast_nullable_to_non_nullable
              as AIAPIFormat,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuiltin: null == isBuiltin
          ? _value.isBuiltin
          : isBuiltin // ignore: cast_nullable_to_non_nullable
              as bool,
      capabilities: null == capabilities
          ? _value.capabilities
          : capabilities // ignore: cast_nullable_to_non_nullable
              as ModelCapabilities,
      validationStatus: null == validationStatus
          ? _value.validationStatus
          : validationStatus // ignore: cast_nullable_to_non_nullable
              as ModelValidationStatus,
      lastValidated: freezed == lastValidated
          ? _value.lastValidated
          : lastValidated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      validationError: freezed == validationError
          ? _value.validationError
          : validationError // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AIModelConfigImpl implements _AIModelConfig {
  const _$AIModelConfigImpl(
      {required this.id,
      required this.provider,
      required this.modelId,
      required this.displayName,
      this.description,
      this.isEnabled = true,
      this.useBuiltinKey = false,
      this.customApiUrl,
      this.customApiKey,
      this.apiFormat = AIAPIFormat.auto,
      this.isDefault = false,
      this.isBuiltin = false,
      this.capabilities = const ModelCapabilities(),
      this.validationStatus = ModelValidationStatus.pending,
      this.lastValidated,
      this.validationError,
      this.createdAt,
      this.updatedAt});

  factory _$AIModelConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$AIModelConfigImplFromJson(json);

  @override
  final String id;
// 唯一标识（UUID）
  @override
  final AIProvider provider;
// 服务商
  @override
  final String modelId;
// 模型 ID（如 claude-3-5-sonnet-20241022）
  @override
  final String displayName;
// 显示名称
  @override
  final String? description;
// 描述
  @override
  @JsonKey()
  final bool isEnabled;
// 是否启用
  @override
  @JsonKey()
  final bool useBuiltinKey;
// 兼容旧数据；新版本始终使用用户 Key
  @override
  final String? customApiUrl;
// 用户自定义 API 地址
  @override
  final String? customApiKey;
// 用户自定义 API Key
  @override
  @JsonKey()
  final AIAPIFormat apiFormat;
// 请求/响应协议
  @override
  @JsonKey()
  final bool isDefault;
// 是否为默认模型
  @override
  @JsonKey()
  final bool isBuiltin;
// 是否为内置模型（不可删除）
// 模型能力（根据官方文档或验证结果填充）
  @override
  @JsonKey()
  final ModelCapabilities capabilities;
// 验证状态
  @override
  @JsonKey()
  final ModelValidationStatus validationStatus;
  @override
  final DateTime? lastValidated;
// 最后验证时间
  @override
  final String? validationError;
// 验证错误信息
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  @override
  String toString() {
    return 'AIModelConfig(id: $id, provider: $provider, modelId: $modelId, displayName: $displayName, description: $description, isEnabled: $isEnabled, useBuiltinKey: $useBuiltinKey, customApiUrl: $customApiUrl, customApiKey: $customApiKey, apiFormat: $apiFormat, isDefault: $isDefault, isBuiltin: $isBuiltin, capabilities: $capabilities, validationStatus: $validationStatus, lastValidated: $lastValidated, validationError: $validationError, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AIModelConfigImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.provider, provider) ||
                other.provider == provider) &&
            (identical(other.modelId, modelId) || other.modelId == modelId) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.isEnabled, isEnabled) ||
                other.isEnabled == isEnabled) &&
            (identical(other.useBuiltinKey, useBuiltinKey) ||
                other.useBuiltinKey == useBuiltinKey) &&
            (identical(other.customApiUrl, customApiUrl) ||
                other.customApiUrl == customApiUrl) &&
            (identical(other.customApiKey, customApiKey) ||
                other.customApiKey == customApiKey) &&
            (identical(other.apiFormat, apiFormat) ||
                other.apiFormat == apiFormat) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.isBuiltin, isBuiltin) ||
                other.isBuiltin == isBuiltin) &&
            (identical(other.capabilities, capabilities) ||
                other.capabilities == capabilities) &&
            (identical(other.validationStatus, validationStatus) ||
                other.validationStatus == validationStatus) &&
            (identical(other.lastValidated, lastValidated) ||
                other.lastValidated == lastValidated) &&
            (identical(other.validationError, validationError) ||
                other.validationError == validationError) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      provider,
      modelId,
      displayName,
      description,
      isEnabled,
      useBuiltinKey,
      customApiUrl,
      customApiKey,
      apiFormat,
      isDefault,
      isBuiltin,
      capabilities,
      validationStatus,
      lastValidated,
      validationError,
      createdAt,
      updatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AIModelConfigImplCopyWith<_$AIModelConfigImpl> get copyWith =>
      __$$AIModelConfigImplCopyWithImpl<_$AIModelConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AIModelConfigImplToJson(
      this,
    );
  }
}

abstract class _AIModelConfig implements AIModelConfig {
  const factory _AIModelConfig(
      {required final String id,
      required final AIProvider provider,
      required final String modelId,
      required final String displayName,
      final String? description,
      final bool isEnabled,
      final bool useBuiltinKey,
      final String? customApiUrl,
      final String? customApiKey,
      final AIAPIFormat apiFormat,
      final bool isDefault,
      final bool isBuiltin,
      final ModelCapabilities capabilities,
      final ModelValidationStatus validationStatus,
      final DateTime? lastValidated,
      final String? validationError,
      final DateTime? createdAt,
      final DateTime? updatedAt}) = _$AIModelConfigImpl;

  factory _AIModelConfig.fromJson(Map<String, dynamic> json) =
      _$AIModelConfigImpl.fromJson;

  @override
  String get id;
  @override // 唯一标识（UUID）
  AIProvider get provider;
  @override // 服务商
  String get modelId;
  @override // 模型 ID（如 claude-3-5-sonnet-20241022）
  String get displayName;
  @override // 显示名称
  String? get description;
  @override // 描述
  bool get isEnabled;
  @override // 是否启用
  bool get useBuiltinKey;
  @override // 兼容旧数据；新版本始终使用用户 Key
  String? get customApiUrl;
  @override // 用户自定义 API 地址
  String? get customApiKey;
  @override // 用户自定义 API Key
  AIAPIFormat get apiFormat;
  @override // 请求/响应协议
  bool get isDefault;
  @override // 是否为默认模型
  bool get isBuiltin;
  @override // 是否为内置模型（不可删除）
// 模型能力（根据官方文档或验证结果填充）
  ModelCapabilities get capabilities;
  @override // 验证状态
  ModelValidationStatus get validationStatus;
  @override
  DateTime? get lastValidated;
  @override // 最后验证时间
  String? get validationError;
  @override // 验证错误信息
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  @JsonKey(ignore: true)
  _$$AIModelConfigImplCopyWith<_$AIModelConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ModelCapabilities _$ModelCapabilitiesFromJson(Map<String, dynamic> json) {
  return _ModelCapabilities.fromJson(json);
}

/// @nodoc
mixin _$ModelCapabilities {
  bool get supportsImageInput => throw _privateConstructorUsedError; // 支持图片输入
  bool get supportsFileInput => throw _privateConstructorUsedError; // 支持文件输入
  bool get supportsMCP => throw _privateConstructorUsedError; // 支持 MCP 工具调用
  bool get enableStreaming => throw _privateConstructorUsedError; // 启用流式输出
  bool get enableThinking =>
      throw _privateConstructorUsedError; // 启用思考链（Extended Thinking）
  int get thinkingBudgetTokens =>
      throw _privateConstructorUsedError; // 思考预算 token 数
  int get maxTokens => throw _privateConstructorUsedError; // 最大 token 数
  int get contextWindow => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ModelCapabilitiesCopyWith<ModelCapabilities> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ModelCapabilitiesCopyWith<$Res> {
  factory $ModelCapabilitiesCopyWith(
          ModelCapabilities value, $Res Function(ModelCapabilities) then) =
      _$ModelCapabilitiesCopyWithImpl<$Res, ModelCapabilities>;
  @useResult
  $Res call(
      {bool supportsImageInput,
      bool supportsFileInput,
      bool supportsMCP,
      bool enableStreaming,
      bool enableThinking,
      int thinkingBudgetTokens,
      int maxTokens,
      int contextWindow});
}

/// @nodoc
class _$ModelCapabilitiesCopyWithImpl<$Res, $Val extends ModelCapabilities>
    implements $ModelCapabilitiesCopyWith<$Res> {
  _$ModelCapabilitiesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? supportsImageInput = null,
    Object? supportsFileInput = null,
    Object? supportsMCP = null,
    Object? enableStreaming = null,
    Object? enableThinking = null,
    Object? thinkingBudgetTokens = null,
    Object? maxTokens = null,
    Object? contextWindow = null,
  }) {
    return _then(_value.copyWith(
      supportsImageInput: null == supportsImageInput
          ? _value.supportsImageInput
          : supportsImageInput // ignore: cast_nullable_to_non_nullable
              as bool,
      supportsFileInput: null == supportsFileInput
          ? _value.supportsFileInput
          : supportsFileInput // ignore: cast_nullable_to_non_nullable
              as bool,
      supportsMCP: null == supportsMCP
          ? _value.supportsMCP
          : supportsMCP // ignore: cast_nullable_to_non_nullable
              as bool,
      enableStreaming: null == enableStreaming
          ? _value.enableStreaming
          : enableStreaming // ignore: cast_nullable_to_non_nullable
              as bool,
      enableThinking: null == enableThinking
          ? _value.enableThinking
          : enableThinking // ignore: cast_nullable_to_non_nullable
              as bool,
      thinkingBudgetTokens: null == thinkingBudgetTokens
          ? _value.thinkingBudgetTokens
          : thinkingBudgetTokens // ignore: cast_nullable_to_non_nullable
              as int,
      maxTokens: null == maxTokens
          ? _value.maxTokens
          : maxTokens // ignore: cast_nullable_to_non_nullable
              as int,
      contextWindow: null == contextWindow
          ? _value.contextWindow
          : contextWindow // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ModelCapabilitiesImplCopyWith<$Res>
    implements $ModelCapabilitiesCopyWith<$Res> {
  factory _$$ModelCapabilitiesImplCopyWith(_$ModelCapabilitiesImpl value,
          $Res Function(_$ModelCapabilitiesImpl) then) =
      __$$ModelCapabilitiesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool supportsImageInput,
      bool supportsFileInput,
      bool supportsMCP,
      bool enableStreaming,
      bool enableThinking,
      int thinkingBudgetTokens,
      int maxTokens,
      int contextWindow});
}

/// @nodoc
class __$$ModelCapabilitiesImplCopyWithImpl<$Res>
    extends _$ModelCapabilitiesCopyWithImpl<$Res, _$ModelCapabilitiesImpl>
    implements _$$ModelCapabilitiesImplCopyWith<$Res> {
  __$$ModelCapabilitiesImplCopyWithImpl(_$ModelCapabilitiesImpl _value,
      $Res Function(_$ModelCapabilitiesImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? supportsImageInput = null,
    Object? supportsFileInput = null,
    Object? supportsMCP = null,
    Object? enableStreaming = null,
    Object? enableThinking = null,
    Object? thinkingBudgetTokens = null,
    Object? maxTokens = null,
    Object? contextWindow = null,
  }) {
    return _then(_$ModelCapabilitiesImpl(
      supportsImageInput: null == supportsImageInput
          ? _value.supportsImageInput
          : supportsImageInput // ignore: cast_nullable_to_non_nullable
              as bool,
      supportsFileInput: null == supportsFileInput
          ? _value.supportsFileInput
          : supportsFileInput // ignore: cast_nullable_to_non_nullable
              as bool,
      supportsMCP: null == supportsMCP
          ? _value.supportsMCP
          : supportsMCP // ignore: cast_nullable_to_non_nullable
              as bool,
      enableStreaming: null == enableStreaming
          ? _value.enableStreaming
          : enableStreaming // ignore: cast_nullable_to_non_nullable
              as bool,
      enableThinking: null == enableThinking
          ? _value.enableThinking
          : enableThinking // ignore: cast_nullable_to_non_nullable
              as bool,
      thinkingBudgetTokens: null == thinkingBudgetTokens
          ? _value.thinkingBudgetTokens
          : thinkingBudgetTokens // ignore: cast_nullable_to_non_nullable
              as int,
      maxTokens: null == maxTokens
          ? _value.maxTokens
          : maxTokens // ignore: cast_nullable_to_non_nullable
              as int,
      contextWindow: null == contextWindow
          ? _value.contextWindow
          : contextWindow // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ModelCapabilitiesImpl implements _ModelCapabilities {
  const _$ModelCapabilitiesImpl(
      {this.supportsImageInput = false,
      this.supportsFileInput = false,
      this.supportsMCP = true,
      this.enableStreaming = true,
      this.enableThinking = false,
      this.thinkingBudgetTokens = 10000,
      this.maxTokens = 4096,
      this.contextWindow = 128000});

  factory _$ModelCapabilitiesImpl.fromJson(Map<String, dynamic> json) =>
      _$$ModelCapabilitiesImplFromJson(json);

  @override
  @JsonKey()
  final bool supportsImageInput;
// 支持图片输入
  @override
  @JsonKey()
  final bool supportsFileInput;
// 支持文件输入
  @override
  @JsonKey()
  final bool supportsMCP;
// 支持 MCP 工具调用
  @override
  @JsonKey()
  final bool enableStreaming;
// 启用流式输出
  @override
  @JsonKey()
  final bool enableThinking;
// 启用思考链（Extended Thinking）
  @override
  @JsonKey()
  final int thinkingBudgetTokens;
// 思考预算 token 数
  @override
  @JsonKey()
  final int maxTokens;
// 最大 token 数
  @override
  @JsonKey()
  final int contextWindow;

  @override
  String toString() {
    return 'ModelCapabilities(supportsImageInput: $supportsImageInput, supportsFileInput: $supportsFileInput, supportsMCP: $supportsMCP, enableStreaming: $enableStreaming, enableThinking: $enableThinking, thinkingBudgetTokens: $thinkingBudgetTokens, maxTokens: $maxTokens, contextWindow: $contextWindow)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ModelCapabilitiesImpl &&
            (identical(other.supportsImageInput, supportsImageInput) ||
                other.supportsImageInput == supportsImageInput) &&
            (identical(other.supportsFileInput, supportsFileInput) ||
                other.supportsFileInput == supportsFileInput) &&
            (identical(other.supportsMCP, supportsMCP) ||
                other.supportsMCP == supportsMCP) &&
            (identical(other.enableStreaming, enableStreaming) ||
                other.enableStreaming == enableStreaming) &&
            (identical(other.enableThinking, enableThinking) ||
                other.enableThinking == enableThinking) &&
            (identical(other.thinkingBudgetTokens, thinkingBudgetTokens) ||
                other.thinkingBudgetTokens == thinkingBudgetTokens) &&
            (identical(other.maxTokens, maxTokens) ||
                other.maxTokens == maxTokens) &&
            (identical(other.contextWindow, contextWindow) ||
                other.contextWindow == contextWindow));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      supportsImageInput,
      supportsFileInput,
      supportsMCP,
      enableStreaming,
      enableThinking,
      thinkingBudgetTokens,
      maxTokens,
      contextWindow);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ModelCapabilitiesImplCopyWith<_$ModelCapabilitiesImpl> get copyWith =>
      __$$ModelCapabilitiesImplCopyWithImpl<_$ModelCapabilitiesImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ModelCapabilitiesImplToJson(
      this,
    );
  }
}

abstract class _ModelCapabilities implements ModelCapabilities {
  const factory _ModelCapabilities(
      {final bool supportsImageInput,
      final bool supportsFileInput,
      final bool supportsMCP,
      final bool enableStreaming,
      final bool enableThinking,
      final int thinkingBudgetTokens,
      final int maxTokens,
      final int contextWindow}) = _$ModelCapabilitiesImpl;

  factory _ModelCapabilities.fromJson(Map<String, dynamic> json) =
      _$ModelCapabilitiesImpl.fromJson;

  @override
  bool get supportsImageInput;
  @override // 支持图片输入
  bool get supportsFileInput;
  @override // 支持文件输入
  bool get supportsMCP;
  @override // 支持 MCP 工具调用
  bool get enableStreaming;
  @override // 启用流式输出
  bool get enableThinking;
  @override // 启用思考链（Extended Thinking）
  int get thinkingBudgetTokens;
  @override // 思考预算 token 数
  int get maxTokens;
  @override // 最大 token 数
  int get contextWindow;
  @override
  @JsonKey(ignore: true)
  _$$ModelCapabilitiesImplCopyWith<_$ModelCapabilitiesImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
