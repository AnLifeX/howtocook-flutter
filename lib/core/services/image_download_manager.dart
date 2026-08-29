import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:background_downloader/background_downloader.dart'
    hide DownloadTask;
import 'package:background_downloader/background_downloader.dart'
    as bd
    show DownloadTask;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'app_notification_service.dart';
import 'cover_manifest_service.dart';

part 'image_download_manager.g.dart';
part 'image_download_manager.freezed.dart';

enum DownloadStatus { idle, downloading, paused, completed, error }

class DownloadTask {
  final String id;
  final String category;
  final String recipeId;
  final String imageUrl;
  final String localPath;
  final int priority;
  final bool replaceExisting;
  final String? expectedSha256;
  final String? coverVersion;
  final CoverManifestEntry? coverEntry;
  DownloadStatus status;
  int progress;
  String? error;

  DownloadTask({
    required this.id,
    required this.category,
    required this.recipeId,
    required this.imageUrl,
    required this.localPath,
    this.priority = 0,
    this.replaceExisting = false,
    this.expectedSha256,
    this.coverVersion,
    this.coverEntry,
    this.status = DownloadStatus.idle,
    this.progress = 0,
    this.error,
  });
}

@Riverpod(keepAlive: true)
class ImageDownloadManager extends _$ImageDownloadManager {
  static const String _cacheDirName = 'recipe_images';
  static const String _taskGroup = 'howtocook-images';

  final Map<String, DownloadTask> _tasks = {};
  bool _isPaused = false;

  @override
  ImageDownloadState build() {
    return const ImageDownloadState(
      status: DownloadStatus.idle,
      totalTasks: 0,
      completedTasks: 0,
      progress: 0,
    );
  }

  void addDownloadTasks(List<DownloadTask> tasks) {
    if (state.status != DownloadStatus.downloading &&
        state.status != DownloadStatus.paused) {
      _tasks.clear();
    }
    for (final task in tasks) {
      _tasks[task.id] = task;
    }

    state = state.copyWith(
      totalTasks: _tasks.length,
      completedTasks: _getCompletedCount(),
    );

    if (!_isPaused) {
      _startBatchDownload();
    }
  }

  Future<void> _startBatchDownload() async {
    final pendingTasks = _tasks.values
        .where(
          (t) =>
              t.status == DownloadStatus.idle ||
              t.status == DownloadStatus.error,
        )
        .toList();

    if (pendingTasks.isEmpty) {
      state = state.copyWith(status: DownloadStatus.completed, progress: 100);
      return;
    }

    state = state.copyWith(status: DownloadStatus.downloading, progress: 0);
    _isPaused = false;

    final bdTasks = <bd.DownloadTask>[];
    for (final task in pendingTasks) {
      if (task.replaceExisting) await _recoverPreviousFile(task);
      final file = File(_downloadPath(task));
      await file.parent.create(recursive: true);
      if (task.replaceExisting && await file.exists()) {
        await file.delete();
      }

      final (baseDirectory, directory, filename) = await Task.split(
        filePath: file.path,
      );
      bdTasks.add(
        bd.DownloadTask(
          url: task.imageUrl,
          filename: filename,
          directory: directory,
          baseDirectory: baseDirectory,
          group: _taskGroup,
          updates: Updates.status,
          retries: 1,
          allowPause: true,
          priority: task.priority,
        ),
      );

      task.status = DownloadStatus.downloading;
    }

    final baseCompleted = _getCompletedCount();
    final notif = AppNotificationService.instance;

    notif.showDownloadProgress(
      completed: baseCompleted,
      total: _tasks.length,
      progress: 0,
    );

    try {
      final batch = await FileDownloader().downloadBatch(
        bdTasks,
        batchProgressCallback: (succeeded, failed) {
          final completed = succeeded + failed;
          final currentCompleted = baseCompleted + succeeded;
          final currentProgress = _tasks.isEmpty
              ? 0
              : ((baseCompleted + completed) / _tasks.length * 100).round();

          state = state.copyWith(
            completedTasks: currentCompleted,
            progress: currentProgress,
          );

          notif.showDownloadProgress(
            completed: currentCompleted,
            total: _tasks.length,
            progress: currentProgress,
          );
        },
        taskStatusCallback: (update) {
          final matchingTask = _findTaskByUrl(update.task.url);
          if (matchingTask == null) return;

          switch (update.status) {
            case TaskStatus.complete:
              matchingTask.status = DownloadStatus.completed;
              matchingTask.progress = 100;
            case TaskStatus.failed:
            case TaskStatus.notFound:
              matchingTask.status = DownloadStatus.error;
              matchingTask.error = update.exception?.description ?? '下载失败';
            case TaskStatus.canceled:
              matchingTask.status = DownloadStatus.paused;
            default:
              break;
          }
        },
      );

      for (final task in pendingTasks.where(
        (item) => item.status == DownloadStatus.completed,
      )) {
        try {
          await _finalizeDownloadedTask(task);
        } catch (error) {
          task.status = DownloadStatus.error;
          task.error = error.toString();
          debugPrint('❌ 图片替换失败 ${task.localPath}: $error');
        }
      }

      final allCompleted = _tasks.values.every(
        (t) => t.status == DownloadStatus.completed,
      );

      state = state.copyWith(
        status: allCompleted ? DownloadStatus.completed : DownloadStatus.error,
        progress: allCompleted ? 100 : state.progress,
        completedTasks: _getCompletedCount(),
        error: batch.numFailed > 0
            ? '${batch.numFailed} 张图片下载失败'
            : allCompleted
            ? null
            : '${_tasks.length - _getCompletedCount()} 张图片校验或替换失败',
      );

      notif.showDownloadComplete(
        total: _getCompletedCount(),
        failed: batch.numFailed,
      );
    } catch (e) {
      debugPrint('❌ 批量下载异常: $e');
      state = state.copyWith(status: DownloadStatus.error, error: e.toString());
      notif.cancelDownloadNotification();
    }
  }

  DownloadTask? _findTaskByUrl(String url) {
    return _tasks.values.where((t) => t.imageUrl == url).firstOrNull;
  }

  String _downloadPath(DownloadTask task) =>
      task.replaceExisting ? '${task.localPath}.download' : task.localPath;

  Future<void> _recoverPreviousFile(DownloadTask task) async {
    final target = File(task.localPath);
    final backup = File('${task.localPath}.previous');
    if (!await backup.exists()) return;
    if (await target.exists()) {
      await backup.delete();
    } else {
      await backup.rename(target.path);
    }
  }

  Future<void> _finalizeDownloadedTask(DownloadTask task) async {
    if (!task.replaceExisting) return;
    final temporary = File(_downloadPath(task));
    if (!await temporary.exists()) throw const FileSystemException('下载临时文件不存在');

    final expectedHash = task.expectedSha256;
    if (expectedHash != null) {
      final actualHash = (await sha256.bind(temporary.openRead()).first)
          .toString();
      if (actualHash != expectedHash) {
        await temporary.delete();
        throw StateError('封面哈希校验失败');
      }
    }

    final target = File(task.localPath);
    final backup = File('${task.localPath}.previous');
    await target.parent.create(recursive: true);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) {
      PaintingBinding.instance.imageCache.evict(FileImage(target));
      await target.rename(backup.path);
    }

    try {
      await temporary.rename(target.path);
      final entry = task.coverEntry;
      final coverVersion = task.coverVersion;
      if (entry != null && coverVersion != null) {
        await CoverManifestService().recordDownloadedCover(
          coverVersion: coverVersion,
          entry: entry,
        );
      }
      if (await backup.exists()) await backup.delete();
      PaintingBinding.instance.imageCache.evict(FileImage(target));
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }

  void pauseDownload() async {
    _isPaused = true;
    final activeTasks = await FileDownloader().allTasks(group: _taskGroup);
    if (activeTasks.isNotEmpty) {
      await FileDownloader().cancelTasksWithIds(
        activeTasks.map((t) => t.taskId).toList(),
      );
    }

    for (final task in _tasks.values) {
      if (task.status == DownloadStatus.downloading) {
        task.status = DownloadStatus.paused;
      }
    }

    AppNotificationService.instance.cancelDownloadNotification();
    state = state.copyWith(status: DownloadStatus.paused);
  }

  void resumeDownload() {
    if (state.status != DownloadStatus.paused) return;

    for (final task in _tasks.values) {
      if (task.status == DownloadStatus.paused) {
        task.status = DownloadStatus.idle;
      }
    }

    _isPaused = false;
    _startBatchDownload();
  }

  void cancelAllDownloads() async {
    _isPaused = true;
    final activeTasks = await FileDownloader().allTasks(group: _taskGroup);
    if (activeTasks.isNotEmpty) {
      await FileDownloader().cancelTasksWithIds(
        activeTasks.map((t) => t.taskId).toList(),
      );
    }

    _tasks.clear();
    AppNotificationService.instance.cancelDownloadNotification();
    state = const ImageDownloadState(
      status: DownloadStatus.idle,
      totalTasks: 0,
      completedTasks: 0,
      progress: 0,
    );
  }

  int _getCompletedCount() {
    return _tasks.values
        .where((t) => t.status == DownloadStatus.completed)
        .length;
  }

  List<DownloadTask> getAllTasks() => _tasks.values.toList();

  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/$_cacheDirName');
      if (!await imageCacheDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in imageCacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      debugPrint('❌ 计算缓存大小失败: $e');
      return 0;
    }
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = await getApplicationDocumentsDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/$_cacheDirName');
      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('❌ 清理缓存失败: $e');
    }
  }
}

@freezed
class ImageDownloadState with _$ImageDownloadState {
  const factory ImageDownloadState({
    required DownloadStatus status,
    required int totalTasks,
    required int completedTasks,
    required int progress,
    String? error,
  }) = _ImageDownloadState;
}
