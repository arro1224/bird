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
      controller.setCopyMode(BirdCopyMode.dualTrack);
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
      expect(restored.copyMode, BirdCopyMode.dualTrack);
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
    controller.setVerifyCopies(false);
    expect(
      (await copyChange).resources,
      {AppDataResource.copyPreferences},
    );
    expect(store.snapshot.verifyCopies, isFalse);
  });
}

class _MemorySettingsStore implements SettingsStore {
  BirdSettingsSnapshot snapshot = const BirdSettingsSnapshot();

  @override
  BirdSettingsSnapshot read() => snapshot;

  @override
  Future<void> write(BirdSettingsSnapshot value) async {
    snapshot = value;
  }
}
