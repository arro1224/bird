/// RC3 任务闭环响应模型（birdbox-copy-v1 §12/§13.5/§13.6）。
///
/// 与 `copy_models.dart` 的发送端严格解析相反，本文件全部为**容错解析**：
/// 响应协议尚未冻结（联调期后端 OpenAPI 可能增改字段），因此约定：
/// - 未知字段一律忽略；
/// - 缺失字段给默认值（绝不抛 `ProtocolCompatibilityException`，
///   仅 `CopyJobDetail.copyJobId` 等无法降级的身份字段除外）；
/// - 未知枚举保留原始 wire 值展示，不崩溃；`allowed_actions`
///   中的未知动作直接丢弃（迁移对照 §3.5：只渲染可识别的按钮）。
///
/// 能力声明模型（CopyCapabilities）沿用 copy_models.dart 的 rc3 严格版本。
library;

import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';

/// 复制任务状态机（§12）。常量类而非 enum：未知 wire 值保留原始字符串。
class CopyJobState {
  const CopyJobState._(this.wire, this.label, {required this.isTerminal})
    : isCustom = false;

  const CopyJobState._custom(String raw)
    : wire = raw,
      label = raw,
      isTerminal = false,
      isCustom = true;

  static const draft = CopyJobState._('draft', '已创建', isTerminal: false);
  static const preflighted = CopyJobState._(
    'preflighted',
    '预检完成',
    isTerminal: false,
  );
  static const queued = CopyJobState._('queued', '排队中', isTerminal: false);
  static const acquiringTarget = CopyJobState._(
    'acquiring_target',
    '正在获取目标盘',
    isTerminal: false,
  );
  static const running = CopyJobState._('running', '复制中', isTerminal: false);
  static const pauseRequested = CopyJobState._(
    'pause_requested',
    '正在暂停',
    isTerminal: false,
  );
  static const paused = CopyJobState._('paused', '已暂停', isTerminal: false);
  static const cancelRequested = CopyJobState._(
    'cancel_requested',
    '正在取消',
    isTerminal: false,
  );
  static const cancelled = CopyJobState._('cancelled', '已取消', isTerminal: true);
  static const waitingForSource = CopyJobState._(
    'waiting_for_source',
    '等待相机卡',
    isTerminal: false,
  );
  static const waitingForTarget = CopyJobState._(
    'waiting_for_target',
    '等待目标设备',
    isTerminal: false,
  );
  static const completed = CopyJobState._('completed', '已完成', isTerminal: true);
  static const completedWithErrors = CopyJobState._(
    'completed_with_errors',
    '部分完成',
    isTerminal: true,
  );
  static const failed = CopyJobState._('failed', '失败', isTerminal: true);

  /// 解析失败（null/空）时的兜底；未知 wire 值走 `_custom` 保留原文。
  static const unknown = CopyJobState._('unknown', '未知状态', isTerminal: false);

  final String wire;
  final String label;
  final bool isTerminal;
  final bool isCustom;

  /// 文件仍在推进（含暂停/取消过渡期：当前文件完成后才停）。
  bool get isRunning => switch (wire) {
    'running' || 'acquiring_target' || 'pause_requested' || 'cancel_requested' => true,
    _ => false,
  };

  bool get isWaitingDevice => switch (wire) {
    'waiting_for_source' || 'waiting_for_target' => true,
    _ => false,
  };

  bool get isTransition => switch (wire) {
    'pause_requested' || 'cancel_requested' => true,
    _ => false,
  };

  static CopyJobState fromWire(String? raw) {
    if (raw == null || raw.trim().isEmpty) return unknown;
    return switch (raw.trim()) {
      'draft' => draft,
      'preflighted' => preflighted,
      'queued' => queued,
      'acquiring_target' => acquiringTarget,
      'running' => running,
      'pause_requested' => pauseRequested,
      'paused' => paused,
      'cancel_requested' => cancelRequested,
      'cancelled' => cancelled,
      'waiting_for_source' => waitingForSource,
      'waiting_for_target' => waitingForTarget,
      'completed' => completed,
      'completed_with_errors' => completedWithErrors,
      'failed' => failed,
      _ => CopyJobState._custom(raw.trim()),
    };
  }

  @override
  bool operator ==(Object other) => other is CopyJobState && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// 文件项状态（§12）。与 `CopyJobState` 同样容错：未知值保留原文。
class CopyItemState {
  const CopyItemState._(this.wire, this.label);

  const CopyItemState._custom(String raw)
    : wire = raw,
      label = raw;

  static const pending = CopyItemState._('pending', '待复制');
  static const copying = CopyItemState._('copying', '复制中');
  static const verifying = CopyItemState._('verifying', '校验中');
  static const copied = CopyItemState._('copied', '已复制');
  static const failed = CopyItemState._('failed', '失败');
  static const skippedConflict = CopyItemState._('skipped_conflict', '同名跳过');
  static const notApplicable = CopyItemState._('not_applicable', '不适用');

  final String wire;
  final String label;

  static CopyItemState fromWire(String? raw) {
    if (raw == null || raw.trim().isEmpty) return pending;
    return switch (raw.trim()) {
      'pending' => pending,
      'copying' => copying,
      'verifying' => verifying,
      'copied' => copied,
      'failed' => failed,
      'skipped_conflict' => skippedConflict,
      'not_applicable' => notApplicable,
      _ => CopyItemState._custom(raw.trim()),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is CopyItemState && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// 任务详情允许的动作（迁移对照 §3.5）。未知名直接丢弃。
class CopyAllowedAction {
  const CopyAllowedAction._(this.wire, this.label);

  static const pause = CopyAllowedAction._('pause', '暂停');
  static const resume = CopyAllowedAction._('resume', '继续');
  static const cancel = CopyAllowedAction._('cancel', '取消任务');
  static const retryFailed = CopyAllowedAction._('retry_failed', '重试失败项');
  static const safeRemoveSource = CopyAllowedAction._(
    'safe_remove_source',
    '安全移除源设备',
  );
  static const safeRemoveTarget = CopyAllowedAction._(
    'safe_remove_target',
    '安全移除目标设备',
  );

  static const values = [
    pause,
    resume,
    cancel,
    retryFailed,
    safeRemoveSource,
    safeRemoveTarget,
  ];

  final String wire;
  final String label;

  static CopyAllowedAction? fromWire(String? raw) {
    if (raw == null) return null;
    return switch (raw.trim()) {
      'pause' => pause,
      'resume' => resume,
      'cancel' => cancel,
      'retry_failed' => retryFailed,
      'safe_remove_source' => safeRemoveSource,
      'safe_remove_target' => safeRemoveTarget,
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is CopyAllowedAction && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;
}

/// 任务进度统计（§13.5）。全部数值缺失给 0/null，不做格式校验。
class CopyJobStats {
  const CopyJobStats({
    required this.totalFiles,
    required this.copiedFiles,
    required this.failedFiles,
    required this.skippedFiles,
    required this.notApplicableFiles,
    required this.totalBytes,
    required this.copiedBytes,
    this.elapsedSeconds,
    this.etaSeconds,
    this.bytesPerSecond,
    this.currentFile,
    this.progressPercent,
  });

  final int totalFiles;
  final int copiedFiles;
  final int failedFiles;
  final int skippedFiles;
  final int notApplicableFiles;
  final int totalBytes;
  final int copiedBytes;
  final int? elapsedSeconds;
  final int? etaSeconds;
  final int? bytesPerSecond;
  final String? currentFile;

  /// 后端 P1-5 反馈当前为假值：UI 对 0/null 必须不渲染进度卡。
  final double? progressPercent;

  factory CopyJobStats.fromJson(Map<String, dynamic> json) => CopyJobStats(
    totalFiles: _int(json, 'total_files') ?? 0,
    copiedFiles: _int(json, 'copied_files') ?? 0,
    failedFiles: _int(json, 'failed_files') ?? 0,
    skippedFiles: _int(json, 'skipped_files') ?? 0,
    notApplicableFiles: _int(json, 'not_applicable_files') ?? 0,
    totalBytes: _int(json, 'total_bytes') ?? 0,
    copiedBytes: _int(json, 'copied_bytes') ?? 0,
    elapsedSeconds: _int(json, 'elapsed_seconds'),
    etaSeconds: _int(json, 'eta_seconds'),
    bytesPerSecond: _int(json, 'bytes_per_second'),
    currentFile: json['current_file']?.toString(),
    progressPercent: _progressPercent(json['progress_percent']),
  );

  /// 无显式进度时按文件数推导（copied/total）；两者皆无则 null。
  double? get effectiveProgressPercent {
    final explicit = progressPercent;
    if (explicit != null) return explicit;
    if (totalFiles <= 0) return null;
    return (copiedFiles / totalFiles).clamp(0.0, 1.0);
  }
}

/// 任务详情中的设备展示快照（§13.5）。
///
/// 响应字段未冻结，全部 nullable；**不得复用** `StorageDeviceSummary.fromJson`
/// （发送端严格模型，联调期会崩）。
class CopyJobDeviceSnapshot {
  const CopyJobDeviceSnapshot({
    this.mediaId,
    this.displayName,
    this.kind,
    this.userAlias,
  });

  final String? mediaId;
  final String? displayName;
  final String? kind;
  final String? userAlias;

  String? get presentationLabel {
    final alias = userAlias?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return mediaId;
  }

  factory CopyJobDeviceSnapshot.fromJson(Map<String, dynamic> json) =>
      CopyJobDeviceSnapshot(
        mediaId: _string(json, 'media_id'),
        displayName: _string(json, 'display_name'),
        kind: _string(json, 'kind'),
        userAlias: _string(json, 'user_alias'),
      );
}

/// 复制任务详情（§13.5）。
class CopyJobDetail {
  const CopyJobDetail({
    required this.copyJobId,
    required this.state,
    required this.stateVersion,
    required this.eventSeq,
    required this.allowedActions,
    this.stats,
    this.sourceDevice,
    this.targetDevice,
    this.scopeWire,
    this.batchId,
    this.selectionId,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  /// 唯一必填字段：没有任务 id 时该响应不可用，直接抛协议异常。
  final String copyJobId;
  final CopyJobState state;

  /// 依次尝试 state_version / expected_state_version / version，缺省 0。
  final int stateVersion;
  final int eventSeq;
  final CopyJobStats? stats;
  final CopyJobDeviceSnapshot? sourceDevice;
  final CopyJobDeviceSnapshot? targetDevice;

  /// 只渲染后端返回的可识别动作（未知动作解析时已丢弃）。
  final List<CopyAllowedAction> allowedActions;
  final String? scopeWire;
  final String? batchId;
  final String? selectionId;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isFullBackup => scopeWire == 'media_full_backup';

  factory CopyJobDetail.fromJson(Map<String, dynamic> json) {
    final rawState = json['state'];
    if (rawState == null) {
      throw const ProtocolCompatibilityException('state', '不能为空');
    }
    final rawStats = json['stats'];
    final rawSource = json['source_device'];
    final rawTarget = json['target_device'];
    final rawActions = json['allowed_actions'];
    return CopyJobDetail(
      copyJobId: ProtocolValidation.requiredId(json, 'copy_job_id'),
      state: CopyJobState.fromWire(rawState?.toString()),
      stateVersion:
          _int(json, 'state_version') ??
          _int(json, 'expected_state_version') ??
          _int(json, 'version') ??
          0,
      eventSeq: _int(json, 'event_seq') ?? 0,
      stats: rawStats is Map
          ? CopyJobStats.fromJson(Map<String, dynamic>.from(rawStats))
          : null,
      sourceDevice: rawSource is Map
          ? CopyJobDeviceSnapshot.fromJson(Map<String, dynamic>.from(rawSource))
          : null,
      targetDevice: rawTarget is Map
          ? CopyJobDeviceSnapshot.fromJson(Map<String, dynamic>.from(rawTarget))
          : null,
      allowedActions: (rawActions is List ? rawActions : const [])
          .map((action) => CopyAllowedAction.fromWire(action?.toString()))
          .whereType<CopyAllowedAction>()
          .toList(growable: false),
      scopeWire: _string(json, 'scope'),
      batchId: _string(json, 'batch_id'),
      selectionId: _string(json, 'selection_id'),
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      startedAt: ProtocolValidation.optionalDateTime(json, 'started_at'),
      finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
    );
  }
}

/// 任务列表行（列表端点契约未冻结：仅要求 copy_job_id，其余容错）。
class CopyJobListItem {
  const CopyJobListItem({
    required this.copyJobId,
    required this.state,
    this.scopeWire,
    this.stats,
    this.createdAt,
  });

  final String copyJobId;
  final CopyJobState state;
  final String? scopeWire;
  final CopyJobStats? stats;
  final DateTime? createdAt;

  bool get isFullBackup => scopeWire == 'media_full_backup';

  factory CopyJobListItem.fromJson(Map<String, dynamic> json) {
    final rawStats = json['stats'];
    return CopyJobListItem(
      copyJobId: ProtocolValidation.requiredId(json, 'copy_job_id'),
      state: CopyJobState.fromWire(json['state']?.toString()),
      scopeWire: _string(json, 'scope'),
      stats: rawStats is Map
          ? CopyJobStats.fromJson(Map<String, dynamic>.from(rawStats))
          : null,
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
    );
  }
}

/// 文件项（§10.2）。任务详情失败项与预检明细复用同一模型。
class CopyJobItem {
  const CopyJobItem({
    required this.copyItemId,
    this.assetId,
    this.sourceMediaId,
    this.sourceRelativePath,
    this.sourceSize,
    this.sourceMtimeNs,
    this.targetRelativeDirectory,
    this.targetFilename,
    this.state = CopyItemState.pending,
    this.conflictDecision,
  });

  /// copy_item_id | item_id | id 三键容错（未冻结）。
  final String copyItemId;
  final String? assetId;
  final String? sourceMediaId;
  final String? sourceRelativePath;
  final int? sourceSize;
  final int? sourceMtimeNs;
  final String? targetRelativeDirectory;
  final String? targetFilename;
  final CopyItemState state;

  /// 预检明细：skip / overwrite / keep_both；任务项可能缺失。
  final String? conflictDecision;

  String? get targetPath {
    final dir = targetRelativeDirectory?.trim();
    final file = targetFilename?.trim();
    if (dir == null || dir.isEmpty) return (file == null || file.isEmpty) ? null : file;
    if (file == null || file.isEmpty) return dir;
    return '$dir/$file';
  }

  factory CopyJobItem.fromJson(Map<String, dynamic> json) {
    final rawId =
        _string(json, 'copy_item_id') ??
        _string(json, 'item_id') ??
        _string(json, 'id');
    if (rawId == null || rawId.isEmpty) {
      throw const ProtocolCompatibilityException('copy_item_id', '不能为空');
    }
    return CopyJobItem(
      copyItemId: rawId,
      assetId: _string(json, 'asset_id'),
      sourceMediaId: _string(json, 'source_media_id'),
      sourceRelativePath: _string(json, 'source_relative_path'),
      sourceSize: _int(json, 'source_size'),
      sourceMtimeNs: _int(json, 'source_mtime_ns'),
      targetRelativeDirectory: _string(json, 'target_relative_directory'),
      targetFilename: _string(json, 'target_filename'),
      state: CopyItemState.fromWire(json['state']?.toString()),
      conflictDecision: _string(json, 'conflict_decision'),
    );
  }
}

/// 分页容器基形：{items, has_more, next_cursor}。
/// next_cursor 兼容 int/String；has_more 缺失时以 next_cursor 是否存在推断。
class _PageFields {
  const _PageFields({required this.hasMore, this.nextCursor});

  final bool hasMore;
  final String? nextCursor;

  factory _PageFields.fromJson(Map<String, dynamic> json) {
    final cursor =
        _string(json, 'next_cursor') ?? _string(json, 'next_after_seq');
    final rawHasMore = json['has_more'];
    final hasMore = rawHasMore is bool ? rawHasMore : cursor != null;
    return _PageFields(hasMore: hasMore, nextCursor: cursor);
  }
}

/// 文件明细分页。
class CopyJobItemPage {
  const CopyJobItemPage({required this.items, required this.hasMore, this.nextCursor});

  final List<CopyJobItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory CopyJobItemPage.fromJson(Map<String, dynamic> json) {
    final page = _PageFields.fromJson(json);
    final rawItems = json['items'];
    return CopyJobItemPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => CopyJobItem.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }
}

/// 任务列表分页。
class CopyJobPage {
  const CopyJobPage({required this.items, required this.hasMore, this.nextCursor});

  final List<CopyJobListItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory CopyJobPage.fromJson(Map<String, dynamic> json) {
    final page = _PageFields.fromJson(json);
    final rawItems = json['items'];
    return CopyJobPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    CopyJobListItem.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
          : const [],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }
}

/// 任务事件（§13.5 events）。seq 兼容 seq | event_seq。
class CopyJobEvent {
  const CopyJobEvent({
    required this.seq,
    this.type,
    this.message,
    this.createdAt,
  });

  final int? seq;
  final String? type;
  final String? message;
  final DateTime? createdAt;

  factory CopyJobEvent.fromJson(Map<String, dynamic> json) => CopyJobEvent(
    seq: _int(json, 'seq') ?? _int(json, 'event_seq'),
    type: _string(json, 'type'),
    message: _string(json, 'message'),
    createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
  );
}

/// 事件分页。
class CopyJobEventPage {
  const CopyJobEventPage({required this.events, required this.hasMore, this.nextCursor});

  final List<CopyJobEvent> events;
  final bool hasMore;
  final String? nextCursor;

  factory CopyJobEventPage.fromJson(Map<String, dynamic> json) {
    final page = _PageFields.fromJson(json);
    final rawEvents = json['events'];
    return CopyJobEventPage(
      events: rawEvents is List
          ? rawEvents
              .whereType<Map>()
              .map(
                (event) => CopyJobEvent.fromJson(Map<String, dynamic>.from(event)),
              )
              .toList(growable: false)
          : const [],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );
  }
}

/// 任务结果报告（迁移对照 §3.6，字段全 optional）。
class CopyReport {
  const CopyReport({
    this.copyJobId,
    this.selectionId,
    this.reviewSnapshotId,
    this.logicalPhotoCount,
    this.actualFileCount,
    this.copiedFiles,
    this.failedFiles,
    this.skippedFiles,
    this.notApplicableFiles,
    this.rawCount,
    this.jpegCount,
    this.videoCount,
    this.companionCount,
    this.totalBytes,
    this.elapsedSeconds,
    this.bytesPerSecond,
    this.xmpCount,
    this.csvStatus,
    this.embedSuccessCount,
    this.embedDegradedCount,
    this.sourceDevice,
    this.targetDevice,
    this.generatedAt,
  });

  final String? copyJobId;
  final String? selectionId;
  final String? reviewSnapshotId;
  final int? logicalPhotoCount;
  final int? actualFileCount;
  final int? copiedFiles;
  final int? failedFiles;
  final int? skippedFiles;
  final int? notApplicableFiles;
  final int? rawCount;
  final int? jpegCount;
  final int? videoCount;
  final int? companionCount;
  final int? totalBytes;
  final int? elapsedSeconds;
  final int? bytesPerSecond;
  final int? xmpCount;

  /// csv 导出状态 wire 值（success/failed/...，未冻结）。
  final String? csvStatus;
  final int? embedSuccessCount;
  final int? embedDegradedCount;
  final CopyJobDeviceSnapshot? sourceDevice;
  final CopyJobDeviceSnapshot? targetDevice;
  final DateTime? generatedAt;

  /// “部分成功不得显示成成功”：只要有失败项即按部分完成渲染。
  bool get isPartialSuccess => (failedFiles ?? 0) > 0;

  factory CopyReport.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source_device'];
    final rawTarget = json['target_device'];
    return CopyReport(
      copyJobId: _string(json, 'copy_job_id'),
      selectionId: _string(json, 'selection_id'),
      reviewSnapshotId: _string(json, 'review_snapshot_id'),
      logicalPhotoCount: _int(json, 'logical_photo_count'),
      actualFileCount: _int(json, 'actual_file_count'),
      copiedFiles: _int(json, 'copied_files'),
      failedFiles: _int(json, 'failed_files'),
      skippedFiles: _int(json, 'skipped_files'),
      notApplicableFiles: _int(json, 'not_applicable_files'),
      rawCount: _int(json, 'raw_count'),
      jpegCount: _int(json, 'jpeg_count'),
      videoCount: _int(json, 'video_count'),
      companionCount: _int(json, 'companion_count'),
      totalBytes: _int(json, 'total_bytes'),
      elapsedSeconds: _int(json, 'elapsed_seconds'),
      bytesPerSecond: _int(json, 'bytes_per_second'),
      xmpCount: _int(json, 'xmp_count'),
      csvStatus: _string(json, 'csv_status'),
      embedSuccessCount: _int(json, 'embed_success_count'),
      embedDegradedCount: _int(json, 'embed_degraded_count'),
      sourceDevice: rawSource is Map
          ? CopyJobDeviceSnapshot.fromJson(Map<String, dynamic>.from(rawSource))
          : null,
      targetDevice: rawTarget is Map
          ? CopyJobDeviceSnapshot.fromJson(Map<String, dynamic>.from(rawTarget))
          : null,
      generatedAt: ProtocolValidation.optionalDateTime(json, 'generated_at'),
    );
  }
}

/// 安全移除结果（§13.6/§4.5）。safe_to_remove 缺失按 false（保守）。
class SafeRemoveResult {
  const SafeRemoveResult({
    required this.safeToRemove,
    this.reason,
    this.keepUntil,
  });

  final bool safeToRemove;
  final String? reason;
  final DateTime? keepUntil;

  factory SafeRemoveResult.fromJson(Map<String, dynamic> json) => SafeRemoveResult(
    safeToRemove: _bool(json, 'safe_to_remove', fallback: false),
    reason: _string(json, 'reason'),
    keepUntil: ProtocolValidation.optionalDateTime(json, 'keep_until'),
  );
}

/// 设备列表响应：行仍走严格 `StorageDeviceSummary.fromJson`；
/// 顶层推荐目标键容错 last_successful_target_media_id |
/// recommended_target_media_id（覆盖审计 P1-3）。
class CopyDeviceList {
  const CopyDeviceList({required this.devices, this.recommendedTargetMediaId});

  final List<StorageDeviceSummary> devices;
  final String? recommendedTargetMediaId;

  factory CopyDeviceList.fromJson(Map<String, dynamic> json) {
    final rawDevices = json['devices'];
    final recommended =
        _string(json, 'last_successful_target_media_id') ??
        _string(json, 'recommended_target_media_id');
    return CopyDeviceList(
      devices: rawDevices is List
          ? rawDevices
              .whereType<Map>()
              .map(
                (device) => StorageDeviceSummary.fromJson(
                  Map<String, dynamic>.from(device),
                ),
              )
              .toList(growable: false)
          : const [],
      recommendedTargetMediaId: recommended,
    );
  }
}

// ---- 容错解析 helpers：非法值一律回退默认，不抛异常 ----

String? _string(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

int? _int(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is num && raw.isFinite) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

bool _bool(Map<String, dynamic> json, String key, {required bool fallback}) {
  final raw = json[key];
  if (raw is bool) return raw;
  if (raw is String) return raw.trim() == 'true';
  return fallback;
}

double? _progressPercent(Object? raw) {
  if (raw is! num || !raw.isFinite || raw < 0) return null;
  // 0..1 视为比例，>1 视为百分数（契约未冻结，两形态都接受）。
  if (raw <= 1) return raw.toDouble();
  return (raw / 100).clamp(0.0, 1.0).toDouble();
}
