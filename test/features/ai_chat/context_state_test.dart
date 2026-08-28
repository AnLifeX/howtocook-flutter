import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/ai_usage_metrics.dart';
import 'package:howtocook/features/ai_chat/domain/entities/chat_message.dart';
import 'package:howtocook/features/ai_chat/domain/entities/conversation_context_state.dart';
import 'package:howtocook/features/ai_chat/infrastructure/services/ai_service_factory.dart';

void main() {
  test(
    'runtime context survives message persistence without changing content',
    () {
      final message = ChatMessage(
        id: 'message-1',
        role: MessageRole.user,
        content: const [MessageContent.text(text: '今天吃什么？')],
        timestamp: DateTime.utc(2026, 8, 28),
        runtimeContext: '[运行时信息：晚上 18:30]',
      );

      final restored = ChatMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );
      expect(restored.runtimeContext, message.runtimeContext);
      expect((restored.content.single as TextContent).text, '今天吃什么？');
    },
  );

  test('conversation context accumulates provider cache usage', () {
    final state = const ConversationContextState().recordUsage(
      const AIUsageMetrics(
        inputTokens: 1000,
        outputTokens: 80,
        cacheReadTokens: 750,
        cacheMissTokens: 250,
      ),
    );

    expect(state.lastInputTokens, 1000);
    expect(state.totalCacheReadTokens, 750);
    expect(state.cacheHitRate, 0.75);
    expect(
      ConversationContextState.fromJson(state.toJson()).cacheHitRate,
      0.75,
    );
  });

  test('the app no longer ships built-in AI models', () {
    expect(AIServiceFactory.getBuiltinModels(), isEmpty);
  });
}
