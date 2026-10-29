/// SmartFollow 边识别边复制：App 侧冻结契约（状态、动作、会话、子任务、能力）。
///
/// 依据 `doc/任务/BirdBox_SmartFollow_App与后端联合开发资料包_202610/`
/// 联合开发任务书 §4（会话状态九值）、§5（动作）、§6.1（capability）、
/// §6.5（会话字段）、§6.6/§6.7（子任务与动作），以及 App 修改任务书 §3
/// （eligibility 只认后端结论）。
///
/// 三条硬规则（评审时逐条看）：
/// 1. 计数一律取后端字段，App 不做 "+1"，事件只触发重读；
/// 2. 未知 `state`/`action` 原样保留并降级展示，不抛异常、不猜；
/// 3. `allowed_actions` 是唯一按钮来源，页面不自造动作。
///
/// 字段命名仍有一处待后端确认：capability 里 `eligibility_mode` 与
/// `mode`/`policy_version` 三种写法并存（见分工任务书 §5 第 1 条）。
/// 本文件按"同时接受、只暴露一个字段"的方式解析，确认后删多余别名即可。
library;

import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';

/// 联合任务书 §4 冻结的 SmartFollowSession 状态。
///
/// 未冻结但后端可能返回的旧值（如 `recognition_interrupted`、
/// `reconciliation_error`、`resume_recognition` 之类）走 [_custom] 原样保留，
/// App 既不接受为九态之一，也不因此报错。
class SmartFollowState {
  const SmartFollowState._(this.wire, this.label, {required this.isTerminal}) : isUnknown = false;

  const SmartFollowState._custom(String raw) : wire = raw, label = raw, isTerminal = false, isUnknown = true;

  static const created = SmartFollowState._('created', '已创建', isTerminal: false);
  static const following = SmartFollowState._('following', '识别与复制中', isTerminal: false);
  static const paused = SmartFollowState._('paused', '已暂停', isTerminal: false);
  static const waitingForTarget = SmartFollowState._('waiting_for_target', '等待目标盘', isTerminal: false);
  static const waitingForSource = SmartFollowState._('waiting_for_source', '等待原相机卡', isTerminal: false);
  static const draining = SmartFollowState._('draining', '识别结束·正在完成剩余复制', isTerminal: false);
  static const completed = SmartFollowState._('completed', '已完成', isTerminal: true);
  static const completedPartial = SmartFollowState._('completed_partial', '部分完成', isTerminal: true);
  static const failed = SmartFollowState._('failed', '失败，需要处理', isTerminal: true);

  /// 缺字段/空串兜底；未知 wire 值走 [_custom]。
  static const unknown = SmartFollowState._('unknown', '状态未知', isTerminal: false);

  static const values = [created, following, paused, waitingForTarget, waitingForSource, draining, completed, completedPartial, failed];

  final String wire;
  final String label;
  final bool isTerminal;
  final bool isUnknown;

  /// 仍在跟随：识别可能继续产出新结果。
  bool get isFollowing => wire == 'following';

  /// 需要用户处理介质/错误，不是失败。
  bool get isWaiting => wire == 'waiting_for_target' || wire == 'waiting_for_source';

  /// 会话已收敛（含 part 与失败）。只有这三种可以显示完成页。
  bool get isFinished => isTerminal;

  static SmartFollowState fromWire(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return unknown;
    return switch (value) {
      'created' => created,
      'following' => following,
      'paused' => paused,
      'waiting_for_target' => waitingForTarget,
      'waiting_for_source' => waitingForSource,
      'draining' => draining,
      'completed' => completed,
      'completed_partial' => completedPartial,
      'failed' => failed,
      _ => SmartFollowState._custom(value),
    };
  }

  @override
  bool operator ==(Object other) => other is SmartFollowState && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'SmartFollowState($wire)';
}

/// 联合任务书 §5 的动作。未知值丢弃（页面不显示无法解释的按钮）。
///
/// 特别说明：旧代码里的 `resume_recognition` 不在 §5 列表内（那是识别任务
/// 自己的接口），未对账前不进本枚举（分工任务书 §5 第 3 条）。
class SmartFollowAction {
  const SmartFollowAction._(this.wire, this.label, {this.destructive = false});

  static const pause = SmartFollowAction._('pause', '暂停');
  static const resume = SmartFollowAction._('resume', '继续');
  static const finishCurrentResults = SmartFollowAction._('finish_current_results', '完成当前结果');
  static const stopFollowing = SmartFollowAction._('stop_following', '停止跟随', destructive: true);
  static const retry = SmartFollowAction._('retry', '重试失败项');

  static const values = [pause, resume, finishCurrentResults, stopFollowing, retry];

  final String wire;
  final String label;

  /// 需要二次确认，并明确告知"当前待复制照片将不再复制"。
  final bool destructive;

  static SmartFollowAction? fromWire(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return switch (value) {
      'pause' => pause,
      'resume' => resume,
      'finish_current_results' => finishCurrentResults,
      'stop_following' => stopFollowing,
      'retry' => retry,
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) => other is SmartFollowAction && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'SmartFollowAction($wire)';
}

/// 创建 SmartFollow 的 `smart_follow` 请求体（联合任务书 §6.2/§6.3）。
///
/// `source_session_id`/`manifest_revision` 由后端按 RecognitionJob 绑定
/// （RC3 增量 §2.2），App 不自己传；若后端要求额外字段，改这里并同步
/// 分工任务书 §5 第 5 条。
class SmartFollowStartRequest {
  const SmartFollowStartRequest({
    required this.targetMediaId,
    required this.reviewExportEnabled,
    this.preferEmbedded = true,
    this.eligibilityMode = SmartFollowContract.eligibilityMode,
    this.pairPolicy = 'raw_only',
    this.conflictStrategy = 'skip',
  });

  /// 目标存储设备的 `media_id`（唯一稳定身份，禁止传路径）。
  final String targetMediaId;

  /// 唯一用户开关：随副本保存识别与审阅信息。
  final bool reviewExportEnabled;

  /// 安全支持时优先内嵌；其余按 RC3 写 XMP/CSV。
  final bool preferEmbedded;

  final String eligibilityMode;

  /// `raw_only` / `jpeg_only` / `both`（RC3 wire 值，不新增枚举）。
  final String pairPolicy;

  /// `skip` / `overwrite` / `keep_both`（RC3 wire 值）。
  final String conflictStrategy;

  Map<String, dynamic> toJson() => {
    'target_media_id': targetMediaId,
    'eligibility_mode': eligibilityMode,
    'pair_policy': pairPolicy,
    'conflict_strategy': conflictStrategy,
    'review_export': {'enabled': reviewExportEnabled, 'prefer_embedded': preferEmbedded},
  };
}

abstract final class SmartFollowContract {
  /// 首版唯一策略：只复制 `high + top1_class 非空`（RC3 增量 §3）。
  static const eligibilityMode = 'recognized_only_v1';
  static const version = 'smart-follow-v1';
  static const metadataVersion = 'smart-follow-metadata-v1';
}

/// 创建请求结果未知：请求超时/连接中断，没有拿到会话，也没查回既有会话。
///
/// 联合 §6.3 + App 修改任务书 §5 末段要求"先查原请求/会话结果，不能直接换
/// key 重建"。因此这里不是普通失败：**用同一个请求键再调一次
/// `startOnRecognitionJob` 就是被认可的重试方式**（键由 job 派生、稳定不变）。
class SmartFollowOutcomeUnknown implements Exception {
  const SmartFollowOutcomeUnknown(this.recognitionJobId, this.cause);

  final String recognitionJobId;
  final Object cause;

  @override
  String toString() => 'SmartFollowOutcomeUnknown($recognitionJobId): $cause';
}

/// 会话快照（联合任务书 §6.5）。所有累计数字必须来自后端。
class SmartFollowSession {
  SmartFollowSession({
    required this.sessionId,
    required this.recognitionJobId,
    required this.state,
    required this.stateVersion,
    required this.recognizedCount,
    required this.eligibleCount,
    required this.pendingCount,
    required this.assignedCount,
    required this.copiedAssetCount,
    required this.copiedFileCount,
    required this.failedAssetCount,
    required this.childJobCount,
    required this.allowedActions,
    required this.metadataUpdateAvailable,
    this.eligibilityMode = SmartFollowContract.eligibilityMode,
    this.targetMediaId,
    this.batchSize = 0,
    this.collectWindowMs = 0,
    this.lastConsumedEventSeq = 0,
    this.cutoffEventSeq,
    this.activeMetadataUpdateId,
    this.errorCode,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.raw = const {},
  });

  final String sessionId;
  final String recognitionJobId;
  final SmartFollowState state;

  /// 单调递增；任何写操作都要带 `expected_state_version`。
  final int stateVersion;

  /// 首版固定 `recognized_only_v1`。
  final String eligibilityMode;
  final String? targetMediaId;
  final int batchSize;
  final int collectWindowMs;
  final int lastConsumedEventSeq;

  /// `finish_current_results`/`stop_following` 之后冻结的截止序号。
  final int? cutoffEventSeq;

  /// 识别累计产出（已 committed 的结果数）。
  final int recognizedCount;

  /// 符合 eligibility 的累计数。
  final int eligibleCount;

  /// 尚未封成 child CopyJob 的待复制照片数。
  final int pendingCount;

  /// 已分配进 child CopyJob 的照片数。
  final int assignedCount;

  /// 已复制**逻辑照片**数。
  final int copiedAssetCount;

  /// 已复制**实际文件**数（RAW+JPEG 分别计）。
  final int copiedFileCount;

  final int failedAssetCount;
  final int childJobCount;

  /// 后端只负责计算；App 只负责呈现，不得据此自动写盘。
  final bool metadataUpdateAvailable;
  final String? activeMetadataUpdateId;

  final List<SmartFollowAction> allowedActions;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;

  /// 未契约化字段原样保留，避免"后端补了字段 App 就丢"。
  final Map<String, dynamic> raw;

  bool get isFinished => state.isFinished;
  bool get canShowCompletion => state.isFinished;
  bool get isWaiting => state.isWaiting;

  SmartFollowAction? action(SmartFollowAction value) => allowedActions.contains(value) ? value : null;

  bool supports(SmartFollowAction value) => allowedActions.contains(value);

  /// 同一会话内，只有不更旧的快照才允许覆盖当前快照（分工任务书 §6）。
  bool isNewerThan(SmartFollowSession other) => stateVersion >= other.stateVersion;

  factory SmartFollowSession.fromJson(Map<String, dynamic> json) {
    final rawActions = json['allowed_actions'];
    final actions = <SmartFollowAction>[];
    if (rawActions is List) {
      for (final item in rawActions) {
        final action = SmartFollowAction.fromWire(item?.toString());
        if (action != null && !actions.contains(action)) actions.add(action);
      }
    }
    return SmartFollowSession(
      sessionId: ProtocolValidation.requiredId(json, 'session_id'),
      recognitionJobId: ProtocolValidation.requiredId(json, 'recognition_job_id'),
      state: SmartFollowState.fromWire(json['state']?.toString()),
      stateVersion: ProtocolValidation.nonNegativeInt(json, 'state_version'),
      eligibilityMode: _stringAlias(json, const ['eligibility_mode', 'mode', 'policy_version']) ?? SmartFollowContract.eligibilityMode,
      targetMediaId: _stringAlias(json, const ['target_media_id']),
      batchSize: _intAlias(json, const ['batch_size', 'default_batch_size']),
      collectWindowMs: _intAlias(json, const ['collect_window_ms', 'default_collect_window_ms']),
      lastConsumedEventSeq: ProtocolValidation.nonNegativeInt(json, 'last_consumed_event_seq'),
      cutoffEventSeq: ProtocolValidation.optionalNonNegativeInt(json, 'cutoff_event_seq'),
      recognizedCount: ProtocolValidation.nonNegativeInt(json, 'recognized_count'),
      eligibleCount: ProtocolValidation.nonNegativeInt(json, 'eligible_count'),
      pendingCount: ProtocolValidation.nonNegativeInt(json, 'pending_count'),
      assignedCount: ProtocolValidation.nonNegativeInt(json, 'assigned_count'),
      copiedAssetCount: ProtocolValidation.nonNegativeInt(json, 'copied_asset_count'),
      copiedFileCount: ProtocolValidation.nonNegativeInt(json, 'copied_file_count'),
      failedAssetCount: ProtocolValidation.nonNegativeInt(json, 'failed_asset_count'),
      childJobCount: ProtocolValidation.nonNegativeInt(json, 'child_job_count'),
      metadataUpdateAvailable: json['metadata_update_available'] == true,
      activeMetadataUpdateId: _stringAlias(json, const ['active_metadata_update_id']),
      allowedActions: List.unmodifiable(actions),
      errorCode: _stringAlias(json, const ['error_code']),
      errorMessage: _stringAlias(json, const ['error_message']),
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
      finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
      raw: Map.unmodifiable(json),
    );
  }

  @override
  String toString() => 'SmartFollowSession($sessionId, ${state.wire}, v$stateVersion, eligible=$eligibleCount, copied=$copiedAssetCount)';
}

/// child CopyJob 摘要（联合任务书 §6.6）。清单不可变，App 只读。
class SmartFollowChildJob {
  const SmartFollowChildJob({
    required this.copyJobId,
    required this.state,
    required this.assetCount,
    required this.fileCount,
    required this.totalBytes,
    required this.copiedFileCount,
    required this.skippedFileCount,
    required this.failedFileCount,
    this.index = 0,
    this.createdAt,
    this.finishedAt,
  });

  final String copyJobId;

  /// 服务端序号（1 起）。缺失时为 0，页面按列表顺序显示。
  final int index;

  /// 复用 RC3 复制任务状态机（`copy_job_models.dart`），不新造枚举。
  final CopyJobState state;

  /// 冻结的逻辑照片数与实际文件数。
  final int assetCount;
  final int fileCount;
  final int totalBytes;
  final int copiedFileCount;
  final int skippedFileCount;
  final int failedFileCount;
  final DateTime? createdAt;
  final DateTime? finishedAt;

  factory SmartFollowChildJob.fromJson(Map<String, dynamic> json) => SmartFollowChildJob(
    copyJobId: ProtocolValidation.requiredId(json, 'copy_job_id'),
    index: _intAlias(json, const ['index', 'ordinal', 'sequence']),
    state: CopyJobState.fromWire(_stringAlias(json, const ['state'])),
    assetCount: _intAlias(json, const ['asset_count', 'frozen_asset_count', 'logical_assets']),
    fileCount: _intAlias(json, const ['file_count', 'planned_files', 'total_files']),
    totalBytes: _intAlias(json, const ['total_bytes', 'planned_bytes']),
    copiedFileCount: _intAlias(json, const ['copied_file_count', 'copied_files', 'copied_count']),
    skippedFileCount: _intAlias(json, const ['skipped_file_count', 'skipped_files', 'skipped_count']),
    failedFileCount: _intAlias(json, const ['failed_file_count', 'failed_files', 'failed_count']),
    createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
    finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
  );
}

/// 子任务分页（服务端固定排序 + cursor 快照）。
class SmartFollowChildJobPage {
  const SmartFollowChildJobPage({required this.items, required this.hasMore, this.nextCursor});

  final List<SmartFollowChildJob> items;
  final bool hasMore;
  final String? nextCursor;

  factory SmartFollowChildJobPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] ?? json['copy_jobs'];
    if (raw is! List) {
      throw const ProtocolCompatibilityException('items', '必须是子任务列表');
    }
    final items = <SmartFollowChildJob>[];
    for (var index = 0; index < raw.length; index++) {
      final item = raw[index];
      if (item is! Map) {
        throw ProtocolCompatibilityException('items[$index]', '必须是对象');
      }
      items.add(SmartFollowChildJob.fromJson(Map<String, dynamic>.from(item)));
    }
    final cursor = _stringAlias(json, const ['next_cursor']);
    return SmartFollowChildJobPage(
      items: List.unmodifiable(items),
      hasMore: json['has_more'] == true && cursor != null,
      nextCursor: cursor,
    );
  }

  static const empty = SmartFollowChildJobPage(items: [], hasMore: false);
}

/// `smart_follow_copy` 能力（联合任务书 §6.1）。
class SmartFollowCapability {
  const SmartFollowCapability({
    required this.available,
    this.contractVersion = SmartFollowContract.version,
    this.eligibilityMode = SmartFollowContract.eligibilityMode,
    this.batchSize = 0,
    this.collectWindowMs = 0,
    this.batchSizeRange = const [],
    this.collectWindowMsRange = const [],
  });

  final bool available;
  final String contractVersion;
  final String eligibilityMode;

  /// 后端当前默认批参数；App 一般不让普通用户修改。
  final int batchSize;
  final int collectWindowMs;

  /// 有效范围 `[min, max]`，空表示后端未声明。
  final List<int> batchSizeRange;
  final List<int> collectWindowMsRange;

  static const unavailable = SmartFollowCapability(available: false);

  factory SmartFollowCapability.fromJson(Object? value) {
    if (value is! Map) return unavailable;
    final json = Map<String, dynamic>.from(value);
    return SmartFollowCapability(
      available: json['available'] == true,
      contractVersion: _stringAlias(json, const ['contract_version']) ?? SmartFollowContract.version,
      eligibilityMode: _stringAlias(json, const ['eligibility_mode', 'mode', 'policy_version']) ?? SmartFollowContract.eligibilityMode,
      batchSize: _intAlias(json, const ['default_batch_size', 'batch_size']),
      collectWindowMs: _intAlias(json, const ['default_collect_window_ms', 'collect_window_ms']),
      batchSizeRange: _intRange(json, const ['batch_size_range']),
      collectWindowMsRange: _intRange(json, const ['collect_window_ms_range']),
    );
  }
}

/// `/recognition-capabilities` 里与 SmartFollow 相关的三项能力。
class SmartFollowCapabilities {
  const SmartFollowCapabilities({
    required this.incrementalRecognition,
    required this.copy,
    required this.metadataUpdate,
    this.incrementalSchemaVersion,
  });

  /// 逐照片 committed 结果可增量读取；SmartFollow 的前置条件。
  final bool incrementalRecognition;
  final SmartFollowCapability copy;
  final bool metadataUpdate;
  final String? incrementalSchemaVersion;

  /// 入口总开关：两项都必须就绪（App 修改任务书 §4、§10）。
  bool get canShowEntry => incrementalRecognition && copy.available;

  /// 信息统一更新入口（`smart_follow_metadata_update=false` 时隐藏）。
  bool get canUpdateMetadata => canShowEntry && metadataUpdate;

  static const none = SmartFollowCapabilities(incrementalRecognition: false, copy: SmartFollowCapability.unavailable, metadataUpdate: false);

  factory SmartFollowCapabilities.fromJson(Map<String, dynamic> json) {
    final incremental = json['incremental_recognition_results'];
    final metadata = json['smart_follow_metadata_update'];
    return SmartFollowCapabilities(
      incrementalRecognition: incremental is Map && incremental['available'] == true,
      incrementalSchemaVersion: incremental is Map ? _stringAlias(Map<String, dynamic>.from(incremental), const ['schema_version']) : null,
      copy: SmartFollowCapability.fromJson(json['smart_follow_copy']),
      metadataUpdate: metadata is Map && metadata['available'] == true,
    );
  }
}

String? _stringAlias(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw == null) continue;
    final value = raw.toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

int _intAlias(Map<String, dynamic> json, List<String> keys, {int fallback = 0}) {
  for (final key in keys) {
    final raw = json[key];
    if (raw == null) continue;
    if (raw is num && raw.isFinite && raw >= 0 && raw.toDouble() == raw.toInt()) return raw.toInt();
  }
  return fallback;
}

List<int> _intRange(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw is! List || raw.length < 2) continue;
    final min = raw[0];
    final max = raw[1];
    if (min is num && max is num && min.isFinite && max.isFinite && min >= 0 && max >= min) {
      return List.unmodifiable([min.toInt(), max.toInt()]);
    }
  }
  return const [];
}
