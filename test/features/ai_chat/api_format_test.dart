import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/ai_model_config.dart';
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
}
