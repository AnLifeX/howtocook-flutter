import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/application/services/ai_chat_task_coordinator.dart';

void main() {
  final coordinator = AIChatTaskCoordinator.instance;

  setUp(coordinator.finish);
  tearDown(coordinator.finish);

  test('tracks one app-scoped chat task until it finishes', () {
    expect(coordinator.begin('conversation-a'), isTrue);
    expect(coordinator.begin('conversation-b'), isFalse);

    coordinator.update(statusText: '查询菜谱中...', partialText: '正在查找');

    expect(coordinator.snapshot.conversationId, 'conversation-a');
    expect(coordinator.snapshot.statusText, '查询菜谱中...');
    expect(coordinator.snapshot.partialText, '正在查找');
    expect(coordinator.snapshot.isRunning, isTrue);

    coordinator.finish();

    expect(coordinator.snapshot.isRunning, isFalse);
    expect(coordinator.snapshot.conversationId, isNull);
  });

  test('stop request remains visible while the task unwinds', () {
    coordinator.begin('conversation-a');
    coordinator.requestStop();

    expect(coordinator.snapshot.isRunning, isTrue);
    expect(coordinator.snapshot.stopRequested, isTrue);
    expect(coordinator.snapshot.statusText, '正在停止...');
  });
}
