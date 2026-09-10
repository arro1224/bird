import 'package:aves/bird_companion/core/storage/local_cache.dart';

String photoQuerySortFromPreference(String value) => switch (value) {
  'qualityDescending' => 'score_desc',
  'recommendedFirst' => 'recommended_desc',
  'confidenceDescending' => 'confidence_desc',
  _ => 'captured_at_desc',
};

/// 旧偏好迁移（迁移对照文档 §5-E）：`dual`/`all`/`keptOnly` 映射到新复制范围。
/// 旧全局默认目标盘直接丢弃，不映射到任何新设备。
String migrateLegacyCopyMode(String? value) => switch (value) {
  'batchAllAssets' || 'dualTrack' || 'all' => 'batchAllAssets',
  'keptAssets' || 'keptOnly' => 'keptAssets',
  _ => 'keptAssets',
};

bool migrateLegacyReviewExport(String? value) =>
    value == null || value != '不导出标记';

class BirdSettingsSnapshot {
  const BirdSettingsSnapshot({
    this.gridColumns = 4,
    this.showSubjectBox = true,
    this.autoAdvance = true,
    this.showRatingOverlay = true,
    this.thumbnailSize = 'medium',
    this.sortOrder = 'newest',
    this.birdPhotosOnly = true,
    this.defaultPhotoFilter = 'all',
    this.copyMode = 'keptAssets',
    this.reviewExportEnabled = true,
    this.embedReviewMetadata = true,
    this.lowBatteryReminder = true,
    this.autoOpenReport = false,
    this.batchTargetPreferences = const {},
  });

  final int gridColumns;
  final bool showSubjectBox;
  final bool autoAdvance;
  final bool showRatingOverlay;
  final String thumbnailSize;
  final String sortOrder;
  final bool birdPhotosOnly;
  final String defaultPhotoFilter;

  /// 默认复制范围（仅作为页面初始偏好，§3.7），值为 `keptAssets`/`batchAllAssets`。
  final String copyMode;

  /// 随副本保存审阅信息（XMP + CSV）。
  final bool reviewExportEnabled;

  /// 安全兼容的副本格式上优先嵌入标准字段（§9.1 embed_into_supported_copy）。
  final bool embedReviewMetadata;
  final bool lowBatteryReminder;
  final bool autoOpenReport;

  /// 同批次上次成功目标设备（batchId → media_id），仅作为可修改的预选（§4.4）。
  final Map<String, String> batchTargetPreferences;

  BirdSettingsSnapshot copyWith({
    String? copyMode,
    bool? reviewExportEnabled,
    bool? embedReviewMetadata,
    bool? lowBatteryReminder,
    bool? autoOpenReport,
    Map<String, String>? batchTargetPreferences,
  }) => BirdSettingsSnapshot(
    gridColumns: gridColumns,
    showSubjectBox: showSubjectBox,
    autoAdvance: autoAdvance,
    showRatingOverlay: showRatingOverlay,
    thumbnailSize: thumbnailSize,
    sortOrder: sortOrder,
    birdPhotosOnly: birdPhotosOnly,
    defaultPhotoFilter: defaultPhotoFilter,
    copyMode: copyMode ?? this.copyMode,
    reviewExportEnabled: reviewExportEnabled ?? this.reviewExportEnabled,
    embedReviewMetadata: embedReviewMetadata ?? this.embedReviewMetadata,
    lowBatteryReminder: lowBatteryReminder ?? this.lowBatteryReminder,
    autoOpenReport: autoOpenReport ?? this.autoOpenReport,
    batchTargetPreferences: batchTargetPreferences ?? this.batchTargetPreferences,
  );

  factory BirdSettingsSnapshot.fromJson(Map<String, dynamic> json) => BirdSettingsSnapshot(
    gridColumns: (json['grid_columns'] as num?)?.toInt() ?? 4,
    showSubjectBox: json['show_subject_box'] as bool? ?? true,
    autoAdvance: json['auto_advance'] as bool? ?? true,
    showRatingOverlay: json['show_rating_overlay'] as bool? ?? true,
    thumbnailSize: json['thumbnail_size']?.toString() ?? 'medium',
    sortOrder: json['sort_order']?.toString() ?? 'newest',
    birdPhotosOnly: json['bird_photos_only'] as bool? ?? true,
    defaultPhotoFilter: json['default_photo_filter']?.toString() ?? 'all',
    copyMode: migrateLegacyCopyMode(json['copy_mode']?.toString()),
    reviewExportEnabled: migrateLegacyReviewExport(
      json['xmp_strategy']?.toString(),
    ),
    embedReviewMetadata: json['embed_review_metadata'] as bool? ?? true,
    lowBatteryReminder: json['low_battery_reminder'] as bool? ?? true,
    autoOpenReport: json['auto_open_report'] as bool? ?? false,
    batchTargetPreferences: _stringMap(
      json['batch_target_preferences'],
    ),
  );

  Map<String, dynamic> toJson() => {
    'grid_columns': gridColumns,
    'show_subject_box': showSubjectBox,
    'auto_advance': autoAdvance,
    'show_rating_overlay': showRatingOverlay,
    'thumbnail_size': thumbnailSize,
    'sort_order': sortOrder,
    'bird_photos_only': birdPhotosOnly,
    'default_photo_filter': defaultPhotoFilter,
    'copy_mode': copyMode,
    'review_export_enabled': reviewExportEnabled,
    'embed_review_metadata': embedReviewMetadata,
    'low_battery_reminder': lowBatteryReminder,
    'auto_open_report': autoOpenReport,
    'batch_target_preferences': batchTargetPreferences,
  };
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable(<String, String>{
    for (final entry in value.entries)
      if (entry.value != null) entry.key.toString(): entry.value.toString(),
  });
}

abstract interface class SettingsStore {
  BirdSettingsSnapshot read();

  Future<void> write(BirdSettingsSnapshot snapshot);
}

class BirdSettingsStore implements SettingsStore {
  BirdSettingsStore(this._cache);

  static const cacheKey = 'settings:ui:v1';
  final LocalCache _cache;

  @override
  BirdSettingsSnapshot read() {
    final value = _cache.read<Map>(cacheKey);
    return value == null
        ? const BirdSettingsSnapshot()
        : BirdSettingsSnapshot.fromJson(
            Map<String, dynamic>.from(value),
          );
  }

  @override
  Future<void> write(BirdSettingsSnapshot snapshot) => _cache.write(cacheKey, snapshot.toJson());
}
