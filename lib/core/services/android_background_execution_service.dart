import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';

/// Keeps the existing Flutter isolate alive while an AI request is running.
///
/// The AI stream and local recipe tools intentionally remain on the main
/// isolate so Hive/SQLite and tool state are not duplicated in another
/// isolate. Android runs a foreground service only for the lifetime of an
/// active request.
class AndroidBackgroundExecutionService {
  AndroidBackgroundExecutionService._();

  static final instance = AndroidBackgroundExecutionService._();

  bool _initialized = false;
  int _activeLeases = 0;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> acquire() async {
    if (!isSupported) return false;
    _activeLeases++;
    if (_activeLeases > 1 && FlutterBackground.isBackgroundExecutionEnabled) {
      return true;
    }

    try {
      if (!_initialized) {
        _initialized = await FlutterBackground.initialize(
          androidConfig: const FlutterBackgroundAndroidConfig(
            notificationTitle: '小厨正在回复',
            notificationText: '正在生成回复并处理菜谱工具，可返回应用查看进度',
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon: AndroidResource(
              name: 'ic_launcher',
              defType: 'mipmap',
            ),
            enableWifiLock: true,
            showBadge: false,
            // Do not interrupt the first message with a battery-settings page.
            // A foreground service, CPU wake lock and Wi-Fi lock are sufficient
            // for the normal background reply window.
            shouldRequestBatteryOptimizationsOff: false,
          ),
        );
      }
      if (!_initialized) {
        _activeLeases--;
        return false;
      }
      if (FlutterBackground.isBackgroundExecutionEnabled) return true;
      final enabled = await FlutterBackground.enableBackgroundExecution();
      if (!enabled) _activeLeases--;
      return enabled;
    } catch (error, stackTrace) {
      if (_activeLeases > 0) _activeLeases--;
      debugPrint('Unable to start Android AI foreground service: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  Future<void> release() async {
    if (!isSupported || _activeLeases == 0) return;
    _activeLeases--;
    if (_activeLeases > 0 || !FlutterBackground.isBackgroundExecutionEnabled) {
      return;
    }
    try {
      await FlutterBackground.disableBackgroundExecution();
    } catch (error, stackTrace) {
      debugPrint('Unable to stop Android AI foreground service: $error');
      debugPrint('$stackTrace');
    }
  }
}
