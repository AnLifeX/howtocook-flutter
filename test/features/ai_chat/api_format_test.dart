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
  }) {
    return AIModelConfig(
      id: 'test',
      provider: AIProvider.deepseek,
      modelId: 'deepseek-v4-flash',
      displayName: 'DeepSeek',
      customApiKey: 'test-key',
      customApiUrl: apiUrl,
      apiFormat: apiFormat,
      capabilities: const ModelCapabilities(supportsMCP: false),
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
  });
}
