/// Domain models for the frozen copy contract `birdbox-copy-v1`.
///
/// Field names and semantics follow `拍鸟盒子_复制全量备份与多存储设备三端协议
/// _v1.0-rc1_开发冻结版_2026-08-24.md`. The App never invents parallel enums
/// or mock fields that are not part of the protocol.
library;

import 'package:aves/bird_companion/core/models/protocol_validation.dart';

/// 复制范围（主协议 §5）。
enum CopyScope {
  selectedAssets('selected_assets', '复制我选中的照片'),
  keptAssets('kept_assets', '复制本批次已保留的照片'),
  batchAllAssets('batch_all_assets', '复制本批次全部照片'),
  mediaFullBackup('media_full_backup', '备份源设备全部摄影资料');

  const CopyScope(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CopyScope fromWire(String? value) => switch (value) {
    'selected_assets' => CopyScope.selectedAssets,
    'kept_assets' => CopyScope.keptAssets,
    'batch_all_assets' => CopyScope.batchAllAssets,
    'media_full_backup' => CopyScope.mediaFullBackup,
    _ => throw const ProtocolCompatibilityException('scope', '必须是 birdbox-copy-v1 复制范围'),
  };
}

/// RAW+JPEG 配对策略（主协议 §6.2）。
enum PairPolicy {
  rawOnly('raw_only', '仅复制 RAW'),
  jpegOnly('jpeg_only', '仅复制 JPEG/HEIF'),
  both('both', 'RAW 与 JPEG/HEIF 都复制');

  const PairPolicy(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static PairPolicy fromWire(String? value) => switch (value) {
    'raw_only' => PairPolicy.rawOnly,
    'jpeg_only' => PairPolicy.jpegOnly,
    'both' => PairPolicy.both,
    _ => throw const ProtocolCompatibilityException('pair_policy', '必须是 birdbox-copy-v1 配对策略'),
  };
}

/// 同名冲突策略（主协议 §8）。新建任务时必填，协议禁止默认值。
enum ConflictStrategy {
  skip('skip', '跳过目标盘已有文件'),
  overwrite('overwrite', '覆盖目标盘副本'),
  keepBoth('keep_both', '两份都保留（文件名加 (1)(2)）');

  const ConflictStrategy(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ConflictStrategy fromWire(String? value) => switch (value) {
    'skip' => ConflictStrategy.skip,
    'overwrite' => ConflictStrategy.overwrite,
    'keep_both' => ConflictStrategy.keepBoth,
    _ => throw const ProtocolCompatibilityException('conflict_strategy', '必须是 birdbox-copy-v1 冲突策略'),
  };
}

/// 审阅信息导出（主协议 §9.1）。
///
/// `enabled=true` 时 v1 要求 `writeXmp` 与 `writeCsv` 同时为 true；
/// `enabled=false` 时其余字段必须为 false。
class ReviewExportConfig {
  const ReviewExportConfig({
    required this.enabled,
    this.writeXmp = true,
    this.writeCsv = true,
    this.embedIntoSupportedCopy = true,
  });

  const ReviewExportConfig.disabled()
    : enabled = false,
      writeXmp = false,
      writeCsv = false,
      embedIntoSupportedCopy = false;

  final bool enabled;
  final bool writeXmp;
  final bool writeCsv;
  final bool embedIntoSupportedCopy;

  factory ReviewExportConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw const ProtocolCompatibilityException('review_export', '不能为空');
    }
    final enabled = json['enabled'];
    if (enabled is! bool) {
      throw const ProtocolCompatibilityException('review_export.enabled', '必须是布尔值');
    }
    if (!enabled) {
      return const ReviewExportConfig.disabled();
    }
    return ReviewExportConfig(
      enabled: true,
      writeXmp: json['write_xmp'] as bool? ?? true,
      writeCsv: json['write_csv'] as bool? ?? true,
      embedIntoSupportedCopy: json['embed_into_supported_copy'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'write_xmp': writeXmp,
    'write_csv': writeCsv,
    'embed_into_supported_copy': embedIntoSupportedCopy,
  };
}

/// 存储设备展示模型（主协议 §4.1）。
///
/// 仅包含协议字段；`media_id` 是唯一稳定身份，禁止展示 Linux 路径。
class StorageDeviceSummary {
  const StorageDeviceSummary({
    required this.mediaId,
    required this.displayName,
    required this.kind,
    required this.kindConfidence,
    required this.detail,
    required this.capacityBytes,
    required this.freeBytes,
    required this.filesystem,
    required this.label,
    required this.roleState,
    required this.canBeSource,
    required this.canBeTarget,
    required this.targetBlockReasons,
    required this.identityConfidence,
    this.lastSeenAt,
    this.userAlias,
  });

  final String mediaId;
  final String displayName;

  /// `memory_card` / `card_reader` / `usb_flash` / `usb_storage` /
  /// `external_hdd` / `external_ssd` / `removable_storage` / `unknown`。
  final String kind;

  /// `high` / `medium` / `low` / `unknown`。
  final String kindConfidence;

  /// 厂商/型号 · 容量 · 文件系统 等展示信息。
  final String detail;
  final int capacityBytes;
  final int freeBytes;
  final String filesystem;
  final String label;
  final String roleState;
  final bool canBeSource;
  final bool canBeTarget;
  final List<String> targetBlockReasons;

  /// `stable_uuid` / `degraded`（§3.1 无 UUID 降级指纹）。
  final String identityConfidence;
  final DateTime? lastSeenAt;
  final String? userAlias;

  bool get online => roleState != 'removed' && roleState != 'unavailable';
  bool get identityStable => identityConfidence == 'stable_uuid';

  /// 展示名优先级：用户别名 > 服务端 display_name（§4.2 第 1 条）。
  String get presentationName {
    final alias = userAlias?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final name = displayName.trim();
    return name.isEmpty ? _kindLabel : name;
  }

  String get _kindLabel => switch (kind) {
    'memory_card' => '存储卡',
    'card_reader' => '读卡器',
    'usb_flash' => 'U 盘',
    'usb_storage' => 'USB 存储',
    'external_hdd' => '移动硬盘',
    'external_ssd' => '移动固态硬盘',
    'removable_storage' => '可移动存储',
    _ => 'USB 存储设备（类型未确认）',
  };

  factory StorageDeviceSummary.fromJson(Map<String, dynamic> json) {
    final kind = ProtocolValidation.requiredId(json, 'kind');
    if (!const {
      'memory_card',
      'card_reader',
      'usb_flash',
      'usb_storage',
      'external_hdd',
      'external_ssd',
      'removable_storage',
      'unknown',
    }.contains(kind)) {
      throw const ProtocolCompatibilityException('kind', '不是 birdbox-copy-v1 设备类型');
    }
    final roleState = ProtocolValidation.requiredId(json, 'role_state');
    if (roleState != 'available' && roleState != 'removed' && roleState != 'unavailable') {
      throw const ProtocolCompatibilityException('role_state', '不是 birdbox-copy-v1 设备角色状态');
    }
    return StorageDeviceSummary(
      mediaId: ProtocolValidation.requiredId(json, 'media_id'),
      displayName: ProtocolValidation.requiredId(json, 'display_name'),
      kind: kind,
      kindConfidence: ProtocolValidation.requiredId(json, 'kind_confidence'),
      detail: json['detail']?.toString() ?? '',
      capacityBytes: _requiredNonNegativeInt(json, 'capacity_bytes'),
      freeBytes: _requiredNonNegativeInt(json, 'free_bytes'),
      filesystem: json['filesystem']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      roleState: roleState,
      canBeSource: _requiredBool(json, 'can_be_source'),
      canBeTarget: _requiredBool(json, 'can_be_target'),
      targetBlockReasons: _stringList(json, 'target_block_reasons'),
      identityConfidence: ProtocolValidation.requiredId(json, 'identity_confidence'),
      lastSeenAt: ProtocolValidation.optionalDateTime(json, 'last_seen_at'),
      userAlias: json['user_alias']?.toString(),
    );
  }
}

/// 不可变选择快照（主协议 §3 / §13.3）。
class CopySelectionSnapshot {
  const CopySelectionSnapshot({
    required this.selectionId,
    required this.assetCount,
    this.createdAt,
  });

  final String selectionId;
  final int assetCount;
  final DateTime? createdAt;

  factory CopySelectionSnapshot.fromJson(Map<String, dynamic> json) =>
      CopySelectionSnapshot(
        selectionId: ProtocolValidation.requiredId(json, 'selection_id'),
        assetCount: _requiredNonNegativeInt(json, 'asset_count'),
        createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      );
}

/// 复制预检结果（主协议 §10.1）。
class CopyPreview {
  const CopyPreview({
    required this.previewToken,
    required this.expiresAt,
    required this.source,
    required this.target,
    required this.logicalPhotoCount,
    required this.actualFileCount,
    required this.totalBytes,
    required this.rawCount,
    required this.jpegCount,
    required this.videoCount,
    required this.companionCount,
    required this.estimatedDateDirectories,
    required this.conflictCount,
    required this.targetFreeBytes,
    required this.safetyReserveBytes,
    this.unsupportedCount = 0,
    this.missingCount = 0,
    this.permissionErrorCount = 0,
  });

  final String previewToken;
  final DateTime expiresAt;
  final StorageDeviceSummary source;
  final StorageDeviceSummary target;

  /// 逻辑照片数（RAW+JPEG 视为一个）。
  final int logicalPhotoCount;

  /// 实际文件数。
  final int actualFileCount;
  final int totalBytes;

  /// RAW/JPEG/视频/伴随文件分类统计。
  final int rawCount;
  final int jpegCount;
  final int videoCount;
  final int companionCount;
  final int estimatedDateDirectories;
  final int conflictCount;

  /// 目标可用空间与安全余量（至少 5% 或配置下限，§10.1）。
  final int targetFreeBytes;
  final int safetyReserveBytes;
  final int unsupportedCount;
  final int missingCount;
  final int permissionErrorCount;

  bool get hasEnoughSpace => targetFreeBytes - safetyReserveBytes >= totalBytes;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory CopyPreview.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source'];
    final rawTarget = json['target'];
    if (rawSource is! Map || rawTarget is! Map) {
      throw const ProtocolCompatibilityException(
        'source/target',
        '必须包含源与目标设备快照',
      );
    }
    return CopyPreview(
      previewToken: ProtocolValidation.requiredId(json, 'preview_token'),
      expiresAt: _requiredDateTime(json, 'expires_at'),
      source: StorageDeviceSummary.fromJson(Map<String, dynamic>.from(rawSource)),
      target: StorageDeviceSummary.fromJson(Map<String, dynamic>.from(rawTarget)),
      logicalPhotoCount: _requiredNonNegativeInt(json, 'logical_photo_count'),
      actualFileCount: _requiredNonNegativeInt(json, 'actual_file_count'),
      totalBytes: _requiredNonNegativeInt(json, 'total_bytes'),
      rawCount: _requiredNonNegativeInt(json, 'raw_count'),
      jpegCount: _requiredNonNegativeInt(json, 'jpeg_count'),
      videoCount: _requiredNonNegativeInt(json, 'video_count'),
      companionCount: _requiredNonNegativeInt(json, 'companion_count'),
      estimatedDateDirectories: _requiredNonNegativeInt(json, 'estimated_date_directories'),
      conflictCount: _requiredNonNegativeInt(json, 'conflict_count'),
      targetFreeBytes: _requiredNonNegativeInt(json, 'target_free_bytes'),
      safetyReserveBytes: _requiredNonNegativeInt(json, 'safety_reserve_bytes'),
      unsupportedCount: ProtocolValidation.nonNegativeInt(json, 'unsupported_count'),
      missingCount: ProtocolValidation.nonNegativeInt(json, 'missing_count'),
      permissionErrorCount: ProtocolValidation.nonNegativeInt(json, 'permission_error_count'),
    );
  }
}

/// 复制任务创建请求草稿（主协议 §13.4 预检请求体）。
///
/// `conflictStrategy` 无默认值；未选择时禁止创建任务（§8）。
class CopyRequestDraft {
  const CopyRequestDraft({
    required this.scope,
    required this.sourceMediaId,
    required this.targetMediaId,
    required this.reviewExport,
    this.batchId,
    this.selectionId,
    this.pairPolicy = PairPolicy.rawOnly,
    this.conflictStrategy,
  });

  final String? batchId;
  final CopyScope scope;
  final String? selectionId;
  final String sourceMediaId;
  final String targetMediaId;
  final PairPolicy pairPolicy;
  final ConflictStrategy? conflictStrategy;
  final ReviewExportConfig reviewExport;

  CopyRequestDraft copyWith({
    String? batchId,
    CopyScope? scope,
    String? selectionId,
    String? sourceMediaId,
    String? targetMediaId,
    PairPolicy? pairPolicy,
    ConflictStrategy? conflictStrategy,
    ReviewExportConfig? reviewExport,
    bool clearSelectionId = false,
  }) => CopyRequestDraft(
    batchId: batchId ?? this.batchId,
    scope: scope ?? this.scope,
    selectionId: clearSelectionId ? null : selectionId ?? this.selectionId,
    sourceMediaId: sourceMediaId ?? this.sourceMediaId,
    targetMediaId: targetMediaId ?? this.targetMediaId,
    pairPolicy: pairPolicy ?? this.pairPolicy,
    conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    reviewExport: reviewExport ?? this.reviewExport,
  );

  /// 预检请求体（§13.4）。`batchId` 在全量备份时可省略。
  Map<String, dynamic> toJson() => {
    if (batchId != null && batchId!.trim().isNotEmpty) 'batch_id': batchId!.trim(),
    'source_media_id': sourceMediaId,
    'target_media_id': targetMediaId,
    'scope': scope.wireValue,
    if (selectionId != null && selectionId!.trim().isNotEmpty) 'selection_id': selectionId!.trim(),
    'pair_policy': pairPolicy.wireValue,
    'conflict_strategy': conflictStrategy?.wireValue,
    'review_export': reviewExport.toJson(),
  };
}

/// 复制任务摘要（§13.5 创建响应）。完整状态机与事件流在联调阶段接入。
class CopyJobSummary {
  const CopyJobSummary({
    required this.copyJobId,
    required this.state,
    required this.eventSeq,
    this.createdAt,
  });

  final String copyJobId;
  final String state;
  final int eventSeq;
  final DateTime? createdAt;

  factory CopyJobSummary.fromJson(Map<String, dynamic> json) => CopyJobSummary(
    copyJobId: ProtocolValidation.requiredId(json, 'copy_job_id'),
    state: ProtocolValidation.requiredId(json, 'state'),
    eventSeq: ProtocolValidation.nonNegativeInt(json, 'event_seq'),
    createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
  );
}

/// 同批次上次成功目标设备（§4.4）。仅作为可修改的预选，不是全局默认盘。
class BatchTargetPreference {
  const BatchTargetPreference({
    required this.batchId,
    required this.lastSuccessfulTargetMediaId,
    this.updatedAt,
  });

  final String batchId;
  final String lastSuccessfulTargetMediaId;
  final DateTime? updatedAt;

  factory BatchTargetPreference.fromJson(Map<String, dynamic> json) =>
      BatchTargetPreference(
        batchId: ProtocolValidation.requiredId(json, 'batch_id'),
        lastSuccessfulTargetMediaId: ProtocolValidation.requiredId(
          json,
          'last_successful_target_media_id',
        ),
        updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
      );
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw ProtocolCompatibilityException(key, '不能为空');
  }
  return ProtocolValidation.nonNegativeInt(json, key);
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! bool) {
    throw ProtocolCompatibilityException(key, '必须是布尔值');
  }
  return raw;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
  if (parsed == null) {
    throw ProtocolCompatibilityException(key, '必须是 ISO-8601 时间');
  }
  return parsed;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! List) {
    throw ProtocolCompatibilityException(key, '必须是字符串列表');
  }
  return List.unmodifiable(
    raw.map((value) => value.toString()).where((value) => value.isNotEmpty),
  );
}
