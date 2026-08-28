// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) {
  return _ChatMessage.fromJson(json);
}

/// @nodoc
mixin _$ChatMessage {
  String get id => throw _privateConstructorUsedError;
  MessageRole get role => throw _privateConstructorUsedError;
  List<MessageContent> get content => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;
  MessageStatus get status => throw _privateConstructorUsedError;
  String? get modelId =>
      throw _privateConstructorUsedError; // 消息使用的模型ID（用于显示模型名称）
  String? get reasoningContent =>
      throw _privateConstructorUsedError; // AI思考过程（仅deepseek-reasoner等模型, JSON序列化为reasoning_content）
  String? get runtimeContext =>
      throw _privateConstructorUsedError; // 创建消息时附加给模型的动态上下文，不在消息气泡中显示
  List<RecipeCard>? get recipeCards =>
      throw _privateConstructorUsedError; // 菜谱卡片（UI 展示用）
  List<String>? get createdRecipeIds => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ChatMessageCopyWith<ChatMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatMessageCopyWith<$Res> {
  factory $ChatMessageCopyWith(
          ChatMessage value, $Res Function(ChatMessage) then) =
      _$ChatMessageCopyWithImpl<$Res, ChatMessage>;
  @useResult
  $Res call(
      {String id,
      MessageRole role,
      List<MessageContent> content,
      DateTime timestamp,
      MessageStatus status,
      String? modelId,
      String? reasoningContent,
      String? runtimeContext,
      List<RecipeCard>? recipeCards,
      List<String>? createdRecipeIds});
}

/// @nodoc
class _$ChatMessageCopyWithImpl<$Res, $Val extends ChatMessage>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? timestamp = null,
    Object? status = null,
    Object? modelId = freezed,
    Object? reasoningContent = freezed,
    Object? runtimeContext = freezed,
    Object? recipeCards = freezed,
    Object? createdRecipeIds = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as MessageRole,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as List<MessageContent>,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      modelId: freezed == modelId
          ? _value.modelId
          : modelId // ignore: cast_nullable_to_non_nullable
              as String?,
      reasoningContent: freezed == reasoningContent
          ? _value.reasoningContent
          : reasoningContent // ignore: cast_nullable_to_non_nullable
              as String?,
      runtimeContext: freezed == runtimeContext
          ? _value.runtimeContext
          : runtimeContext // ignore: cast_nullable_to_non_nullable
              as String?,
      recipeCards: freezed == recipeCards
          ? _value.recipeCards
          : recipeCards // ignore: cast_nullable_to_non_nullable
              as List<RecipeCard>?,
      createdRecipeIds: freezed == createdRecipeIds
          ? _value.createdRecipeIds
          : createdRecipeIds // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ChatMessageImplCopyWith<$Res>
    implements $ChatMessageCopyWith<$Res> {
  factory _$$ChatMessageImplCopyWith(
          _$ChatMessageImpl value, $Res Function(_$ChatMessageImpl) then) =
      __$$ChatMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      MessageRole role,
      List<MessageContent> content,
      DateTime timestamp,
      MessageStatus status,
      String? modelId,
      String? reasoningContent,
      String? runtimeContext,
      List<RecipeCard>? recipeCards,
      List<String>? createdRecipeIds});
}

/// @nodoc
class __$$ChatMessageImplCopyWithImpl<$Res>
    extends _$ChatMessageCopyWithImpl<$Res, _$ChatMessageImpl>
    implements _$$ChatMessageImplCopyWith<$Res> {
  __$$ChatMessageImplCopyWithImpl(
      _$ChatMessageImpl _value, $Res Function(_$ChatMessageImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? timestamp = null,
    Object? status = null,
    Object? modelId = freezed,
    Object? reasoningContent = freezed,
    Object? runtimeContext = freezed,
    Object? recipeCards = freezed,
    Object? createdRecipeIds = freezed,
  }) {
    return _then(_$ChatMessageImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _value.role
          : role // ignore: cast_nullable_to_non_nullable
              as MessageRole,
      content: null == content
          ? _value._content
          : content // ignore: cast_nullable_to_non_nullable
              as List<MessageContent>,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      modelId: freezed == modelId
          ? _value.modelId
          : modelId // ignore: cast_nullable_to_non_nullable
              as String?,
      reasoningContent: freezed == reasoningContent
          ? _value.reasoningContent
          : reasoningContent // ignore: cast_nullable_to_non_nullable
              as String?,
      runtimeContext: freezed == runtimeContext
          ? _value.runtimeContext
          : runtimeContext // ignore: cast_nullable_to_non_nullable
              as String?,
      recipeCards: freezed == recipeCards
          ? _value._recipeCards
          : recipeCards // ignore: cast_nullable_to_non_nullable
              as List<RecipeCard>?,
      createdRecipeIds: freezed == createdRecipeIds
          ? _value._createdRecipeIds
          : createdRecipeIds // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatMessageImpl implements _ChatMessage {
  const _$ChatMessageImpl(
      {required this.id,
      required this.role,
      required final List<MessageContent> content,
      required this.timestamp,
      this.status = MessageStatus.sent,
      this.modelId,
      this.reasoningContent,
      this.runtimeContext,
      final List<RecipeCard>? recipeCards,
      final List<String>? createdRecipeIds})
      : _content = content,
        _recipeCards = recipeCards,
        _createdRecipeIds = createdRecipeIds;

  factory _$ChatMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatMessageImplFromJson(json);

  @override
  final String id;
  @override
  final MessageRole role;
  final List<MessageContent> _content;
  @override
  List<MessageContent> get content {
    if (_content is EqualUnmodifiableListView) return _content;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_content);
  }

  @override
  final DateTime timestamp;
  @override
  @JsonKey()
  final MessageStatus status;
  @override
  final String? modelId;
// 消息使用的模型ID（用于显示模型名称）
  @override
  final String? reasoningContent;
// AI思考过程（仅deepseek-reasoner等模型, JSON序列化为reasoning_content）
  @override
  final String? runtimeContext;
// 创建消息时附加给模型的动态上下文，不在消息气泡中显示
  final List<RecipeCard>? _recipeCards;
// 创建消息时附加给模型的动态上下文，不在消息气泡中显示
  @override
  List<RecipeCard>? get recipeCards {
    final value = _recipeCards;
    if (value == null) return null;
    if (_recipeCards is EqualUnmodifiableListView) return _recipeCards;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

// 菜谱卡片（UI 展示用）
  final List<String>? _createdRecipeIds;
// 菜谱卡片（UI 展示用）
  @override
  List<String>? get createdRecipeIds {
    final value = _createdRecipeIds;
    if (value == null) return null;
    if (_createdRecipeIds is EqualUnmodifiableListView)
      return _createdRecipeIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: $content, timestamp: $timestamp, status: $status, modelId: $modelId, reasoningContent: $reasoningContent, runtimeContext: $runtimeContext, recipeCards: $recipeCards, createdRecipeIds: $createdRecipeIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.role, role) || other.role == role) &&
            const DeepCollectionEquality().equals(other._content, _content) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.modelId, modelId) || other.modelId == modelId) &&
            (identical(other.reasoningContent, reasoningContent) ||
                other.reasoningContent == reasoningContent) &&
            (identical(other.runtimeContext, runtimeContext) ||
                other.runtimeContext == runtimeContext) &&
            const DeepCollectionEquality()
                .equals(other._recipeCards, _recipeCards) &&
            const DeepCollectionEquality()
                .equals(other._createdRecipeIds, _createdRecipeIds));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      role,
      const DeepCollectionEquality().hash(_content),
      timestamp,
      status,
      modelId,
      reasoningContent,
      runtimeContext,
      const DeepCollectionEquality().hash(_recipeCards),
      const DeepCollectionEquality().hash(_createdRecipeIds));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      __$$ChatMessageImplCopyWithImpl<_$ChatMessageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatMessageImplToJson(
      this,
    );
  }
}

abstract class _ChatMessage implements ChatMessage {
  const factory _ChatMessage(
      {required final String id,
      required final MessageRole role,
      required final List<MessageContent> content,
      required final DateTime timestamp,
      final MessageStatus status,
      final String? modelId,
      final String? reasoningContent,
      final String? runtimeContext,
      final List<RecipeCard>? recipeCards,
      final List<String>? createdRecipeIds}) = _$ChatMessageImpl;

  factory _ChatMessage.fromJson(Map<String, dynamic> json) =
      _$ChatMessageImpl.fromJson;

  @override
  String get id;
  @override
  MessageRole get role;
  @override
  List<MessageContent> get content;
  @override
  DateTime get timestamp;
  @override
  MessageStatus get status;
  @override
  String? get modelId;
  @override // 消息使用的模型ID（用于显示模型名称）
  String? get reasoningContent;
  @override // AI思考过程（仅deepseek-reasoner等模型, JSON序列化为reasoning_content）
  String? get runtimeContext;
  @override // 创建消息时附加给模型的动态上下文，不在消息气泡中显示
  List<RecipeCard>? get recipeCards;
  @override // 菜谱卡片（UI 展示用）
  List<String>? get createdRecipeIds;
  @override
  @JsonKey(ignore: true)
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MessageContent _$MessageContentFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'text':
      return TextContent.fromJson(json);
    case 'image':
      return ImageContent.fromJson(json);
    case 'toolUse':
      return ToolUseContent.fromJson(json);
    case 'toolResult':
      return ToolResultContent.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'MessageContent',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$MessageContent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(String data, String? mimeType, String? localPath)
        image,
    required TResult Function(
            String toolUseId, String name, Map<String, dynamic> input)
        toolUse,
    required TResult Function(String toolUseId, Map<String, dynamic> result)
        toolResult,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(String data, String? mimeType, String? localPath)? image,
    TResult? Function(
            String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult? Function(String toolUseId, Map<String, dynamic> result)?
        toolResult,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(String data, String? mimeType, String? localPath)? image,
    TResult Function(String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult Function(String toolUseId, Map<String, dynamic> result)? toolResult,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(ImageContent value) image,
    required TResult Function(ToolUseContent value) toolUse,
    required TResult Function(ToolResultContent value) toolResult,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(ImageContent value)? image,
    TResult? Function(ToolUseContent value)? toolUse,
    TResult? Function(ToolResultContent value)? toolResult,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(ImageContent value)? image,
    TResult Function(ToolUseContent value)? toolUse,
    TResult Function(ToolResultContent value)? toolResult,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MessageContentCopyWith<$Res> {
  factory $MessageContentCopyWith(
          MessageContent value, $Res Function(MessageContent) then) =
      _$MessageContentCopyWithImpl<$Res, MessageContent>;
}

/// @nodoc
class _$MessageContentCopyWithImpl<$Res, $Val extends MessageContent>
    implements $MessageContentCopyWith<$Res> {
  _$MessageContentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$TextContentImplCopyWith<$Res> {
  factory _$$TextContentImplCopyWith(
          _$TextContentImpl value, $Res Function(_$TextContentImpl) then) =
      __$$TextContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String text});
}

/// @nodoc
class __$$TextContentImplCopyWithImpl<$Res>
    extends _$MessageContentCopyWithImpl<$Res, _$TextContentImpl>
    implements _$$TextContentImplCopyWith<$Res> {
  __$$TextContentImplCopyWithImpl(
      _$TextContentImpl _value, $Res Function(_$TextContentImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
  }) {
    return _then(_$TextContentImpl(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TextContentImpl implements TextContent {
  const _$TextContentImpl({required this.text, final String? $type})
      : $type = $type ?? 'text';

  factory _$TextContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextContentImplFromJson(json);

  @override
  final String text;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MessageContent.text(text: $text)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextContentImpl &&
            (identical(other.text, text) || other.text == text));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, text);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TextContentImplCopyWith<_$TextContentImpl> get copyWith =>
      __$$TextContentImplCopyWithImpl<_$TextContentImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(String data, String? mimeType, String? localPath)
        image,
    required TResult Function(
            String toolUseId, String name, Map<String, dynamic> input)
        toolUse,
    required TResult Function(String toolUseId, Map<String, dynamic> result)
        toolResult,
  }) {
    return text(this.text);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(String data, String? mimeType, String? localPath)? image,
    TResult? Function(
            String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult? Function(String toolUseId, Map<String, dynamic> result)?
        toolResult,
  }) {
    return text?.call(this.text);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(String data, String? mimeType, String? localPath)? image,
    TResult Function(String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult Function(String toolUseId, Map<String, dynamic> result)? toolResult,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this.text);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(ImageContent value) image,
    required TResult Function(ToolUseContent value) toolUse,
    required TResult Function(ToolResultContent value) toolResult,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(ImageContent value)? image,
    TResult? Function(ToolUseContent value)? toolUse,
    TResult? Function(ToolResultContent value)? toolResult,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(ImageContent value)? image,
    TResult Function(ToolUseContent value)? toolUse,
    TResult Function(ToolResultContent value)? toolResult,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TextContentImplToJson(
      this,
    );
  }
}

abstract class TextContent implements MessageContent {
  const factory TextContent({required final String text}) = _$TextContentImpl;

  factory TextContent.fromJson(Map<String, dynamic> json) =
      _$TextContentImpl.fromJson;

  String get text;
  @JsonKey(ignore: true)
  _$$TextContentImplCopyWith<_$TextContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ImageContentImplCopyWith<$Res> {
  factory _$$ImageContentImplCopyWith(
          _$ImageContentImpl value, $Res Function(_$ImageContentImpl) then) =
      __$$ImageContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String data, String? mimeType, String? localPath});
}

/// @nodoc
class __$$ImageContentImplCopyWithImpl<$Res>
    extends _$MessageContentCopyWithImpl<$Res, _$ImageContentImpl>
    implements _$$ImageContentImplCopyWith<$Res> {
  __$$ImageContentImplCopyWithImpl(
      _$ImageContentImpl _value, $Res Function(_$ImageContentImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? data = null,
    Object? mimeType = freezed,
    Object? localPath = freezed,
  }) {
    return _then(_$ImageContentImpl(
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as String,
      mimeType: freezed == mimeType
          ? _value.mimeType
          : mimeType // ignore: cast_nullable_to_non_nullable
              as String?,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageContentImpl implements ImageContent {
  const _$ImageContentImpl(
      {required this.data, this.mimeType, this.localPath, final String? $type})
      : $type = $type ?? 'image';

  factory _$ImageContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageContentImplFromJson(json);

  @override
  final String data;
// Base64 编码的图片数据
  @override
  final String? mimeType;
// MIME 类型（如 image/jpeg）
  @override
  final String? localPath;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MessageContent.image(data: $data, mimeType: $mimeType, localPath: $localPath)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageContentImpl &&
            (identical(other.data, data) || other.data == data) &&
            (identical(other.mimeType, mimeType) ||
                other.mimeType == mimeType) &&
            (identical(other.localPath, localPath) ||
                other.localPath == localPath));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, data, mimeType, localPath);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageContentImplCopyWith<_$ImageContentImpl> get copyWith =>
      __$$ImageContentImplCopyWithImpl<_$ImageContentImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(String data, String? mimeType, String? localPath)
        image,
    required TResult Function(
            String toolUseId, String name, Map<String, dynamic> input)
        toolUse,
    required TResult Function(String toolUseId, Map<String, dynamic> result)
        toolResult,
  }) {
    return image(data, mimeType, localPath);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(String data, String? mimeType, String? localPath)? image,
    TResult? Function(
            String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult? Function(String toolUseId, Map<String, dynamic> result)?
        toolResult,
  }) {
    return image?.call(data, mimeType, localPath);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(String data, String? mimeType, String? localPath)? image,
    TResult Function(String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult Function(String toolUseId, Map<String, dynamic> result)? toolResult,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(data, mimeType, localPath);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(ImageContent value) image,
    required TResult Function(ToolUseContent value) toolUse,
    required TResult Function(ToolResultContent value) toolResult,
  }) {
    return image(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(ImageContent value)? image,
    TResult? Function(ToolUseContent value)? toolUse,
    TResult? Function(ToolResultContent value)? toolResult,
  }) {
    return image?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(ImageContent value)? image,
    TResult Function(ToolUseContent value)? toolUse,
    TResult Function(ToolResultContent value)? toolResult,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageContentImplToJson(
      this,
    );
  }
}

abstract class ImageContent implements MessageContent {
  const factory ImageContent(
      {required final String data,
      final String? mimeType,
      final String? localPath}) = _$ImageContentImpl;

  factory ImageContent.fromJson(Map<String, dynamic> json) =
      _$ImageContentImpl.fromJson;

  String get data; // Base64 编码的图片数据
  String? get mimeType; // MIME 类型（如 image/jpeg）
  String? get localPath;
  @JsonKey(ignore: true)
  _$$ImageContentImplCopyWith<_$ImageContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ToolUseContentImplCopyWith<$Res> {
  factory _$$ToolUseContentImplCopyWith(_$ToolUseContentImpl value,
          $Res Function(_$ToolUseContentImpl) then) =
      __$$ToolUseContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String toolUseId, String name, Map<String, dynamic> input});
}

/// @nodoc
class __$$ToolUseContentImplCopyWithImpl<$Res>
    extends _$MessageContentCopyWithImpl<$Res, _$ToolUseContentImpl>
    implements _$$ToolUseContentImplCopyWith<$Res> {
  __$$ToolUseContentImplCopyWithImpl(
      _$ToolUseContentImpl _value, $Res Function(_$ToolUseContentImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? toolUseId = null,
    Object? name = null,
    Object? input = null,
  }) {
    return _then(_$ToolUseContentImpl(
      toolUseId: null == toolUseId
          ? _value.toolUseId
          : toolUseId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      input: null == input
          ? _value._input
          : input // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolUseContentImpl implements ToolUseContent {
  const _$ToolUseContentImpl(
      {required this.toolUseId,
      required this.name,
      required final Map<String, dynamic> input,
      final String? $type})
      : _input = input,
        $type = $type ?? 'toolUse';

  factory _$ToolUseContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolUseContentImplFromJson(json);

  @override
  final String toolUseId;
  @override
  final String name;
  final Map<String, dynamic> _input;
  @override
  Map<String, dynamic> get input {
    if (_input is EqualUnmodifiableMapView) return _input;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_input);
  }

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MessageContent.toolUse(toolUseId: $toolUseId, name: $name, input: $input)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolUseContentImpl &&
            (identical(other.toolUseId, toolUseId) ||
                other.toolUseId == toolUseId) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(other._input, _input));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, toolUseId, name,
      const DeepCollectionEquality().hash(_input));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolUseContentImplCopyWith<_$ToolUseContentImpl> get copyWith =>
      __$$ToolUseContentImplCopyWithImpl<_$ToolUseContentImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(String data, String? mimeType, String? localPath)
        image,
    required TResult Function(
            String toolUseId, String name, Map<String, dynamic> input)
        toolUse,
    required TResult Function(String toolUseId, Map<String, dynamic> result)
        toolResult,
  }) {
    return toolUse(toolUseId, name, input);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(String data, String? mimeType, String? localPath)? image,
    TResult? Function(
            String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult? Function(String toolUseId, Map<String, dynamic> result)?
        toolResult,
  }) {
    return toolUse?.call(toolUseId, name, input);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(String data, String? mimeType, String? localPath)? image,
    TResult Function(String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult Function(String toolUseId, Map<String, dynamic> result)? toolResult,
    required TResult orElse(),
  }) {
    if (toolUse != null) {
      return toolUse(toolUseId, name, input);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(ImageContent value) image,
    required TResult Function(ToolUseContent value) toolUse,
    required TResult Function(ToolResultContent value) toolResult,
  }) {
    return toolUse(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(ImageContent value)? image,
    TResult? Function(ToolUseContent value)? toolUse,
    TResult? Function(ToolResultContent value)? toolResult,
  }) {
    return toolUse?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(ImageContent value)? image,
    TResult Function(ToolUseContent value)? toolUse,
    TResult Function(ToolResultContent value)? toolResult,
    required TResult orElse(),
  }) {
    if (toolUse != null) {
      return toolUse(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolUseContentImplToJson(
      this,
    );
  }
}

abstract class ToolUseContent implements MessageContent {
  const factory ToolUseContent(
      {required final String toolUseId,
      required final String name,
      required final Map<String, dynamic> input}) = _$ToolUseContentImpl;

  factory ToolUseContent.fromJson(Map<String, dynamic> json) =
      _$ToolUseContentImpl.fromJson;

  String get toolUseId;
  String get name;
  Map<String, dynamic> get input;
  @JsonKey(ignore: true)
  _$$ToolUseContentImplCopyWith<_$ToolUseContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ToolResultContentImplCopyWith<$Res> {
  factory _$$ToolResultContentImplCopyWith(_$ToolResultContentImpl value,
          $Res Function(_$ToolResultContentImpl) then) =
      __$$ToolResultContentImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String toolUseId, Map<String, dynamic> result});
}

/// @nodoc
class __$$ToolResultContentImplCopyWithImpl<$Res>
    extends _$MessageContentCopyWithImpl<$Res, _$ToolResultContentImpl>
    implements _$$ToolResultContentImplCopyWith<$Res> {
  __$$ToolResultContentImplCopyWithImpl(_$ToolResultContentImpl _value,
      $Res Function(_$ToolResultContentImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? toolUseId = null,
    Object? result = null,
  }) {
    return _then(_$ToolResultContentImpl(
      toolUseId: null == toolUseId
          ? _value.toolUseId
          : toolUseId // ignore: cast_nullable_to_non_nullable
              as String,
      result: null == result
          ? _value._result
          : result // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolResultContentImpl implements ToolResultContent {
  const _$ToolResultContentImpl(
      {required this.toolUseId,
      required final Map<String, dynamic> result,
      final String? $type})
      : _result = result,
        $type = $type ?? 'toolResult';

  factory _$ToolResultContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolResultContentImplFromJson(json);

  @override
  final String toolUseId;
  final Map<String, dynamic> _result;
  @override
  Map<String, dynamic> get result {
    if (_result is EqualUnmodifiableMapView) return _result;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_result);
  }

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MessageContent.toolResult(toolUseId: $toolUseId, result: $result)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolResultContentImpl &&
            (identical(other.toolUseId, toolUseId) ||
                other.toolUseId == toolUseId) &&
            const DeepCollectionEquality().equals(other._result, _result));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, toolUseId, const DeepCollectionEquality().hash(_result));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolResultContentImplCopyWith<_$ToolResultContentImpl> get copyWith =>
      __$$ToolResultContentImplCopyWithImpl<_$ToolResultContentImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String text) text,
    required TResult Function(String data, String? mimeType, String? localPath)
        image,
    required TResult Function(
            String toolUseId, String name, Map<String, dynamic> input)
        toolUse,
    required TResult Function(String toolUseId, Map<String, dynamic> result)
        toolResult,
  }) {
    return toolResult(toolUseId, result);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String text)? text,
    TResult? Function(String data, String? mimeType, String? localPath)? image,
    TResult? Function(
            String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult? Function(String toolUseId, Map<String, dynamic> result)?
        toolResult,
  }) {
    return toolResult?.call(toolUseId, result);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String text)? text,
    TResult Function(String data, String? mimeType, String? localPath)? image,
    TResult Function(String toolUseId, String name, Map<String, dynamic> input)?
        toolUse,
    TResult Function(String toolUseId, Map<String, dynamic> result)? toolResult,
    required TResult orElse(),
  }) {
    if (toolResult != null) {
      return toolResult(toolUseId, result);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(TextContent value) text,
    required TResult Function(ImageContent value) image,
    required TResult Function(ToolUseContent value) toolUse,
    required TResult Function(ToolResultContent value) toolResult,
  }) {
    return toolResult(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(TextContent value)? text,
    TResult? Function(ImageContent value)? image,
    TResult? Function(ToolUseContent value)? toolUse,
    TResult? Function(ToolResultContent value)? toolResult,
  }) {
    return toolResult?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(TextContent value)? text,
    TResult Function(ImageContent value)? image,
    TResult Function(ToolUseContent value)? toolUse,
    TResult Function(ToolResultContent value)? toolResult,
    required TResult orElse(),
  }) {
    if (toolResult != null) {
      return toolResult(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolResultContentImplToJson(
      this,
    );
  }
}

abstract class ToolResultContent implements MessageContent {
  const factory ToolResultContent(
      {required final String toolUseId,
      required final Map<String, dynamic> result}) = _$ToolResultContentImpl;

  factory ToolResultContent.fromJson(Map<String, dynamic> json) =
      _$ToolResultContentImpl.fromJson;

  String get toolUseId;
  Map<String, dynamic> get result;
  @JsonKey(ignore: true)
  _$$ToolResultContentImplCopyWith<_$ToolResultContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RecipeCard _$RecipeCardFromJson(Map<String, dynamic> json) {
  return _RecipeCard.fromJson(json);
}

/// @nodoc
mixin _$RecipeCard {
  String get recipeId => throw _privateConstructorUsedError;
  String get recipeName => throw _privateConstructorUsedError;
  String? get imageUrl => throw _privateConstructorUsedError;
  String? get category => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $RecipeCardCopyWith<RecipeCard> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RecipeCardCopyWith<$Res> {
  factory $RecipeCardCopyWith(
          RecipeCard value, $Res Function(RecipeCard) then) =
      _$RecipeCardCopyWithImpl<$Res, RecipeCard>;
  @useResult
  $Res call(
      {String recipeId, String recipeName, String? imageUrl, String? category});
}

/// @nodoc
class _$RecipeCardCopyWithImpl<$Res, $Val extends RecipeCard>
    implements $RecipeCardCopyWith<$Res> {
  _$RecipeCardCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? recipeId = null,
    Object? recipeName = null,
    Object? imageUrl = freezed,
    Object? category = freezed,
  }) {
    return _then(_value.copyWith(
      recipeId: null == recipeId
          ? _value.recipeId
          : recipeId // ignore: cast_nullable_to_non_nullable
              as String,
      recipeName: null == recipeName
          ? _value.recipeName
          : recipeName // ignore: cast_nullable_to_non_nullable
              as String,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RecipeCardImplCopyWith<$Res>
    implements $RecipeCardCopyWith<$Res> {
  factory _$$RecipeCardImplCopyWith(
          _$RecipeCardImpl value, $Res Function(_$RecipeCardImpl) then) =
      __$$RecipeCardImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String recipeId, String recipeName, String? imageUrl, String? category});
}

/// @nodoc
class __$$RecipeCardImplCopyWithImpl<$Res>
    extends _$RecipeCardCopyWithImpl<$Res, _$RecipeCardImpl>
    implements _$$RecipeCardImplCopyWith<$Res> {
  __$$RecipeCardImplCopyWithImpl(
      _$RecipeCardImpl _value, $Res Function(_$RecipeCardImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? recipeId = null,
    Object? recipeName = null,
    Object? imageUrl = freezed,
    Object? category = freezed,
  }) {
    return _then(_$RecipeCardImpl(
      recipeId: null == recipeId
          ? _value.recipeId
          : recipeId // ignore: cast_nullable_to_non_nullable
              as String,
      recipeName: null == recipeName
          ? _value.recipeName
          : recipeName // ignore: cast_nullable_to_non_nullable
              as String,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      category: freezed == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RecipeCardImpl implements _RecipeCard {
  const _$RecipeCardImpl(
      {required this.recipeId,
      required this.recipeName,
      this.imageUrl,
      this.category});

  factory _$RecipeCardImpl.fromJson(Map<String, dynamic> json) =>
      _$$RecipeCardImplFromJson(json);

  @override
  final String recipeId;
  @override
  final String recipeName;
  @override
  final String? imageUrl;
  @override
  final String? category;

  @override
  String toString() {
    return 'RecipeCard(recipeId: $recipeId, recipeName: $recipeName, imageUrl: $imageUrl, category: $category)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RecipeCardImpl &&
            (identical(other.recipeId, recipeId) ||
                other.recipeId == recipeId) &&
            (identical(other.recipeName, recipeName) ||
                other.recipeName == recipeName) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            (identical(other.category, category) ||
                other.category == category));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, recipeId, recipeName, imageUrl, category);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$RecipeCardImplCopyWith<_$RecipeCardImpl> get copyWith =>
      __$$RecipeCardImplCopyWithImpl<_$RecipeCardImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RecipeCardImplToJson(
      this,
    );
  }
}

abstract class _RecipeCard implements RecipeCard {
  const factory _RecipeCard(
      {required final String recipeId,
      required final String recipeName,
      final String? imageUrl,
      final String? category}) = _$RecipeCardImpl;

  factory _RecipeCard.fromJson(Map<String, dynamic> json) =
      _$RecipeCardImpl.fromJson;

  @override
  String get recipeId;
  @override
  String get recipeName;
  @override
  String? get imageUrl;
  @override
  String? get category;
  @override
  @JsonKey(ignore: true)
  _$$RecipeCardImplCopyWith<_$RecipeCardImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
