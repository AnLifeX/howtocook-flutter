import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/core/services/data_sync_service.dart';
import 'package:howtocook/features/settings/domain/models/sync_item_state.dart';
import 'package:howtocook/features/settings/presentation/widgets/modern_data_sync_widget.dart';

void main() {
  test('V2 sync page exposes JSON, AI covers and optional offline images', () {
    expect(SyncItemInfo.items.map((item) => item.type), [
      SyncItemType.json,
      SyncItemType.coverImages,
      SyncItemType.fullDetailImages,
    ]);
    expect(SyncItemInfo.items[1].description, contains('仅替换'));
    expect(SyncItemInfo.items.last.description, contains('可选下载'));
  });

  test('maps live JSON synchronization progress to the visible card', () {
    final item = mapDataSyncStateToItemState(
      const DataSyncState(
        status: SyncStatus.downloading,
        progress: 47,
        downloadedRecipes: 180,
        totalRecipes: 367,
        downloadedTips: 0,
        totalTips: 18,
        downloadedImages: 0,
        totalImages: 0,
        message: '正在下载菜谱 180/367',
      ),
    );

    expect(item.status, SyncItemStatus.downloading);
    expect(item.completedItems, 47);
    expect(item.totalItems, 100);
    expect(item.message, '正在下载菜谱 180/367');
  });

  test('maps activation failures to an error state', () {
    final item = mapDataSyncStateToItemState(
      const DataSyncState(
        status: SyncStatus.error,
        progress: 92,
        downloadedRecipes: 367,
        totalRecipes: 367,
        downloadedTips: 18,
        totalTips: 18,
        downloadedImages: 0,
        totalImages: 0,
        message: '正在校验并激活 V2 数据...',
        error: 'manifest 写入失败',
      ),
    );

    expect(item.status, SyncItemStatus.error);
    expect(item.error, 'manifest 写入失败');
  });

  test('maps a paused background data download to resume controls', () {
    final item = mapDataSyncStateToItemState(
      const DataSyncState(
        status: SyncStatus.paused,
        progress: 63,
        downloadedRecipes: 220,
        totalRecipes: 367,
        downloadedTips: 4,
        totalTips: 18,
        downloadedImages: 0,
        totalImages: 0,
        message: '数据下载已暂停',
      ),
    );

    expect(item.status, SyncItemStatus.paused);
    expect(item.progress, 63);
    expect(item.message, '数据下载已暂停');
  });
}
