import 'package:aves/bird_companion/core/storage/local_cache.dart';

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
    this.copyMode = 'keptOnly',
    this.xmpStrategy = '生成同名 XMP（推荐）',
    this.verifyCopies = true,
    this.lowBatteryReminder = true,
    this.autoOpenReport = false,
    this.selectedStorageId = 'removable-e',
  });

  final int gridColumns;
  final bool showSubjectBox;
  final bool autoAdvance;
  final bool showRatingOverlay;
  final String thumbnailSize;
  final String sortOrder;
  final bool birdPhotosOnly;
  final String defaultPhotoFilter;
  final String copyMode;
  final String xmpStrategy;
  final bool verifyCopies;
  final bool lowBatteryReminder;
  final bool autoOpenReport;
  final String selectedStorageId;

  factory BirdSettingsSnapshot.fromJson(Map<String, dynamic> json) => BirdSettingsSnapshot(
    gridColumns: (json['grid_columns'] as num?)?.toInt() ?? 4,
    showSubjectBox: json['show_subject_box'] as bool? ?? true,
    autoAdvance: json['auto_advance'] as bool? ?? true,
    showRatingOverlay: json['show_rating_overlay'] as bool? ?? true,
    thumbnailSize: json['thumbnail_size']?.toString() ?? 'medium',
    sortOrder: json['sort_order']?.toString() ?? 'newest',
    birdPhotosOnly: json['bird_photos_only'] as bool? ?? true,
    defaultPhotoFilter: json['default_photo_filter']?.toString() ?? 'all',
    copyMode: json['copy_mode']?.toString() ?? 'keptOnly',
    xmpStrategy: json['xmp_strategy']?.toString() ?? '生成同名 XMP（推荐）',
    verifyCopies: json['verify_copies'] as bool? ?? true,
    lowBatteryReminder: json['low_battery_reminder'] as bool? ?? true,
    autoOpenReport: json['auto_open_report'] as bool? ?? false,
    selectedStorageId: json['selected_storage_id']?.toString() ?? 'removable-e',
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
    'xmp_strategy': xmpStrategy,
    'verify_copies': verifyCopies,
    'low_battery_reminder': lowBatteryReminder,
    'auto_open_report': autoOpenReport,
    'selected_storage_id': selectedStorageId,
  };
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
