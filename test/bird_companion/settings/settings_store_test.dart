import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'UI preferences persist while device facts remain session-owned',
    () async {
      final store = _MemorySettingsStore();
      final controller = BirdSettingsController(store: store);

      controller.setGridColumns(5);
      controller.setThumbnailSize(BirdThumbnailSize.large);
      controller.setCopyMode(BirdCopyMode.batchAllAssets);
      controller.setDefaultPhotoFilter(
        BirdDefaultPhotoFilter.pendingReview,
      );
      controller.setDevice('box-b');
      await Future<void>.delayed(Duration.zero);

      final restored = BirdSettingsController(store: store);
      addTearDown(controller.dispose);
      addTearDown(restored.dispose);

      expect(restored.gridColumns, 5);
      expect(restored.thumbnailSize, BirdThumbnailSize.large);
      expect(restored.copyMode, BirdCopyMode.batchAllAssets);
      expect(
        restored.defaultPhotoFilter,
        BirdDefaultPhotoFilter.pendingReview,
      );
      expect(restored.selectedDeviceId, 'k7-current');
    },
  );

  test('persisted preferences publish precise album and copy changes', () async {
    final store = _MemorySettingsStore();
    final bus = AppDataChangeBus();
    final controller = BirdSettingsController(
      store: store,
      dataChangeBus: bus,
    );
    addTearDown(controller.dispose);
    addTearDown(bus.dispose);

    final photoChange = bus.changes.first;
    controller.setGridColumns(5);
    expect(
      (await photoChange).resources,
      {AppDataResource.photoPreferences},
    );
    expect(store.snapshot.gridColumns, 5);

    final copyChange = bus.changes.first;
    controller.setReviewExportEnabled(false);
    expect(
      (await copyChange).resources,
      {AppDataResource.copyPreferences},
    );
    expect(store.snapshot.reviewExportEnabled, isFalse);
  });

  test('default gallery sort persists before its change event is published', () async {
    final store = _MemorySettingsStore();
    final bus = AppDataChangeBus();
    final controller = BirdSettingsController(
      store: store,
      dataChangeBus: bus,
    );
    addTearDown(controller.dispose);
    addTearDown(bus.dispose);

    final changed = bus.changes.first;
    controller.setSortOrder(BirdPhotoSortOrder.confidenceDescending);

    expect(
      (await changed).resources,
      {AppDataResource.photoPreferences},
    );
    expect(store.snapshot.sortOrder, 'confidenceDescending');
  });

  test('legacy dual track preference migrates to batch-all copy scope', () async {
    final store = _MemorySettingsStore.withJson({
      'copy_mode': 'dualTrack',
      'xmp_strategy': '生成同名 XMP（推荐）',
      'selected_storage_id': 'removable-e',
    });
    final controller = BirdSettingsController(store: store);
    addTearDown(controller.dispose);

    expect(controller.copyMode, BirdCopyMode.batchAllAssets);
    expect(controller.reviewExportEnabled, isTrue);
    // 旧全局默认目标盘直接丢弃，不映射到新设备（迁移对照文档 §5-E）。
    expect(store.snapshot.batchTargetPreferences, isEmpty);
  });
}

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore() : snapshot = const BirdSettingsSnapshot();

  _MemorySettingsStore.withJson(Map<String, dynamic> json)
    : snapshot = BirdSettingsSnapshot.fromJson(json);

  BirdSettingsSnapshot snapshot;

  @override
  BirdSettingsSnapshot read() => snapshot;

  @override
  Future<void> write(BirdSettingsSnapshot value) async {
    snapshot = value;
  }
}
