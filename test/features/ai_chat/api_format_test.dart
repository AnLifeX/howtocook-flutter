import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/ai_model_config.dart';
import 'package:howtocook/features/ai_chat/domain/entities/chat_message.dart';
import 'package:howtocook/features/ai_chat/infrastructure/adapters/claude_adapter.dart';
import 'package:howtocook/features/ai_chat/infrastructure/adapters/deepseek_adapter.dart';
import 'package:howtocook/features/ai_chat/infrastructure/adapters/openai_adapter.dart';
import 'package:howtocook/features/ai_chat/infrastructure/services/ai_service_factory.dart';

void main() {
  AIModelConfig config({
    AIAPIFormat apiFormat = AIAPIFormat.auto,
    String? apiUrl,
    String modelId = 'deepseek-v4-flash',
    ModelCapabilities capabilities = const ModelCapabilities(
      supportsMCP: false,
    ),
  }) {
    return AIModelConfig(
      id: 'test',
      provider: AIProvider.deepseek,
      modelId: modelId,
      displayName: 'DeepSeek',
      customApiKey: 'test-key',
      customApiUrl: apiUrl,
      apiFormat: apiFormat,
      capabilities: capabilities,
    );
  }

  Map<String, dynamic> persistedJson(AIModelConfig value) {
    return {...value.toJson(), 'capabilities': value.capabilities.toJson()};
  }

  test('legacy model configuration defaults to automatic API format', () {
    final json = persistedJson(config(apiFormat: AIAPIFormat.responses))
      ..remove('apiFormat');
    expect(AIModelConfig.fromJson(json).apiFormat, AIAPIFormat.auto);
  });

  test('API format wire values survive JSON persistence', () {
    for (final format in AIAPIFormat.values) {
      final restored = AIModelConfig.fromJson(
        persistedJson(config(apiFormat: format)),
      );
      expect(restored.apiFormat, format);
      expect(format.wireValue, isNotEmpty);
    }
  });

  test('DeepSeek can route to all supported protocol adapters', () {
    expect(AIServiceFactory.create(config()), isA<DeepSeekAdapter>());
    expect(
      AIServiceFactory.create(config(apiFormat: AIAPIFormat.responses)),
      isA<OpenAIAdapter>(),
    );
    expect(
      AIServiceFactory.create(config(apiFormat: AIAPIFormat.anthropicMessages)),
      isA<ClaudeAdapter>(),
    );
  });

  test('automatic mode recognizes explicit compatible endpoint URLs', () {
    expect(
      AIServiceFactory.resolveAPIFormat(
        config(apiUrl: 'https://example.com/v1/responses'),
      ),
      AIAPIFormat.responses,
    );
    expect(
      AIServiceFactory.resolveAPIFormat(
        config(apiUrl: 'https://api.deepseek.com/anthropic'),
      ),
      AIAPIFormat.anthropicMessages,
    );
    expect(
      AIServiceFactory.resolveAPIFormat(
        config(modelId: 'deepseek-v4-flash-vision-exp'),
      ),
      AIAPIFormat.chatCompletions,
    );
    expect(
      AIServiceFactory.resolveAPIFormat(
        config(
          apiUrl: 'https://opencode.ai/zen/go/v1/responses',
          modelId: 'deepseek-v4-flash-vision-exp',
        ),
      ),
      AIAPIFormat.chatCompletions,
    );
  });

  group('DeepSeek v4 flash tool protocol compatibility', () {
    final tools = <Map<String, dynamic>>[
      {
        'name': 'searchRecipes',
        'description': '搜索菜谱',
        'input_schema': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
        },
      },
    ];
    final history = <ChatMessage>[
      ChatMessage(
        id: 'system',
        role: MessageRole.system,
        content: const [MessageContent.text(text: '你是烹饪助手')],
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      ChatMessage(
        id: 'assistant-call',
        role: MessageRole.assistant,
        content: const [
          MessageContent.toolUse(
            toolUseId: 'call_1',
            name: 'searchRecipes',
            input: {'query': '鸡蛋'},
          ),
        ],
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        reasoningContent: '需要先搜索鸡蛋相关菜谱。',
      ),
      ChatMessage(
        id: 'tool-result',
        role: MessageRole.user,
        content: const [
          MessageContent.toolResult(
            toolUseId: 'call_1',
            result: {'success': true, 'count': 1},
          ),
        ],
        timestamp: DateTime.fromMillisecondsSinceEpoch(2),
      ),
    ];

    test('Chat Completions encodes definitions, calls and results', () {
      final adapter = DeepSeekAdapter(
        apiKey: 'test-key',
        modelId: 'deepseek-v4-flash',
      );
      final request = adapter.buildRequestForTesting(
        messages: history,
        tools: tools,
      );

      expect(request['tools'][0]['function']['name'], 'searchRecipes');
      expect(request['messages'][1]['tool_calls'][0]['id'], 'call_1');
      expect(request['messages'][2]['role'], 'tool');
      expect(request['messages'][2]['tool_call_id'], 'call_1');
      expect(request['thinking']['type'], 'disabled');
      expect(request['parallel_tool_calls'], isFalse);
    });

    test('Responses encodes flat functions and function_call_output', () {
      final adapter = OpenAIAdapter(
        apiKey: 'test-key',
        modelId: 'deepseek-v4-flash',
        customApiUrl: 'https://api.deepseek.com',
        apiFormat: AIAPIFormat.responses,
      );
      final request = adapter.buildRequestForTesting(
        messages: history,
        tools: tools,
      );
      final input = request['input'] as List<dynamic>;

      expect(request['tools'][0]['name'], 'searchRecipes');
      expect(request['reasoning']['effort'], 'none');
      expect(request['parallel_tool_calls'], isFalse);
      expect(
        input.where((item) => item['type'] == 'function_call'),
        hasLength(1),
      );
      expect(
        input.where((item) => item['type'] == 'function_call_output'),
        hasLength(1),
      );
      final reasoning = input.singleWhere(
        (item) => item['type'] == 'reasoning',
      );
      expect(reasoning['content'][0]['type'], 'reasoning_text');
      expect(reasoning['content'][0]['text'], contains('先搜索'));
      expect(request, isNot(contains('prompt_cache_key')));
    });

    test('Responses explicitly enables thinking when requested', () {
      final adapter = OpenAIAdapter(
        apiKey: 'test-key',
        modelId: 'deepseek-v4-flash',
        customApiUrl: 'https://api.deepseek.com',
        apiFormat: AIAPIFormat.responses,
        enableThinking: true,
      );

      final request = adapter.buildRequestForTesting(
        messages: history,
        tools: tools,
      );

      expect(request['reasoning']['effort'], 'high');
    });

    test('Chat Completions encodes image input when model supports it', () {
      final adapter = DeepSeekAdapter(
        apiKey: 'test-key',
        modelId: 'deepseek-v4-flash-vision-exp',
        supportsImageInput: true,
      );
      final request = adapter.buildRequestForTesting(
        messages: [
          ChatMessage(
            id: 'vision',
            role: MessageRole.user,
            content: const [
              MessageContent.text(text: '这是什么？'),
              MessageContent.image(data: 'YWJj', mimeType: 'image/jpeg'),
            ],
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
      );
      final content = request['messages'][0]['content'] as List<dynamic>;

      expect(content.first['type'], 'text');
      expect(content.last['type'], 'image_url');
      expect(content.last['image_url']['url'], 'data:image/jpeg;base64,YWJj');
    });

    test('Vision model keeps Chat Completions in automatic mode', () {
      final adapter =
          AIServiceFactory.create(
                config(
                  modelId: 'deepseek-v4-flash-vision-exp',
                  capabilities: const ModelCapabilities(
                    supportsImageInput: true,
                  ),
                ),
              )
              as DeepSeekAdapter;
      final request = adapter.buildRequestForTesting(
        messages: [
          ChatMessage(
            id: 'vision-response',
            role: MessageRole.user,
            content: const [
              MessageContent.text(text: '识别图片'),
              MessageContent.image(data: 'YWJj', mimeType: 'image/png'),
            ],
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ],
      );
      final messages = request['messages'] as List<dynamic>;
      final messageContent = messages.single['content'] as List<dynamic>;

      expect(
        messageContent.where((item) => item['type'] == 'image_url'),
        hasLength(1),
      );
      expect(
        messageContent.last['image_url']['url'],
        'data:image/png;base64,YWJj',
      );
    });

    test('OpenAI-compatible DeepSeek Chat forwards thinking control', () {
      final adapter = OpenAIAdapter(
        apiKey: 'test-key',
        modelId: 'deepseek-v4-flash',
        customApiUrl: 'https://opencode.ai/zen/go/v1/chat/completions',
        apiFormat: AIAPIFormat.chatCompletions,
        enableThinking: false,
      );

      final request = adapter.buildRequestForTesting(
        messages: history,
        tools: tools,
      );

      expect(request['thinking']['type'], 'disabled');
      expect(request['parallel_tool_calls'], isFalse);
      expect(request['messages'][1]['reasoning_content'], contains('先搜索'));
    });

    test('factory keeps thinking toggle for custom OpenAI-compatible Chat', () {
      final adapter =
          AIServiceFactory.create(
                const AIModelConfig(
                  id: 'opencode-go',
                  provider: AIProvider.openai,
                  modelId: 'deepseek-v4-flash',
                  displayName: 'DeepSeek via OpenCode Go',
                  customApiKey: 'test-key',
                  customApiUrl: 'https://opencode.ai/zen/go/v1',
                  capabilities: ModelCapabilities(enableThinking: true),
                ),
              )
              as OpenAIAdapter;

      final request = adapter.buildRequestForTesting(messages: history);

      expect(request['thinking']['type'], 'enabled');
    });
  });
}
