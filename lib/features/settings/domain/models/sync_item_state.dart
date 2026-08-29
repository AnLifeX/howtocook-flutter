import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'sync_item_state.freezed.dart';

/// 同步项类型
enum SyncItemType {
  json, // JSON数据
  coverImages, // 封面图
  detailImages, // 详情图（增量更新）
  fullDetailImages, // 完整详情图（初始化下载）
}

/// 同步项状态
enum SyncItemStatus {
  idle, // 空闲
  checking, // 检查更新中
  updateAvailable, // 有更新可用
  downloading, // 下载中
  paused, // 已暂停
  completed, // 已完成
  error, // 错误
}

/// 同步项状态数据
@freezed
class SyncItemState with _$SyncItemState {
  const factory SyncItemState({
    required SyncItemType type,
    required SyncItemStatus status,
    @Default(0) int progress, // 0-100
    @Default(0) int totalItems, // 总数
    @Default(0) int completedItems, // 已完成数
    String? message, // 提示信息
    String? error, // 错误信息
  }) = _SyncItemState;

  factory SyncItemState.initial(SyncItemType type) =>
      SyncItemState(type: type, status: SyncItemStatus.idle);
}

/// 同步项信息
class SyncItemInfo {
  final SyncItemType type;
  final String title;
  final String description;
  final IconData icon;

  const SyncItemInfo({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
  });

  static const items = [
    SyncItemInfo(
      type: SyncItemType.json,
      title: 'V2 菜谱数据',
      description: '菜谱、教程及旧 ID 迁移数据',
      icon: Icons.description,
    ),
    SyncItemInfo(
      type: SyncItemType.coverImages,
      title: 'AI 封面图',
      description: '按版本更新；仅替换已有新封面的菜谱',
      icon: Icons.auto_awesome,
    ),
    SyncItemInfo(
      type: SyncItemType.fullDetailImages,
      title: '离线详情图',
      description: '可选下载；支持后台、暂停与继续',
      icon: Icons.file_download,
    ),
  ];

  static SyncItemInfo getInfo(SyncItemType type) {
    return items.firstWhere((item) => item.type == type);
  }
}
