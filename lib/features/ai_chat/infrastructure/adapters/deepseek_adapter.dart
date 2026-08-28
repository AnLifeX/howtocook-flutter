import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/ai_usage_metrics.dart';
import '../../domain/services/ai_service.dart';

/// DeepSeek API 适配器
///
/// 支持 DeepSeek Chat 模型
/// DeepSeek API 与 OpenAI API 兼容，使用相同的请求格式
class DeepSeekAdapter implements AIService {
  final Dio _dio;
  final String apiKey;
  final String modelId;
  final String? customApiUrl;
  final bool enableThinking;

  /// 默认 DeepSeek API 地址
  static const String defaultApiUrl = 'https://api.deepseek.com/v1';

  DeepSeekAdapter({
    required this.apiKey,
    required this.modelId,
    this.customApiUrl,
    this.enableThinking = false,
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

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    const suffix = '/chat/completions';
    if (normalized.toLowerCase().endsWith(suffix)) {
      normalized = normalized.substring(0, normalized.length - suffix.length);
    }
    return normalized;
  }

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
        '/chat/completions',
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      // Dio 流是 Stream<Uint8List>，先 cast 成 List<int> 再用 Utf8Decoder 绑定，避免类型不匹配且保持多字节字符完整解码
      final stream = utf8.decoder.bind(response.data.stream.cast<List<int>>());
      var buffer = '';
      final reasoningBuffer = StringBuffer();
      var chunkCounter = 0;

      await for (final chunk in stream) {
        chunkCounter++;
        if (chunkCounter % 10 == 1) {
          // 每10个chunk打印一次，避免日志过多
          debugPrint('📥 DeepSeek stream chunk #$chunkCounter received');
        }
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // 保留不完整行

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (!line.startsWith('data:')) continue;

          final data = line.substring('data:'.length).trim();
          if (data == '[DONE]') {
            final reasoning = reasoningBuffer.toString();
            if (reasoning.isNotEmpty) {
              if (onReasoningContent != null) {
                onReasoningContent(reasoning);
              } else {
                // 无回调时兜底输出思考块
                yield '\n\n💭 思考过程:\n$reasoning';
              }
            }
            continue;
          }
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data);
            final usage = _usageFromJson(json['usage']);
            if (usage != null) onUsage?.call(usage);
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null) {
                  yield content;
                }

                final reasoningContent = delta['reasoning_content'] as String?;
                if (reasoningContent != null) {
                  reasoningBuffer.write(reasoningContent);
                  if (onReasoningContent != null) {
                    onReasoningContent(reasoningBuffer.toString());
                  }
                }
              }
            }
          } catch (_) {
            // 忽略解析错误，继续后续行
            continue;
          }
        }
      }
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('DeepSeek API streaming failed: $e');
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
        '/chat/completions',
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      final stream = utf8.decoder.bind(response.data.stream.cast<List<int>>());
      final textBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final toolCallAccumulators = <int, _ToolCallAccumulator>{};
      var sseBuffer = '';

      await for (final chunk in stream) {
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
            final usage = _usageFromJson(json['usage']);
            if (usage != null) onUsage?.call(usage);
            final choices = json['choices'] as List<dynamic>?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              textBuffer.write(content);
              if (onTextChunk != null) onTextChunk(content);
            }

            final reasoning = delta['reasoning_content'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              reasoningBuffer.write(reasoning);
              if (onReasoningContent != null) {
                onReasoningContent(reasoningBuffer.toString());
              }
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
        } catch (e) {
          debugPrint('⚠️ DeepSeek tool_call arguments 解析失败: $e; raw=$argsRaw');
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
        reasoningContent: reasoningBuffer.isEmpty
            ? null
            : reasoningBuffer.toString(),
      );
    } on DioException catch (e) {
      if (e.response != null && e.response!.data is ResponseBody) {
        try {
          final responseBody = e.response!.data as ResponseBody;
          final bytes = <int>[];
          await for (final chunk in responseBody.stream) {
            bytes.addAll(chunk);
          }
          final bodyStr = utf8.decode(bytes);
          debugPrint(
            '🔴 DeepSeek API error (${e.response!.statusCode}): $bodyStr',
          );

          String errorMessage = 'DeepSeek API error';
          try {
            final json = jsonDecode(bodyStr) as Map<String, dynamic>;
            final error = json['error'] as Map<String, dynamic>?;
            if (error != null) {
              errorMessage = error['message'] as String? ?? errorMessage;
            }
          } catch (_) {
            errorMessage = bodyStr;
          }
          throw Exception(
            'DeepSeek API error (${e.response!.statusCode}): $errorMessage',
          );
        } catch (readError) {
          if (readError is Exception &&
              readError.toString().contains('DeepSeek API error')) {
            rethrow;
          }
          debugPrint('🔴 Failed to read error response: $readError');
        }
      }
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('DeepSeek API call failed: $e');
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
      'provider': 'deepseek',
      'model_id': modelId,
      'supports_streaming': true,
      'supports_vision': false, // DeepSeek 当前不支持视觉输入
      'supports_tools': !modelId.contains(
        'reasoner',
      ), // reasoner 不支持 Function Calling
    };
  }

  /// 构建请求数据
  Map<String, dynamic> _buildRequest(
    List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens, {
    required bool stream,
  }) {
    final requestData = <String, dynamic>{
      'model': modelId,
      'messages': messages.map(_convertMessage).toList(),
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
    };

    if (maxTokens != null) {
      requestData['max_tokens'] = maxTokens;
    }

    // V4 模型支持 thinking 模式控制
    if (!modelId.contains('reasoner')) {
      final thinkingType = enableThinking ? 'enabled' : 'disabled';
      requestData['thinking'] = {'type': thinkingType};
    }

    // 旧版 deepseek-reasoner 不支持 Function Calling，建议迁移到 deepseek-v4-flash/pro
    if (modelId.contains('reasoner')) {
      if (tools != null && tools.isNotEmpty) {
        throw Exception(
          'deepseek-reasoner 不支持工具调用，请切换到 deepseek-v4-flash 或 deepseek-v4-pro',
        );
      }
      // 过滤掉历史消息中的工具调用和结果
      requestData['messages'] = (requestData['messages'] as List)
          .where((msg) => msg['role'] != 'tool' && msg['tool_calls'] == null)
          .toList();
    } else if (tools != null && tools.isNotEmpty) {
      requestData['tools'] = tools.map(_convertTool).toList();
      requestData['tool_choice'] = 'auto';
    }

    return requestData;
  }

  @visibleForTesting
  Map<String, dynamic> buildRequestForTesting({
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    int? maxTokens,
    bool stream = true,
  }) => _buildRequest(messages, tools, maxTokens, stream: stream);

  /// 转换消息格式
  Map<String, dynamic> _convertMessage(ChatMessage message) {
    final textParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    for (final item in message.content) {
      if (item is TextContent) {
        textParts.add(item.text);
      } else if (item is ImageContent) {
        throw Exception('DeepSeek does not support image input');
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
      textParts.add(message.runtimeContext!.trim());
    }
    final textContent = textParts.join('\n\n');

    if (toolCalls.isNotEmpty) {
      final msg = <String, dynamic>{
        'role': 'assistant',
        'content': textContent,
        'tool_calls': toolCalls,
      };
      if (message.reasoningContent != null) {
        msg['reasoning_content'] = message.reasoningContent;
      }
      return msg;
    }

    final msg = <String, dynamic>{
      'role': _convertRole(message.role),
      'content': textContent,
    };
    if (message.role == MessageRole.assistant &&
        message.reasoningContent != null) {
      msg['reasoning_content'] = message.reasoningContent;
    }
    return msg;
  }

  AIUsageMetrics? _usageFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final usage = Map<String, dynamic>.from(raw);
    int value(String key) => (usage[key] as num?)?.toInt() ?? 0;
    return AIUsageMetrics(
      inputTokens: value('prompt_tokens'),
      outputTokens: value('completion_tokens'),
      cacheReadTokens: value('prompt_cache_hit_tokens'),
      cacheMissTokens: value('prompt_cache_miss_tokens'),
    );
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

  /// 转换工具定义（从 MCP 格式到 OpenAI 兼容格式）
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

  /// 处理 Dio 异常
  Exception _handleDioException(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final data = e.response!.data;

      String errorMessage = 'DeepSeek API error';
      if (data is Map<String, dynamic>) {
        final error = data['error'] as Map<String, dynamic>?;
        if (error != null) {
          errorMessage = error['message'] as String? ?? errorMessage;
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
          return Exception('DeepSeek service unavailable: $errorMessage');
        default:
          return Exception('DeepSeek API error ($statusCode): $errorMessage');
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
