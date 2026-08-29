import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

typedef NotificationTapCallback = void Function(String? payload);

/// 应用通知服务（纯信息通知，不含下载进度）
class AppNotificationService {
  AppNotificationService._();
  static final instance = AppNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  NotificationTapCallback? _onTap;
  bool _initialized = false;

  static const _channelId = 'data_sync_updates';
  static const _channelName = '数据更新提醒';
  static const _channelDesc = '菜谱和教程数据源更新通知';

  Future<void> initialize({NotificationTapCallback? onTap}) async {
    if (_initialized) {
      if (onTap != null) _onTap = onTap;
      return;
    }
    _onTap = onTap;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleTap,
    );
    _initialized = true;
  }

  void _handleTap(NotificationResponse response) {
    _onTap?.call(response.payload);
  }

  void handleNotificationTap(String? payload) {
    _onTap?.call(payload);
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<void> showDataUpdateNotification({
    required int newRecipes,
    required int updatedRecipes,
    required int newTips,
    required int updatedTips,
  }) async {
    final parts = <String>[];
    if (newRecipes > 0) parts.add('$newRecipes 个新菜谱');
    if (updatedRecipes > 0) parts.add('$updatedRecipes 个菜谱更新');
    if (newTips > 0) parts.add('$newTips 个新教程');
    if (updatedTips > 0) parts.add('$updatedTips 个教程更新');

    if (parts.isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );

    await _plugin.show(
      id: 1001,
      title: '发现数据更新',
      body: parts.join('、'),
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'data-sync',
    );
  }

  Future<void> showImageDownloadNotification({
    required int missingImages,
  }) async {
    if (missingImages <= 0) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );

    await _plugin.show(
      id: 1002,
      title: '详情图未下载',
      body: '有 $missingImages 张菜谱详情图可下载，点击前往下载',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'data-sync',
    );
  }

  static const _downloadChannelId = 'image_download_progress';
  static const _downloadChannelName = '图片下载进度';
  static const _downloadNotifId = 1003;

  Future<void> showDownloadProgress({
    required int completed,
    required int total,
    required int progress,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: '菜谱详情图下载进度',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progress.clamp(0, 100),
      onlyAlertOnce: true,
    );

    await _plugin.show(
      id: _downloadNotifId,
      title: '正在下载详情图',
      body: '$completed / $total',
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'data-sync',
    );
  }

  Future<void> showDownloadComplete({
    required int total,
    int failed = 0,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _downloadChannelId,
      _downloadChannelName,
      channelDescription: '菜谱详情图下载进度',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );

    final body = failed > 0 ? '$total 张图片已下载，$failed 张失败' : '全部 $total 张图片已下载';

    await _plugin.show(
      id: _downloadNotifId,
      title: '详情图下载完成',
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'data-sync',
    );
  }

  Future<void> cancelDownloadNotification() async {
    await _plugin.cancel(id: _downloadNotifId);
  }

  static const _aiChatChannelId = 'ai_chat_results';
  static const _aiChatChannelName = '小厨回复提醒';
  static const _aiChatNotificationId = 1004;

  Future<void> showAIChatResult({required bool succeeded}) async {
    if (!Platform.isAndroid) return;
    const androidDetails = AndroidNotificationDetails(
      _aiChatChannelId,
      _aiChatChannelName,
      channelDescription: '小厨在后台完成回复或工具调用后的提醒',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
    );
    await _plugin.show(
      id: _aiChatNotificationId,
      title: succeeded ? '小厨已完成回复' : '小厨回复中断',
      body: succeeded ? '点击返回会话查看完整结果' : '点击返回会话查看已保留的内容和错误信息',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: 'ai-chat',
    );
  }
}
