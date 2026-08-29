import 'package:flutter/foundation.dart';

@immutable
class AIChatTaskSnapshot {
  const AIChatTaskSnapshot({
    this.conversationId,
    this.statusText,
    this.partialText = '',
    this.isRunning = false,
    this.stopRequested = false,
  });

  final String? conversationId;
  final String? statusText;
  final String partialText;
  final bool isRunning;
  final bool stopRequested;
}

/// App-scoped view of the currently running chat task.
///
/// It lets navigation UI observe progress without owning or cancelling the
/// underlying network/tool execution.
class AIChatTaskCoordinator extends ChangeNotifier {
  AIChatTaskCoordinator._();

  static final instance = AIChatTaskCoordinator._();

  AIChatTaskSnapshot _snapshot = const AIChatTaskSnapshot();

  AIChatTaskSnapshot get snapshot => _snapshot;
  bool get isRunning => _snapshot.isRunning;

  bool begin(String conversationId) {
    if (_snapshot.isRunning) return false;
    _snapshot = AIChatTaskSnapshot(
      conversationId: conversationId,
      statusText: '回复中...',
      isRunning: true,
    );
    notifyListeners();
    return true;
  }

  void update({String? statusText, String? partialText}) {
    if (!_snapshot.isRunning) return;
    final shouldNotify = statusText != _snapshot.statusText;
    _snapshot = AIChatTaskSnapshot(
      conversationId: _snapshot.conversationId,
      statusText: statusText,
      partialText: partialText ?? _snapshot.partialText,
      isRunning: true,
      stopRequested: _snapshot.stopRequested,
    );
    // Streaming text can change for every token. Keep the latest snapshot but
    // rebuild app-level navigation only when the visible task status changes.
    if (shouldNotify) notifyListeners();
  }

  void requestStop() {
    if (!_snapshot.isRunning || _snapshot.stopRequested) return;
    _snapshot = AIChatTaskSnapshot(
      conversationId: _snapshot.conversationId,
      statusText: '正在停止...',
      partialText: _snapshot.partialText,
      isRunning: true,
      stopRequested: true,
    );
    notifyListeners();
  }

  void finish() {
    if (!_snapshot.isRunning) return;
    _snapshot = const AIChatTaskSnapshot();
    notifyListeners();
  }
}
