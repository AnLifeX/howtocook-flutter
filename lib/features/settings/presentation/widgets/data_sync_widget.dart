import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:howtocook/core/services/data_sync_service.dart';
import 'package:howtocook/core/services/image_download_manager.dart';
import 'package:howtocook/core/widgets/app_snack_bar.dart';

/// 数据同步控制组件
class DataSyncWidget extends ConsumerStatefulWidget {
  const DataSyncWidget({super.key});

  @override
  ConsumerState<DataSyncWidget> createState() => _DataSyncWidgetState();
}

class _DataSyncWidgetState extends ConsumerState<DataSyncWidget> {
  bool _downloadCoverImages = true; // 下载封面图
  bool _downloadDetailImages = false; // 下载详情图

  @override
  Widget build(BuildContext context) {
    final dataSyncState = ref.watch(dataSyncServiceProvider);
    final imageDownloadState = ref.watch(imageDownloadManagerProvider);
    final dataSyncService = ref.read(dataSyncServiceProvider.notifier);
    final imageDownloadService = ref.read(
      imageDownloadManagerProvider.notifier,
    );

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据同步', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // 同步选项
            _buildSyncOptions(),
            const SizedBox(height: 16),

            // 同步按钮
            _buildSyncButton(dataSyncService, dataSyncState),
            const SizedBox(height: 16),

            // 同步进度
            if (dataSyncState.status != SyncStatus.idle)
              _buildSyncProgress(dataSyncState),

            // 图片下载进度
            if (imageDownloadState.status != DownloadStatus.idle)
              _buildImageDownloadProgress(
                imageDownloadState,
                imageDownloadService,
              ),

            const SizedBox(height: 16),

            // 存储信息
            _buildStorageInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('下载封面图'),
          subtitle: const Text('下载食谱的封面图片（AI生成，400x400）'),
          value: _downloadCoverImages,
          onChanged: (value) {
            setState(() {
              _downloadCoverImages = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text('下载详情图'),
          subtitle: const Text('下载食谱的详细步骤图片（较大，建议WiFi下载）'),
          value: _downloadDetailImages,
          onChanged: (value) {
            setState(() {
              _downloadDetailImages = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSyncButton(DataSyncService service, DataSyncState state) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed:
            state.status == SyncStatus.downloading ||
                state.status == SyncStatus.paused
            ? null
            : () {
                final config = SyncConfig(
                  downloadCoverImages: _downloadCoverImages,
                  downloadDetailImages: _downloadDetailImages,
                );
                service.startSync(config);
              },
        child: Text(
          _getButtonText(state.status),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  String _getButtonText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '开始同步';
      case SyncStatus.checking:
        return '检查更新中...';
      case SyncStatus.downloading:
        return '同步中...';
      case SyncStatus.paused:
        return '同步已暂停';
      case SyncStatus.completed:
        return '同步完成';
      case SyncStatus.error:
        return '同步失败，重试';
    }
  }

  Widget _buildSyncProgress(DataSyncState state) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: state.progress / 100),
        const SizedBox(height: 8),
        Text('总体进度：${state.progress}%', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          '食谱同步：${state.downloadedRecipes}/${state.totalRecipes}',
          style: theme.textTheme.bodySmall,
        ),
        if (state.totalTips > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '教程同步：${state.downloadedTips}/${state.totalTips}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '错误：${state.error}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageDownloadProgress(
    ImageDownloadState state,
    ImageDownloadManager service,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(value: state.progress / 100),
            ),
            const SizedBox(width: 8),
            Text(
              '${state.progress}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '图片下载: ${state.completedTasks}/${state.totalTasks}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              children: [
                if (state.status == DownloadStatus.downloading)
                  TextButton(
                    onPressed: () => service.pauseDownload(),
                    child: const Text('暂停'),
                  ),
                if (state.status == DownloadStatus.paused)
                  TextButton(
                    onPressed: () => service.resumeDownload(),
                    child: const Text('继续'),
                  ),
                TextButton(
                  onPressed: () => service.cancelAllDownloads(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStorageInfo() {
    return FutureBuilder<int>(
      future: _getTotalStorageSize(),
      builder: (context, snapshot) {
        final size = snapshot.data ?? 0;
        final sizeText = _formatBytes(size);

        return ListTile(
          leading: const Icon(Icons.storage),
          title: const Text('本地存储'),
          subtitle: Text('已使用: $sizeText'),
          trailing: TextButton(
            onPressed: () => _clearCache(),
            child: const Text('清理'),
          ),
        );
      },
    );
  }

  Future<int> _getTotalStorageSize() async {
    final dataSyncService = ref.read(dataSyncServiceProvider.notifier);
    final imageDownloadService = ref.read(
      imageDownloadManagerProvider.notifier,
    );

    final dataSize = await dataSyncService.getLocalDataSize();
    final imageSize = await imageDownloadService.getCacheSize();

    return dataSize + imageSize;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('确定要清理所有本地数据吗？这将删除已下载的食谱和图片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(dataSyncServiceProvider.notifier).clearLocalData();
              ref.read(imageDownloadManagerProvider.notifier).clearCache();
              Navigator.of(context).pop();
              AppSnackBar.show(context, '缓存已清理');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
