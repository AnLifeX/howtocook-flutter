import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/ai_usage_metrics.dart';
import '../../domain/services/ai_service.dart';

/// Claude API 适配器
///
/// 支持 Claude 3.5 Sonnet 和其他 Claude 模型
/// 支持自定义 API URL（用于代理或非官方端点）
/// 支持 Extended Thinking（思考链）功能
class ClaudeAdapter implements AIService {
  final Dio _dio;
  final String apiKey;
  final String modelId;
  final String? customApiUrl;
  final String? mcpServerUrl;
  final bool enableThinking;
  final int thinkingBudgetTokens;

  /// 默认 Claude API 地址
  static const String defaultApiUrl = 'https://api.anthropic.com/v1';

  ClaudeAdapter({
    required this.apiKey,
    required this.modelId,
    this.customApiUrl,
    this.mcpServerUrl,
    this.enableThinking = false,
    this.thinkingBudgetTokens = 10000,
  }) : _dio = Dio() {
    final baseUrl = _normalizeBaseUrl(customApiUrl ?? defaultApiUrl);
    _dio.options.baseUrl = baseUrl;

    // 基础headers
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    };

    // 仅在使用官方API时添加anthropic-beta头（中转服务可能不支持）
    if (customApiUrl == null || customApiUrl!.contains('anthropic.com')) {
      headers['anthropic-beta'] = 'mcp-client-2025-04-04';
    } else {
      debugPrint('⚠️  Using custom API, skipping anthropic-beta header');
    }

    _dio.options.headers = headers;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 300);
  }

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.toLowerCase().endsWith('/messages')) {
      normalized = normalized.substring(
        0,
        normalized.length - '/messages'.length,
      );
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

      // 详细调试日志
      final requestBody = jsonEncode(requestData);
      debugPrint('🌐 Claude API Request:');
      debugPrint('  URL: ${_dio.options.baseUrl}/messages');
      debugPrint('  Headers: ${_dio.options.headers}');
      debugPrint('  Body length: ${requestBody.length} bytes');
      debugPrint(
        '  Body (first 2000 chars): ${requestBody.substring(0, 2000.clamp(0, requestBody.length))}...',
      );

      // 如果有工具，单独打印工具定义
      if (requestData['tools'] != null) {
        final toolsJson = jsonEncode(requestData['tools']);
        debugPrint(
          '  Tools (first 1000 chars): ${toolsJson.substring(0, 1000.clamp(0, toolsJson.length))}...',
        );
      }

      final response = await _dio.post(
        '/messages',
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      debugPrint('✅ Claude API Response:');
      debugPrint('  Status: ${response.statusCode}');
      debugPrint('  Headers: ${response.headers}');

      final stream = response.data.stream;
      var chunkCount = 0;
      String? currentBlockType; // 跟踪当前内容块类型
      final reasoningBuffer = StringBuffer(); // 累积思考内容

      await for (final chunk in stream) {
        chunkCount++;
        final lines = utf8.decode(chunk).split('\n');
        for (final line in lines) {
          // 调试：打印所有 SSE 事件行
          if (line.trim().isNotEmpty &&
              (line.startsWith('event:') || line.startsWith('data:'))) {
            debugPrint(
              '📨 SSE chunk #$chunkCount: ${line.substring(0, line.length.clamp(0, 200))}${line.length > 200 ? '...' : ''}',
            );
          }

          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') {
              debugPrint('✅ Stream completed');
              continue;
            }

            try {
              final json = jsonDecode(data);
              final usage = _usageFromEvent(json);
              if (usage != null) onUsage?.call(usage);
              final type = json['type'] as String?;

              debugPrint('📋 Event type: $type');

              // 处理内容块开始
              if (type == 'content_block_start') {
                final contentBlock =
                    json['content_block'] as Map<String, dynamic>?;
                if (contentBlock != null) {
                  currentBlockType = contentBlock['type'] as String?;
                  debugPrint(
                    '📦 Content block started: type=$currentBlockType',
                  );
                  if (currentBlockType == 'thinking') {
                    debugPrint('🧠 Thinking block detected!');
                  }
                }
              }
              // 处理内容块增量
              else if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final deltaType = delta['type'] as String?;

                  if (deltaType == 'text_delta') {
                    final text = delta['text'] as String?;
                    if (text != null) {
                      yield text;
                    }
                  } else if (deltaType == 'thinking_delta') {
                    // 处理 Claude Extended Thinking
                    final thinking = delta['thinking'] as String?;
                    if (thinking != null) {
                      debugPrint(
                        '🧠 Thinking delta: ${thinking.substring(0, thinking.length.clamp(0, 50))}...',
                      );
                      reasoningBuffer.write(thinking);
                      // 实时回调推理内容
                      if (onReasoningContent != null) {
                        onReasoningContent(reasoningBuffer.toString());
                      }
                    }
                  }
                }
              }
              // 处理内容块结束
              else if (type == 'content_block_stop') {
                debugPrint('📦 Content block stopped: type=$currentBlockType');
                currentBlockType = null;
              }
              // 处理消息停止（可能包含停止原因）
              else if (type == 'message_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null && delta.containsKey('stop_reason')) {
                  debugPrint('⏹️  Stop reason: ${delta['stop_reason']}');
                }
              }
            } catch (e) {
              debugPrint('⚠️  Failed to parse SSE data: $e');
              // 忽略解析错误，继续处理下一行
              continue;
            }
          }
        }
      }
      debugPrint('🏁 Stream finished, total chunks: $chunkCount');
    } on DioException catch (e) {
      // 如果是400/404等错误，尝试读取ResponseBody
      debugPrint(
        '🔍 Checking response data type: ${e.response?.data.runtimeType}',
      );
      if (e.response != null && e.response!.data is ResponseBody) {
        debugPrint('📖 Attempting to read ResponseBody...');
        try {
          // 正确读取stream
          final chunks = <int>[];
          await for (final chunk in e.response!.data.stream) {
            chunks.addAll(chunk);
          }
          final errorText = utf8.decode(chunks);
          debugPrint('  Response Data (from stream): $errorText');
          throw Exception(
            'Claude API error (${e.response!.statusCode}): $errorText',
          );
        } catch (readError) {
          debugPrint('❌ Failed to read ResponseBody: $readError');
          // 如果读取失败，使用原来的错误处理
        }
      } else {
        debugPrint(
          '⚠️  Response data is not ResponseBody, skipping stream read',
        );
      }
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('Claude API streaming failed: $e');
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
        '/messages',
        data: requestData,
        options: Options(responseType: ResponseType.stream),
      );

      // 解析完整的流式响应，包括工具调用和推理内容
      final parsedResponse = await _parseStreamingResponse(
        response.data.stream,
        onTextChunk: onTextChunk,
        onReasoningContent: onReasoningContent,
        onUsage: onUsage,
      );

      return ChatMessage(
        id: parsedResponse['id'] as String,
        role: MessageRole.assistant,
        content: parsedResponse['content'] as List<MessageContent>,
        timestamp: DateTime.now(),
        reasoningContent: parsedResponse['reasoningContent'] as String?,
      );
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw Exception('Claude API call failed: $e');
    }
  }

  /// 解析完整的流式响应（包括文本和工具调用）
  Future<Map<String, dynamic>> _parseStreamingResponse(
    Stream<List<int>> stream, {
    void Function(String textChunk)? onTextChunk,
    void Function(String reasoningContent)? onReasoningContent,
    void Function(AIUsageMetrics usage)? onUsage,
  }) async {
    String messageId = DateTime.now().toString();
    final contentBlocks = <_ContentBlock>[];
    _ContentBlock? currentBlock;
    final reasoningBuffer = StringBuffer(); // 累积推理内容

    await for (final chunk in stream) {
      final lines = utf8.decode(chunk).split('\n');
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;

        final data = line.substring(6);
        if (data == '[DONE]') continue;

        try {
          final json = jsonDecode(data);
          final usage = _usageFromEvent(json);
          if (usage != null) onUsage?.call(usage);
          final type = json['type'] as String?;

          switch (type) {
            case 'message_start':
              final message = json['message'] as Map<String, dynamic>?;
              if (message != null) {
                messageId = message['id'] as String? ?? messageId;
              }
              break;

            case 'content_block_start':
              final contentBlock =
                  json['content_block'] as Map<String, dynamic>?;
              if (contentBlock != null) {
                final blockType = contentBlock['type'] as String?;
                debugPrint('📦 Content block started: type=$blockType');
                if (blockType == 'text') {
                  currentBlock = _ContentBlock(
                    type: 'text',
                    textBuffer: StringBuffer(),
                  );
                } else if (blockType == 'thinking') {
                  // Claude Extended Thinking
                  debugPrint('🧠 Thinking block detected!');
                  currentBlock = _ContentBlock(
                    type: 'thinking',
                    textBuffer: StringBuffer(),
                  );
                } else if (blockType == 'tool_use') {
                  currentBlock = _ContentBlock(
                    type: 'tool_use',
                    toolUseId: contentBlock['id'] as String?,
                    toolName: contentBlock['name'] as String?,
                    inputJsonBuffer: StringBuffer(),
                  );
                }
              }
              break;

            case 'content_block_delta':
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta != null && currentBlock != null) {
                final deltaType = delta['type'] as String?;
                if (deltaType == 'text_delta') {
                  final text = delta['text'] as String?;
                  if (text != null) {
                    currentBlock.textBuffer?.write(text);
                    // 实时回调文本块
                    if (onTextChunk != null && currentBlock.type == 'text') {
                      onTextChunk(text);
                    }
                  }
                } else if (deltaType == 'thinking_delta') {
                  // Claude Extended Thinking 增量
                  final thinking = delta['thinking'] as String?;
                  if (thinking != null) {
                    debugPrint(
                      '🧠 Thinking delta: ${thinking.substring(0, thinking.length.clamp(0, 50))}...',
                    );
                    currentBlock.textBuffer?.write(thinking);
                    reasoningBuffer.write(thinking);
                    // 实时回调推理内容
                    if (onReasoningContent != null) {
                      onReasoningContent(reasoningBuffer.toString());
                    }
                  }
                } else if (deltaType == 'input_json_delta') {
                  final partialJson = delta['partial_json'] as String?;
                  if (partialJson != null) {
                    currentBlock.inputJsonBuffer?.write(partialJson);
                  }
                }
              }
              break;

            case 'content_block_stop':
              if (currentBlock != null) {
                // 只保存非 thinking 的块（thinking 不作为最终内容）
                if (currentBlock.type != 'thinking') {
                  contentBlocks.add(currentBlock);
                }
                currentBlock = null;
              }
              break;
          }
        } catch (e) {
          debugPrint('⚠️  Failed to parse streaming chunk: $e');
          continue;
        }
      }
    }

    // 转换为 MessageContent 列表
    final content = <MessageContent>[];
    for (final block in contentBlocks) {
      if (block.type == 'text' && block.textBuffer != null) {
        final text = block.textBuffer!.toString();
        if (text.isNotEmpty) {
          content.add(MessageContent.text(text: text));
        }
      } else if (block.type == 'tool_use' &&
          block.toolUseId != null &&
          block.toolName != null &&
          block.inputJsonBuffer != null) {
        try {
          final inputJson = block.inputJsonBuffer!.toString();
          final input = jsonDecode(inputJson) as Map<String, dynamic>;
          content.add(
            MessageContent.toolUse(
              toolUseId: block.toolUseId!,
              name: block.toolName!,
              input: input,
            ),
          );
        } catch (e) {
          debugPrint('⚠️  Failed to parse tool input JSON: $e');
        }
      }
    }

    return {
      'id': messageId,
      'content': content,
      'reasoningContent': reasoningBuffer.isNotEmpty
          ? reasoningBuffer.toString()
          : null,
    };
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
      'provider': 'claude',
      'model_id': modelId,
      'supports_streaming': true,
      'supports_vision': modelId.contains('claude-3'),
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
    // 提取系统消息（使用数组格式，兼容更多中转服务）
    final systemBlocks = <Map<String, dynamic>>[];
    final userMessages = <ChatMessage>[];

    for (final msg in messages) {
      if (msg.role == MessageRole.system) {
        // 提取所有文本内容并转换为 system 块
        for (final content in msg.content.whereType<TextContent>()) {
          systemBlocks.add({'type': 'text', 'text': content.text});
        }
      } else {
        userMessages.add(msg);
      }
    }

    final requestData = <String, dynamic>{
      'model': modelId,
      'messages': userMessages.map(_convertMessage).toList(),
      'max_tokens': maxTokens ?? 4096,
      'stream': stream,
    };

    final isOfficialApi =
        customApiUrl == null || customApiUrl!.contains('anthropic.com');
    if (isOfficialApi) {
      requestData['cache_control'] = {'type': 'ephemeral'};
    }

    if (systemBlocks.isNotEmpty) {
      requestData['system'] = systemBlocks;
    }

    // 添加 Extended Thinking 配置
    if (enableThinking) {
      requestData['thinking'] = {
        'type': 'enabled',
        'budget_tokens': thinkingBudgetTokens,
      };
      // Extended Thinking 需要更大的 max_tokens（思考 + 输出）
      final currentMaxTokens = requestData['max_tokens'] as int;
      if (currentMaxTokens < thinkingBudgetTokens + 4096) {
        requestData['max_tokens'] = thinkingBudgetTokens + 4096;
      }
      debugPrint(
        '🧠 Extended Thinking enabled with budget: $thinkingBudgetTokens tokens',
      );

      // 启用思考链时，使用 XML 格式工具定义（CherryStudio 风格）
      // 部分中转服务不支持同时使用 thinking + tools 参数，但支持 XML 格式
      if (tools != null && tools.isNotEmpty) {
        final xmlTools = _convertToolsToXml(tools);
        final toolSystemBlock = {'type': 'text', 'text': xmlTools};
        // 将工具定义添加到 system prompt
        if (requestData['system'] == null) {
          requestData['system'] = [toolSystemBlock];
        } else {
          (requestData['system'] as List).add(toolSystemBlock);
        }
        debugPrint(
          '🔧 Using XML tools format for thinking mode: ${tools.length} tools',
        );
      }
    } else {
      // 未启用思考链时，使用标准 tools 参数
      // 官方 API 且配置了 MCP Server：使用 MCP connector 模式
      if (isOfficialApi &&
          tools != null &&
          tools.isNotEmpty &&
          mcpServerUrl != null &&
          mcpServerUrl!.isNotEmpty) {
        requestData['mcp_servers'] = [
          {'type': 'url', 'url': mcpServerUrl, 'name': 'howtocook-mcp'},
        ];
        debugPrint('🔧 Using MCP connector mode for official API');
      } else if (tools != null && tools.isNotEmpty) {
        // 标准工具调用模式（适用于自定义 API 或无 MCP Server 的情况）
        requestData['tools'] = tools;
        debugPrint('🔧 Using standard tools mode: ${tools.length} tools');
      }
    }

    return requestData;
  }

  /// 将工具定义转换为 XML 格式（CherryStudio 风格）
  ///
  /// 格式示例：
  /// ```xml
  /// <tools>
  /// <tool>
  ///   <name>tool_name</name>
  ///   <description>工具描述</description>
  ///   <arguments>{"jsonSchema": ...}</arguments>
  /// </tool>
  /// </tools>
  /// ```
  String _convertToolsToXml(List<Map<String, dynamic>> tools) {
    final buffer = StringBuffer();
    buffer.writeln('## Tool Use Available Tools');
    buffer.writeln('You have access to these tools:');
    buffer.writeln('<tools>');

    for (final tool in tools) {
      buffer.writeln('<tool>');
      buffer.writeln('  <name>${tool['name']}</name>');
      if (tool['description'] != null) {
        buffer.writeln('  <description>${tool['description']}</description>');
      }
      if (tool['input_schema'] != null) {
        buffer.writeln('  <arguments>');
        buffer.writeln(
          '    ${jsonEncode({'jsonSchema': tool['input_schema']})}',
        );
        buffer.writeln('  </arguments>');
      }
      buffer.writeln('</tool>');
      buffer.writeln();
    }

    buffer.writeln('</tools>');
    buffer.writeln();
    buffer.writeln('## Tool Use Formatting');
    buffer.writeln('To use a tool, format your response as:');
    buffer.writeln('<tool_use>');
    buffer.writeln('  <name>{tool_name}</name>');
    buffer.writeln('  <arguments>{json_arguments}</arguments>');
    buffer.writeln('</tool_use>');
    buffer.writeln();
    buffer.writeln('## Tool Use Rules');
    buffer.writeln('1. Always use the right arguments for the tools.');
    buffer.writeln('2. Call a tool only when needed.');
    buffer.writeln(
      '3. If no tool call is needed, just answer the question directly.',
    );
    buffer.writeln(
      '4. For tool use, MAKE SURE use XML tag format as shown above.',
    );

    return buffer.toString();
  }

  /// 转换消息格式
  Map<String, dynamic> _convertMessage(ChatMessage message) {
    final content = <Map<String, dynamic>>[];
    final isOfficialApi =
        customApiUrl == null || customApiUrl!.contains('anthropic.com');
    final useMcpFormat =
        isOfficialApi && mcpServerUrl != null && mcpServerUrl!.isNotEmpty;

    for (final item in message.content) {
      if (item is TextContent) {
        content.add({'type': 'text', 'text': item.text});
      } else if (item is ImageContent) {
        content.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': item.mimeType ?? 'image/jpeg',
            'data': item.data,
          },
        });
      } else if (item is ToolUseContent) {
        // 官方 API + MCP Server：使用 mcp_tool_use 类型
        if (useMcpFormat) {
          content.add({
            'type': 'mcp_tool_use',
            'id': item.toolUseId,
            'name': item.name,
            'server_name': 'howtocook-mcp',
            'input': item.input,
          });
        } else {
          // 标准工具调用（自定义 API 或无 MCP）
          content.add({
            'type': 'tool_use',
            'id': item.toolUseId,
            'name': item.name,
            'input': item.input,
          });
        }
      } else if (item is ToolResultContent) {
        // 官方 API + MCP Server：使用 mcp_tool_result 类型
        if (useMcpFormat) {
          content.add({
            'type': 'mcp_tool_result',
            'tool_use_id': item.toolUseId,
            'is_error': false,
            'content': [
              {'type': 'text', 'text': jsonEncode(item.result)},
            ],
          });
        } else {
          // 标准工具结果（自定义 API 或无 MCP）
          content.add({
            'type': 'tool_result',
            'tool_use_id': item.toolUseId,
            'content': item.result,
          });
        }
      }
    }

    if (message.runtimeContext != null &&
        message.runtimeContext!.trim().isNotEmpty) {
      content.add({'type': 'text', 'text': message.runtimeContext!.trim()});
    }

    return {
      'role': message.role == MessageRole.user ? 'user' : 'assistant',
      'content': content,
    };
  }

  AIUsageMetrics? _usageFromEvent(dynamic raw) {
    if (raw is! Map) return null;
    final event = Map<String, dynamic>.from(raw);
    dynamic usageRaw = event['usage'];
    if (usageRaw == null && event['message'] is Map) {
      usageRaw = (event['message'] as Map)['usage'];
    }
    if (usageRaw is! Map) return null;
    final usage = Map<String, dynamic>.from(usageRaw);
    int value(String key) => (usage[key] as num?)?.toInt() ?? 0;
    return AIUsageMetrics(
      inputTokens: value('input_tokens'),
      outputTokens: value('output_tokens'),
      cacheReadTokens: value('cache_read_input_tokens'),
      cacheWriteTokens: value('cache_creation_input_tokens'),
    );
  }

  /// 处理 Dio 异常
  Exception _handleDioException(DioException e) {
    // 详细的错误调试日志
    debugPrint('❌ Claude API Error:');
    debugPrint('  Type: ${e.type}');
    debugPrint('  Message: ${e.message}');

    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      var data = e.response!.data;

      debugPrint('  Status Code: $statusCode');
      debugPrint('  Response Headers: ${e.response!.headers}');
      debugPrint('  Response Data: $data');
      debugPrint('  Request URL: ${e.requestOptions.uri}');
      debugPrint('  Request Method: ${e.requestOptions.method}');
      debugPrint('  Request Headers: ${e.requestOptions.headers}');

      // 如果 data 是字符串，尝试解析为 JSON
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          // 无法解析，使用原始字符串作为错误信息
          return Exception('Claude API error ($statusCode): $data');
        }
      }

      String errorMessage = 'Claude API error';
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
          return Exception('Claude service unavailable: $errorMessage');
        default:
          return Exception('Claude API error ($statusCode): $errorMessage');
      }
    }

    return Exception('Network error: ${e.message}');
  }
}

/// 内容块辅助类，用于跟踪流式响应中的内容块状态
class _ContentBlock {
  final String type; // 'text' or 'tool_use'
  final StringBuffer? textBuffer;
  final StringBuffer? inputJsonBuffer;
  final String? toolUseId;
  final String? toolName;

  _ContentBlock({
    required this.type,
    this.textBuffer,
    this.inputJsonBuffer,
    this.toolUseId,
    this.toolName,
  });
}
