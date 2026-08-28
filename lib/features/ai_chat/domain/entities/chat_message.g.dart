// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ChatMessageImpl _$$ChatMessageImplFromJson(Map<String, dynamic> json) =>
    _$ChatMessageImpl(
      id: json['id'] as String,
      role: $enumDecode(_$MessageRoleEnumMap, json['role']),
      content: (json['content'] as List<dynamic>)
          .map((e) => MessageContent.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: $enumDecodeNullable(_$MessageStatusEnumMap, json['status']) ??
          MessageStatus.sent,
      modelId: json['modelId'] as String?,
      reasoningContent: json['reasoningContent'] as String?,
      runtimeContext: json['runtimeContext'] as String?,
      recipeCards: (json['recipeCards'] as List<dynamic>?)
          ?.map((e) => RecipeCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdRecipeIds: (json['createdRecipeIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$$ChatMessageImplToJson(_$ChatMessageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': _$MessageRoleEnumMap[instance.role]!,
      'content': instance.content,
      'timestamp': instance.timestamp.toIso8601String(),
      'status': _$MessageStatusEnumMap[instance.status]!,
      'modelId': instance.modelId,
      'reasoningContent': instance.reasoningContent,
      'runtimeContext': instance.runtimeContext,
      'recipeCards': instance.recipeCards,
      'createdRecipeIds': instance.createdRecipeIds,
    };

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
  MessageRole.system: 'system',
};

const _$MessageStatusEnumMap = {
  MessageStatus.sending: 'sending',
  MessageStatus.sent: 'sent',
  MessageStatus.error: 'error',
};

_$TextContentImpl _$$TextContentImplFromJson(Map<String, dynamic> json) =>
    _$TextContentImpl(
      text: json['text'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$TextContentImplToJson(_$TextContentImpl instance) =>
    <String, dynamic>{
      'text': instance.text,
      'runtimeType': instance.$type,
    };

_$ImageContentImpl _$$ImageContentImplFromJson(Map<String, dynamic> json) =>
    _$ImageContentImpl(
      data: json['data'] as String,
      mimeType: json['mimeType'] as String?,
      localPath: json['localPath'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ImageContentImplToJson(_$ImageContentImpl instance) =>
    <String, dynamic>{
      'data': instance.data,
      'mimeType': instance.mimeType,
      'localPath': instance.localPath,
      'runtimeType': instance.$type,
    };

_$ToolUseContentImpl _$$ToolUseContentImplFromJson(Map<String, dynamic> json) =>
    _$ToolUseContentImpl(
      toolUseId: json['toolUseId'] as String,
      name: json['name'] as String,
      input: json['input'] as Map<String, dynamic>,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ToolUseContentImplToJson(
        _$ToolUseContentImpl instance) =>
    <String, dynamic>{
      'toolUseId': instance.toolUseId,
      'name': instance.name,
      'input': instance.input,
      'runtimeType': instance.$type,
    };

_$ToolResultContentImpl _$$ToolResultContentImplFromJson(
        Map<String, dynamic> json) =>
    _$ToolResultContentImpl(
      toolUseId: json['toolUseId'] as String,
      result: json['result'] as Map<String, dynamic>,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ToolResultContentImplToJson(
        _$ToolResultContentImpl instance) =>
    <String, dynamic>{
      'toolUseId': instance.toolUseId,
      'result': instance.result,
      'runtimeType': instance.$type,
    };

_$RecipeCardImpl _$$RecipeCardImplFromJson(Map<String, dynamic> json) =>
    _$RecipeCardImpl(
      recipeId: json['recipeId'] as String,
      recipeName: json['recipeName'] as String,
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String?,
    );

Map<String, dynamic> _$$RecipeCardImplToJson(_$RecipeCardImpl instance) =>
    <String, dynamic>{
      'recipeId': instance.recipeId,
      'recipeName': instance.recipeName,
      'imageUrl': instance.imageUrl,
      'category': instance.category,
    };
