import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter/foundation.dart';

enum BirdPhotoSortOrder {
  newest('拍摄时间最新'),
  qualityDescending('照片质量从高到低'),
  recommendedFirst('系统推荐优先'),
  confidenceDescending('识别置信度从高到低');

  const BirdPhotoSortOrder(this.label);
  final String label;

  String get querySort => photoQuerySortFromPreference(name);
}

enum BirdCopyMode {
  keptAssets('只复制已保留'),
  batchAllAssets('复制全部');

  const BirdCopyMode(this.label);
  final String label;
}

enum BirdThumbnailSize {
  small('小'),
  medium('中'),
  large('大');

  const BirdThumbnailSize(this.label);
  final String label;
}

enum BirdDefaultPhotoFilter {
  all('不过滤'),
  pendingReview('待确认照片'),
  recommended('系统推荐'),
  highScore('4 星及以上');

  const BirdDefaultPhotoFilter(this.label);
  final String label;
}

class BirdSettingsController extends ChangeNotifier {
  BirdSettingsController({
    SettingsStore? store,
    this.dataChangeBus,
  }) : _store = store,
       super() {
    final snapshot = store?.read();
    if (snapshot != null) _restore(snapshot);
  }

  final SettingsStore? _store;
  final AppDataChangeBus? dataChangeBus;
  Future<void> _persistTail = Future.value();

  int gridColumns = 4;
  bool showSubjectBox = true;
  bool autoAdvance = true;
  bool showRatingOverlay = true;
  BirdThumbnailSize thumbnailSize = BirdThumbnailSize.medium;
  BirdPhotoSortOrder sortOrder = BirdPhotoSortOrder.newest;
  bool birdPhotosOnly = true;
  BirdDefaultPhotoFilter defaultPhotoFilter = BirdDefaultPhotoFilter.all;
  BirdCopyMode copyMode = BirdCopyMode.keptAssets;
  bool reviewExportEnabled = true;
  bool embedReviewMetadata = true;
  bool lowBatteryReminder = true;
  bool autoOpenReport = false;
  Map<String, String> batchTargetPreferences = const {};
  String selectedDeviceId = 'k7-current';
  bool technicalDetailsExpanded = false;
  bool searchingDevices = false;

  void setGridColumns(int value) => _set(
    () => gridColumns = value,
    resource: AppDataResource.photoPreferences,
  );
  void setShowSubjectBox(bool value) => _set(
    () => showSubjectBox = value,
    resource: AppDataResource.photoPreferences,
  );
  void setAutoAdvance(bool value) => _set(
    () => autoAdvance = value,
    resource: AppDataResource.photoPreferences,
  );
  void setShowRatingOverlay(bool value) => _set(
    () => showRatingOverlay = value,
    resource: AppDataResource.photoPreferences,
  );
  void setThumbnailSize(BirdThumbnailSize value) => _set(
    () => thumbnailSize = value,
    resource: AppDataResource.photoPreferences,
  );
  void setSortOrder(BirdPhotoSortOrder value) => _set(
    () => sortOrder = value,
    resource: AppDataResource.photoPreferences,
  );
  void setBirdPhotosOnly(bool value) => _set(
    () => birdPhotosOnly = value,
    resource: AppDataResource.photoPreferences,
  );
  void setDefaultPhotoFilter(BirdDefaultPhotoFilter value) => _set(
    () => defaultPhotoFilter = value,
    resource: AppDataResource.photoPreferences,
  );
  void setCopyMode(BirdCopyMode value) => _set(
    () => copyMode = value,
    resource: AppDataResource.copyPreferences,
  );
  void setReviewExportEnabled(bool value) => _set(
    () => reviewExportEnabled = value,
    resource: AppDataResource.copyPreferences,
  );
  void setEmbedReviewMetadata(bool value) => _set(
    () => embedReviewMetadata = value,
    resource: AppDataResource.copyPreferences,
  );
  void setLowBatteryReminder(bool value) => _set(
    () => lowBatteryReminder = value,
    resource: AppDataResource.copyPreferences,
  );
  void setAutoOpenReport(bool value) => _set(
    () => autoOpenReport = value,
    resource: AppDataResource.copyPreferences,
  );
  void setDevice(String value) => _set(() => selectedDeviceId = value);

  /// 同批次上次成功目标设备（batchId → media_id），仅用于复制流程预选。
  String? targetPreferenceFor(String batchId) {
    final id = batchId.trim();
    if (id.isEmpty) return null;
    final value = batchTargetPreferences[id]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  void rememberCopyTarget(String batchId, String mediaId) {
    final id = batchId.trim();
    if (id.isEmpty || mediaId.trim().isEmpty) return;
    _set(
      () => batchTargetPreferences = {
        ...batchTargetPreferences,
        id: mediaId.trim(),
      },
      resource: AppDataResource.copyPreferences,
    );
  }
  void toggleTechnicalDetails() => _set(() => technicalDetailsExpanded = !technicalDetailsExpanded);
  void beginDeviceSearch() => _set(() => searchingDevices = true);

  void resetDisplaySettings() {
    gridColumns = 4;
    showSubjectBox = true;
    autoAdvance = true;
    showRatingOverlay = true;
    thumbnailSize = BirdThumbnailSize.medium;
    sortOrder = BirdPhotoSortOrder.newest;
    _changed(resource: AppDataResource.photoPreferences);
  }

  void _set(
    VoidCallback update, {
    AppDataResource? resource,
  }) {
    update();
    _changed(resource: resource);
  }

  void _changed({AppDataResource? resource}) {
    notifyListeners();
    final store = _store;
    if (store != null) {
      final snapshot = _snapshot();
      _persistTail = _persistTail.then((_) async {
        await store.write(snapshot);
        if (resource != null) {
          dataChangeBus?.publish(
            {resource},
            reason: 'settings_${resource.name}_changed',
          );
        }
      });
      unawaited(_persistTail);
    } else if (resource != null) {
      dataChangeBus?.publish(
        {resource},
        reason: 'settings_${resource.name}_changed',
      );
    }
  }

  void _restore(BirdSettingsSnapshot snapshot) {
    gridColumns = snapshot.gridColumns.clamp(2, 6);
    showSubjectBox = snapshot.showSubjectBox;
    autoAdvance = snapshot.autoAdvance;
    showRatingOverlay = snapshot.showRatingOverlay;
    thumbnailSize = BirdThumbnailSize.values.firstWhere(
      (value) => value.name == snapshot.thumbnailSize,
      orElse: () => BirdThumbnailSize.medium,
    );
    sortOrder = BirdPhotoSortOrder.values.firstWhere(
      (value) => value.name == snapshot.sortOrder,
      orElse: () => BirdPhotoSortOrder.newest,
    );
    birdPhotosOnly = snapshot.birdPhotosOnly;
    defaultPhotoFilter = BirdDefaultPhotoFilter.values.firstWhere(
      (value) => value.name == snapshot.defaultPhotoFilter,
      orElse: () => BirdDefaultPhotoFilter.all,
    );
    copyMode = BirdCopyMode.values.firstWhere(
      (value) => value.name == snapshot.copyMode,
      orElse: () => BirdCopyMode.keptAssets,
    );
    reviewExportEnabled = snapshot.reviewExportEnabled;
    embedReviewMetadata = snapshot.embedReviewMetadata;
    lowBatteryReminder = snapshot.lowBatteryReminder;
    autoOpenReport = snapshot.autoOpenReport;
    batchTargetPreferences = snapshot.batchTargetPreferences;
  }

  BirdSettingsSnapshot _snapshot() => BirdSettingsSnapshot(
    gridColumns: gridColumns,
    showSubjectBox: showSubjectBox,
    autoAdvance: autoAdvance,
    showRatingOverlay: showRatingOverlay,
    thumbnailSize: thumbnailSize.name,
    sortOrder: sortOrder.name,
    birdPhotosOnly: birdPhotosOnly,
    defaultPhotoFilter: defaultPhotoFilter.name,
    copyMode: copyMode.name,
    reviewExportEnabled: reviewExportEnabled,
    embedReviewMetadata: embedReviewMetadata,
    lowBatteryReminder: lowBatteryReminder,
    autoOpenReport: autoOpenReport,
    batchTargetPreferences: batchTargetPreferences,
  );
}
