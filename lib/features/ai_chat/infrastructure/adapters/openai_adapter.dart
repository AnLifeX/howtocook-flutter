import 'package:dio/dio.dart';
import 'dart:convert';
import '../../domain/entities/ai_model_config.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/ai_usage_metrics.dart';
import '../../domain/services/ai_service.dart';

/// OpenAI API 适配器
///
/// 支持 GPT-4、GPT-3.5 等 OpenAI 模型
/// 支持自定义 API URL（用于代理或非官方端点）
class OpenAIAdapter implements AIService {
  final Dio _dio;
  final String apiKey;
  final String modelId;
  final String? customApiUrl;
  final AIAPIFormat apiFormat;

  /// 默认 OpenAI API 地址
  static const String defaultApiUrl = 'https://api.openai.com/v1';

  OpenAIAdapter({
    required this.apiKey,
    required this.modelId,
    this.customApiUrl,
    this.apiFormat = AIAPIFormat.auto,
  }) : _dio = Dio() {
    final baseUrl = _normalizeBaseUrl(customApiUrl ?? defaultApiUrl);
    _dio.options.baseUrl = baseUrl;
    _dio.options.headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 300);
  }

  bool get _usesResponses =>
      apiFormat == AIAPIFormat.responses ||
      (apiFormat == AIAPIFormat.auto &&
          ((customApiUrl?.toLowerCase().endsWith('/responses') ?? false) ||
              (customApiUrl?.contains('lljby.cn') ?? false)));

  String get _endpoint => _usesResponses ? '/responses' : '/chat/completions';

  @override
  Stream<String> sendMessage({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    void Function(String reasoningContent)? onReasoningContent,
    void Function(AIUsageMetrics usage)? onUsage,
  }) async* {
    try {
      final requestData = _buildRequest(
        messages,
        tools,
        maxTokens,
        stream: true,
      );

      final response = await _dio.post(
        _endpoint,
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      var sseBuffer = '';
      final reasoningBuffer = StringBuffer();
      await for (final chunk in utf8.decoder.bind(
        response.data.stream.cast<List<int>>(),
      )) {
        sseBuffer += chunk;
        final lines = sseBuffer.split('\n');
        sseBuffer = lines.removeLast();
        for (final rawLine in lines) {
          final data = _sseData(rawLine);
          if (data == null) continue;
          try {
            final event = jsonDecode(data) as Map<String, dynamic>;
            final usage = _usageFromEvent(event);
            if (usage != null) onUsage?.call(usage);
            final text = _usesResponses
                ? _responsesTextDelta(event)
                : _chatTextDelta(event);
            if (text != null && text.isNotEmpty) yield text;
            if (_usesResponses) {
              final reasoning = _responsesReasoningDelta(event);
              if (reasoning != null && reasoning.isNotEmpty) {
                reasoningBuffer.write(reasoning);
                onReasoningContent?.call(reasoningBuffer.toString());
              }
            }
          } catch (_) {
            continue;
          }
        }
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('OpenAI API streaming failed: $e');
    }
  }

  @override
  Future<ChatMessage> sendMessageSync({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    void Function(String textChunk)? onTextChunk,
    void Function(String reasoningContent)? onReasoningContent,
    void Function(AIUsageMetrics usage)? onUsage,
  }) async {
    try {
      final requestData = _buildRequest(
        messages,
        tools,
        maxTokens,
        stream: true,
      );
      final response = await _dio.post(
        _endpoint,
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final toolCallAccumulators = <int, _ToolCallAccumulator>{};
      var sseBuffer = '';

      await for (final chunk in utf8.decoder.bind(
        response.data.stream.cast<List<int>>(),
      )) {
        sseBuffer += chunk;
        final lines = sseBuffer.split('\n');
        sseBuffer = lines.removeLast();

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (!line.startsWith('data:')) continue;
          final data = line.substring('data:'.length).trim();
          if (data.isEmpty || data == '[DONE]') continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final usage = _usageFromEvent(json);
            if (usage != null) onUsage?.call(usage);

            if (_usesResponses) {
              final text = _responsesTextDelta(json);
              if (text != null && text.isNotEmpty) {
                textBuffer.write(text);
                onTextChunk?.call(text);
              }
              final reasoning = _responsesReasoningDelta(json);
              if (reasoning != null && reasoning.isNotEmpty) {
                reasoningBuffer.write(reasoning);
                onReasoningContent?.call(reasoningBuffer.toString());
              }
              _accumulateResponsesToolCall(json, toolCallAccumulators);
            } else {
              final choices = json['choices'] as List<dynamic>?;
              if (choices == null || choices.isEmpty) continue;
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              if (delta == null) continue;

              final content = delta['content'] as String?;
              if (content != null && content.isNotEmpty) {
                textBuffer.write(content);
                if (onTextChunk != null) onTextChunk(content);
              }

              final toolCalls = delta['tool_calls'] as List<dynamic>?;
              if (toolCalls != null) {
                for (final entry in toolCalls) {
                  if (entry is! Map<String, dynamic>) continue;
                  final index = (entry['index'] as num?)?.toInt() ?? 0;
                  final acc = toolCallAccumulators.putIfAbsent(
                    index,
                    () => _ToolCallAccumulator(),
                  );
                  final id = entry['id'] as String?;
                  if (id != null && id.isNotEmpty) acc.id = id;
                  final fn = entry['function'] as Map<String, dynamic>?;
                  if (fn != null) {
                    final name = fn['name'] as String?;
                    if (name != null && name.isNotEmpty) acc.name = name;
                    final args = fn['arguments'] as String?;
                    if (args != null) acc.argsBuffer.write(args);
                  }
                }
              }
            }
          } catch (_) {
            continue;
          }
        }
      }

      final messageContent = <MessageContent>[];
      final textResult = textBuffer.toString();
      if (textResult.isNotEmpty) {
        messageContent.add(MessageContent.text(text: textResult));
      }
      final orderedIndexes = toolCallAccumulators.keys.toList()..sort();
      for (final idx in orderedIndexes) {
        final acc = toolCallAccumulators[idx]!;
        if (acc.id == null || acc.name == null) continue;
        final argsRaw = acc.argsBuffer.toString();
        Map<String, dynamic> input;
        try {
          input = argsRaw.trim().isEmpty
              ? <String, dynamic>{}
              : (jsonDecode(argsRaw) as Map<String, dynamic>);
        } catch (_) {
          input = <String, dynamic>{};
        }
        messageContent.add(
          MessageContent.toolUse(
            toolUseId: acc.id!,
            name: acc.name!,
            input: input,
          ),
        );
      }

      if (messageContent.isEmpty) {
        messageContent.add(const MessageContent.text(text: ''));
      }

      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.assistant,
        content: messageContent,
        timestamp: DateTime.now(),
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('OpenAI API call failed: $e');
    }
  }

  @override
  Future<bool> validateApiKey() async {
    try {
      // 发送一个简单的测试请求
      await sendMessageSync(
        messages: [
          ChatMessage(
            id: 'test',
            role: MessageRole.user,
            content: [MessageContent.text(text: 'Hi')],
            timestamp: DateTime.now(),
          ),
        ],
        maxTokens: 10,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getModelInfo() async {
    return {
      'provider': 'openai',
      'model_id': modelId,
      'supports_streaming': true,
      'supports_vision':
          modelId.contains('gpt-4') && modelId.contains('vision'),
      'supports_tools': true,
    };
  }

  /// 构建请求数据
  Map<String, dynamic> _buildRequest(
    List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens, {
    required bool stream,
  }) {
    if (_usesResponses) {
      // Responses API 格式
      final requestData = <String, dynamic>{
        'model': modelId,
        'input': messages.expand(_convertMessageForResponses).toList(),
        'stream': stream,
      };

      if (maxTokens != null) requestData['max_output_tokens'] = maxTokens;
      if (tools != null && tools.isNotEmpty) {
        requestData['tools'] = tools.map(_convertResponsesTool).toList();
        requestData['tool_choice'] = 'auto';
      }
      if (customApiUrl == null ||
          customApiUrl!.contains('openai.com') ||
          customApiUrl!.contains('deepseek.com')) {
        requestData['prompt_cache_key'] = 'howtocook-chat-v2';
      }

      return requestData;
    }

    // 标准 OpenAI API 格式
    final requestData = <String, dynamic>{
      'model': modelId,
      'messages': messages.map(_convertMessage).toList(),
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
    };

    if (customApiUrl == null || customApiUrl!.contains('openai.com')) {
      requestData['prompt_cache_key'] = 'howtocook-chat-v2';
    }

    if (maxTokens != null) {
      requestData['max_tokens'] = maxTokens;
    }

    if (tools != null && tools.isNotEmpty) {
      requestData['tools'] = tools.map(_convertTool).toList();
      requestData['tool_choice'] = 'auto';
    }

    return requestData;
  }

  /// 转换消息格式（用于 Responses API）
  Iterable<Map<String, dynamic>> _convertMessageForResponses(
    ChatMessage message,
  ) sync* {
    final content = <Map<String, dynamic>>[];

    for (final item in message.content) {
      if (item is TextContent) {
        content.add({
          'type': message.role == MessageRole.assistant
              ? 'output_text'
              : 'input_text',
          'text': item.text,
        });
      } else if (item is ImageContent) {
        content.add({
          'type': 'input_image',
          'image_url':
              'data:${item.mimeType ?? 'image/jpeg'};base64,${item.data}',
        });
      } else if (item is ToolUseContent) {
        yield {
          'type': 'function_call',
          'call_id': item.toolUseId,
          'name': item.name,
          'arguments': jsonEncode(item.input),
        };
      } else if (item is ToolResultContent) {
        yield {
          'type': 'function_call_output',
          'call_id': item.toolUseId,
          'output': jsonEncode(item.result),
        };
      }
    }

    if (message.runtimeContext != null &&
        message.runtimeContext!.trim().isNotEmpty) {
      content.add({
        'type': 'input_text',
        'text': message.runtimeContext!.trim(),
      });
    }

    if (content.isNotEmpty) {
      yield {'role': _convertRole(message.role), 'content': content};
    }
  }

  /// 转换消息格式（用于标准 OpenAI API）
  Map<String, dynamic> _convertMessage(ChatMessage message) {
    final content = <dynamic>[];
    final toolCalls = <Map<String, dynamic>>[];

    for (final item in message.content) {
      if (item is TextContent) {
        content.add(item.text);
      } else if (item is ImageContent) {
        content.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${item.mimeType ?? 'image/jpeg'};base64,${item.data}',
          },
        });
      } else if (item is ToolUseContent) {
        toolCalls.add({
          'id': item.toolUseId,
          'type': 'function',
          'function': {'name': item.name, 'arguments': jsonEncode(item.input)},
        });
      } else if (item is ToolResultContent) {
        return {
          'role': 'tool',
          'tool_call_id': item.toolUseId,
          'content': jsonEncode(item.result),
        };
      }
    }

    if (message.runtimeContext != null &&
        message.runtimeContext!.trim().isNotEmpty) {
      content.add(message.runtimeContext!.trim());
    }

    if (toolCalls.isNotEmpty) {
      final textParts = content.whereType<String>().join();
      return {
        'role': 'assistant',
        'content': textParts.isEmpty ? null : textParts,
        'tool_calls': toolCalls,
      };
    }

    if (content.length == 1 && content.first is String) {
      return {
        'role': _convertRole(message.role),
        'content': content.first as String,
      };
    }

    final formatted = content.map((c) {
      if (c is String) return {'type': 'text', 'text': c};
      return c;
    }).toList();

    return {'role': _convertRole(message.role), 'content': formatted};
  }

  /// 转换角色
  String _convertRole(MessageRole role) {
    switch (role) {
      case MessageRole.system:
        return 'system';
      case MessageRole.user:
        return 'user';
      case MessageRole.assistant:
        return 'assistant';
    }
  }

  Map<String, dynamic> _convertTool(Map<String, dynamic> tool) {
    return {
      'type': 'function',
      'function': {
        'name': tool['name'],
        'description': tool['description'],
        'parameters': tool['input_schema'] ?? tool['parameters'],
      },
    };
  }

  Map<String, dynamic> _convertResponsesTool(Map<String, dynamic> tool) {
    return {
      'type': 'function',
      'name': tool['name'],
      'description': tool['description'],
      'parameters': tool['input_schema'] ?? tool['parameters'],
    };
  }

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    for (final suffix in const ['/chat/completions', '/responses']) {
      if (normalized.toLowerCase().endsWith(suffix)) {
        normalized = normalized.substring(0, normalized.length - suffix.length);
        break;
      }
    }
    return normalized;
  }

  String? _sseData(String rawLine) {
    final line = rawLine.trim();
    if (!line.startsWith('data:')) return null;
    final data = line.substring('data:'.length).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    return data;
  }

  String? _chatTextDelta(Map<String, dynamic> event) {
    final choices = event['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final choice = Map<String, dynamic>.from(choices.first as Map);
    final delta = choice['delta'];
    if (delta is! Map) return null;
    return Map<String, dynamic>.from(delta)['content'] as String?;
  }

  String? _responsesTextDelta(Map<String, dynamic> event) {
    if (event['type'] == 'response.output_text.delta') {
      return event['delta'] as String?;
    }
    return null;
  }

  String? _responsesReasoningDelta(Map<String, dynamic> event) {
    if (event['type'] == 'response.reasoning_text.delta') {
      return event['delta'] as String?;
    }
    return null;
  }

  void _accumulateResponsesToolCall(
    Map<String, dynamic> event,
    Map<int, _ToolCallAccumulator> accumulators,
  ) {
    final type = event['type'] as String?;
    final index = (event['output_index'] as num?)?.toInt() ?? 0;
    if (type == 'response.output_item.added' ||
        type == 'response.output_item.done') {
      final rawItem = event['item'];
      if (rawItem is! Map) return;
      final item = Map<String, dynamic>.from(rawItem);
      if (item['type'] != 'function_call') return;
      final acc = accumulators.putIfAbsent(index, () => _ToolCallAccumulator());
      acc.id = item['call_id'] as String? ?? acc.id;
      acc.name = item['name'] as String? ?? acc.name;
      final arguments = item['arguments'] as String?;
      if (arguments != null && arguments.isNotEmpty && acc.argsBuffer.isEmpty) {
        acc.argsBuffer.write(arguments);
      }
      return;
    }
    if (type == 'response.function_call_arguments.delta') {
      final acc = accumulators.putIfAbsent(index, () => _ToolCallAccumulator());
      final delta = event['delta'] as String?;
      if (delta != null) acc.argsBuffer.write(delta);
    }
  }

  AIUsageMetrics? _usageFromEvent(dynamic raw) {
    if (raw is! Map) return null;
    final event = Map<String, dynamic>.from(raw);
    dynamic usageRaw = event['usage'];
    if (usageRaw == null && event['response'] is Map) {
      usageRaw = (event['response'] as Map)['usage'];
    }
    if (usageRaw is! Map) return null;
    final usage = Map<String, dynamic>.from(usageRaw);
    final detailsRaw =
        usage['prompt_tokens_details'] ?? usage['input_tokens_details'];
    final details = detailsRaw is Map
        ? Map<String, dynamic>.from(detailsRaw)
        : const <String, dynamic>{};
    int value(Map<String, dynamic> map, String key) =>
        (map[key] as num?)?.toInt() ?? 0;
    return AIUsageMetrics(
      inputTokens: value(usage, 'prompt_tokens') != 0
          ? value(usage, 'prompt_tokens')
          : value(usage, 'input_tokens'),
      outputTokens: value(usage, 'completion_tokens') != 0
          ? value(usage, 'completion_tokens')
          : value(usage, 'output_tokens'),
      cacheReadTokens: value(details, 'cached_tokens'),
      cacheWriteTokens: value(details, 'cache_write_tokens'),
    );
  }

  /// 处理 Dio 异常
  Exception _handleDioException(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      var data = e.response!.data;

      // 如果 data 是字符串，尝试解析为 JSON
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          // 无法解析，使用原始字符串作为错误信息
          return Exception('OpenAI API error ($statusCode): $data');
        }
      }

      String errorMessage = 'OpenAI API error';
      if (data is Map<String, dynamic>) {
        final error = data['error'];
        if (error is Map<String, dynamic>) {
          errorMessage = error['message'] as String? ?? errorMessage;
        } else if (error is String) {
          errorMessage = error;
        }
      }

      switch (statusCode) {
        case 401:
          return Exception('Invalid API key: $errorMessage');
        case 429:
          return Exception('Rate limit exceeded: $errorMessage');
        case 500:
        case 502:
        case 503:
          return Exception('OpenAI service unavailable: $errorMessage');
        default:
          return Exception('OpenAI API error ($statusCode): $errorMessage');
      }
    }

    return Exception('Network error: ${e.message}');
  }
}

class _ToolCallAccumulator {
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();
}
