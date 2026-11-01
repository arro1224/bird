/// SmartFollow 信息统一更新的 DTO（联合任务书 §2.3/§2.4/§6.8）。
///
/// 这几组字段是本次契约里**最不确定**的一块：联合任务书只描述了预览"应该
/// 返回什么"（目标身份、涉及子任务数、可更新/不变/不可更新/冲突数、预计写入
/// 方式和空间），没有给 wire 名。因此这里：
///
/// - 只把文档明确列出的概念做成强类型 getter；
/// - 完整原始响应保留在 [raw] 里，后端补字段时页面不必等 DTO 改动；
/// - 具体字段名待分工任务书 §5 第 6 条与后端对账确认，确认后回来删别名。
library;

import 'package:aves/bird_companion/core/models/protocol_validation.dart';

/// 会话当前是否可更新信息，以及可更新的规模。
class SmartFollowMetadataAvailability {
  const SmartFollowMetadataAvailability({
    required this.available,
    this.activeUpdateId,
    this.updatableAssetCount = 0,
    this.blockedAssetCount = 0,
    this.reason,
    this.raw = const {},
  });

  /// 后端 `metadata_update_available` 的展开形式；false 时 App 不显示入口。
  final bool available;

  /// 已有父任务在跑时非空，App 只展示进度、不再允许新建。
  final String? activeUpdateId;
  final int updatableAssetCount;
  final int blockedAssetCount;

  /// 后端给的用户可读原因（不得是错误码）。
  final String? reason;
  final Map<String, dynamic> raw;

  static const unavailable = SmartFollowMetadataAvailability(available: false);

  factory SmartFollowMetadataAvailability.fromJson(Map<String, dynamic> json) => SmartFollowMetadataAvailability(
    available: json['available'] == true || json['metadata_update_available'] == true,
    activeUpdateId: _str(json, const ['active_update_id', 'active_metadata_update_id']),
    updatableAssetCount: _int(json, const ['updatable_asset_count', 'updateable_asset_count', 'updatable_count']),
    blockedAssetCount: _int(json, const ['blocked_asset_count', 'unchanged_or_blocked_count']),
    reason: _str(json, const ['reason', 'message']),
    raw: Map.unmodifiable(json),
  );
}

/// 预览结果：用户确认前必须看到的全部信息（联合 §6.8）。
class SmartFollowMetadataPreview {
  const SmartFollowMetadataPreview({
    required this.previewId,
    required this.previewToken,
    this.expiresAt,
    this.targetMediaId,
    this.targetDisplayName,
    this.childJobCount = 0,
    this.updatableAssetCount = 0,
    this.updatableFileCount = 0,
    this.unchangedCount = 0,
    this.blockedCount = 0,
    this.conflictCount = 0,
    this.estimatedBytes = 0,
    this.writeMode,
    this.requiresPartialConfirmation = false,
    this.blockedReasons = const [],
    this.knownCounts = const {},
    this.partialConfirmationKnown = false,
    this.ready = true,
    this.raw = const {},
  });

  final String previewId;
  final String previewToken;
  final DateTime? expiresAt;

  /// 目标身份：只用于展示与核对，禁止展示 Linux 路径。
  final String? targetMediaId;
  final String? targetDisplayName;

  final int childJobCount;
  final int updatableAssetCount;
  final int updatableFileCount;
  final int unchangedCount;
  final int blockedCount;
  final int conflictCount;
  final int estimatedBytes;

  /// 预计写入方式（RC3 口径：安全支持时内嵌，否则配套 XMP，另生成汇总 CSV）。
  /// 后端未冻结枚举，未知值不可默认为某种安全写入策略。
  final String? writeMode;

  /// 存在不可更新/受阻项，用户必须显式确认"部分更新"。
  final bool requiresPartialConfirmation;
  final List<String> blockedReasons;
  static const countKeys = {'child_job_count', 'updatable_asset_count', 'updatable_file_count', 'unchanged_count', 'blocked_count', 'conflict_count', 'estimated_bytes'};
  final Set<String> knownCounts;
  final bool partialConfirmationKnown;
  final bool ready;
  int? count(String key) => knownCounts.contains(key)
      ? switch (key) {
          'child_job_count' => childJobCount,
          'updatable_asset_count' => updatableAssetCount,
          'updatable_file_count' => updatableFileCount,
          'unchanged_count' => unchangedCount,
          'blocked_count' => blockedCount,
          'conflict_count' => conflictCount,
          'estimated_bytes' => estimatedBytes,
          _ => null,
        }
      : null;
  bool get needsPartialConsent => requiresPartialConfirmation || blockedCount > 0 || conflictCount > 0;
  bool get hasKnownWriteMode => const {'embed', 'embedded', 'embed_only', 'embed_then_xmp_csv', 'safe_embed_first', 'xmp_csv', 'sidecar'}.contains(writeMode);
  final Map<String, dynamic> raw;

  bool get isExpired {
    final deadline = expiresAt;
    return deadline != null && !DateTime.now().isBefore(deadline);
  }

  /// 没有可更新项时不允许创建任务。
  bool get hasUpdatableItems => updatableAssetCount > 0;

  String get writeModeLabel => switch (writeMode) {
    'embed' || 'embedded' || 'embed_only' => '内嵌到支持的副本',
    'embed_then_xmp_csv' || 'safe_embed_first' => '安全支持时内嵌，否则写配套 XMP，并生成汇总 CSV',
    'xmp_csv' || 'sidecar' => '写配套 XMP 与汇总 CSV',
    null || '' => '未提供',
    _ => '暂无法确认写入方式',
  };

  factory SmartFollowMetadataPreview.fromJson(Map<String, dynamic> json) {
    final reasons = json['blocked_reasons'] ?? json['partially_blocked_reasons'];
    return SmartFollowMetadataPreview(
      previewId: _str(json, const ['preview_id']) ?? ProtocolValidation.requiredId(json, 'preview_token'),
      previewToken: ProtocolValidation.requiredId(json, 'preview_token'),
      expiresAt: ProtocolValidation.optionalDateTime(json, 'expires_at'),
      targetMediaId: _str(json, const ['target_media_id']),
      targetDisplayName: _str(json, const ['target_display_name', 'target_name']),
      childJobCount: _count(json, const ['child_job_count', 'copy_job_count']),
      updatableAssetCount: _count(json, const ['updatable_asset_count', 'updateable_asset_count']),
      updatableFileCount: _count(json, const ['updatable_file_count', 'updateable_file_count']),
      unchangedCount: _count(json, const ['unchanged_count']),
      blockedCount: _count(json, const ['blocked_count', 'not_updatable_count']),
      conflictCount: _count(json, const ['conflict_count']),
      estimatedBytes: _count(json, const ['estimated_bytes', 'total_bytes']),
      writeMode: _str(json, const ['write_mode', 'write_method']),
      requiresPartialConfirmation: json['requires_partial_confirmation'] == true || (json['partial'] == true),
      blockedReasons: reasons is List ? List.unmodifiable(reasons.map((item) => item.toString()).where((item) => item.isNotEmpty)) : const [],
      knownCounts: Set.unmodifiable(
        {
          'child_job_count': const ['child_job_count', 'copy_job_count'],
          'updatable_asset_count': const ['updatable_asset_count', 'updateable_asset_count'],
          'updatable_file_count': const ['updatable_file_count', 'updateable_file_count'],
          'unchanged_count': const ['unchanged_count'],
          'blocked_count': const ['blocked_count', 'not_updatable_count'],
          'conflict_count': const ['conflict_count'],
          'estimated_bytes': const ['estimated_bytes', 'total_bytes'],
        }.entries.where((entry) => entry.value.any((key) => json[key] is int && (json[key] as int) >= 0)).map((entry) => entry.key),
      ),
      partialConfirmationKnown: json['requires_partial_confirmation'] is bool || json['partial'] is bool,
      ready: json['state'] == null || json['state'] == 'ready',
      raw: Map.unmodifiable(json),
    );
  }
}

/// 父级信息更新任务（按 child CopyJob 拆成多个 RC3 MetadataUpdateJob）。
class SmartFollowMetadataUpdate {
  const SmartFollowMetadataUpdate({
    required this.updateId,
    required this.state,
    this.stateVersion = 0,
    this.childJobCount = 0,
    this.updatedAssetCount = 0,
    this.updatedFileCount = 0,
    this.failedCount = 0,
    this.unchangedCount = 0,
    this.blockedCount = 0,
    this.childUpdates = const [],
    this.errorCode,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
    this.knownCounts = const {},
    this.childrenProvided = false,
    this.raw = const {},
  });

  final String updateId;

  /// 父任务状态未在联合 §4 冻结，保留原文；终端判定见 [isTerminal]。
  final String state;
  final int stateVersion;
  final int childJobCount;
  final int updatedAssetCount;
  final int updatedFileCount;
  final int failedCount;
  final int unchangedCount;
  final int blockedCount;

  /// 每项对应一个 RC3 MetadataUpdateJob，可追溯到原 child CopyJob。
  final List<SmartFollowMetadataChildUpdate> childUpdates;

  final String? errorCode;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? finishedAt;
  final Map<String, dynamic> raw;
  static const countAliases = {
    'child_job_count': ['child_job_count', 'child_count'],
    'updated_asset_count': ['updated_asset_count', 'updated_assets'],
    'updated_file_count': ['updated_file_count', 'updated_files'],
    'failed_count': ['failed_count', 'failed_file_count'],
    'unchanged_count': ['unchanged_count'],
    'blocked_count': ['blocked_count'],
  };
  final Set<String> knownCounts;
  final bool childrenProvided;
  bool get stateVersionKnown => raw['state_version'] is int && (raw['state_version'] as int) >= 0;
  int? count(String key) => !knownCounts.contains(key)
      ? null
      : switch (key) {
          'child_job_count' => childJobCount,
          'updated_asset_count' => updatedAssetCount,
          'updated_file_count' => updatedFileCount,
          'failed_count' => failedCount,
          'unchanged_count' => unchangedCount,
          'blocked_count' => blockedCount,
          _ => null,
        };

  /// 后端确认前只按"明确表示结束"的值收敛；未知值当作未结束，
  /// 页面继续按运行中展示并允许刷新，不会误报完成。
  bool get isTerminal => const {'completed', 'completed_partial', 'failed', 'cancelled'}.contains(state.trim());

  /// A missing/truncated list cannot prove that all child writes have stopped.
  bool get childrenSettled =>
      childrenProvided && count('child_job_count') == childUpdates.length && childUpdates.map((child) => child.metadataUpdateId).toSet().length == childUpdates.length && childUpdates.every((child) => child.isTerminal);

  bool get isPartial => state.trim() == 'completed_partial' || blockedCount > 0;

  factory SmartFollowMetadataUpdate.fromJson(Map<String, dynamic> json) {
    final children = json['child_jobs'] ?? json['child_updates'] ?? json['metadata_update_jobs'];
    if (children != null && children is! List) throw const ProtocolCompatibilityException('child_jobs', '必须是列表');
    final parsed = <SmartFollowMetadataChildUpdate>[];
    if (children is List) {
      for (final child in children) {
        if (child is! Map) throw const ProtocolCompatibilityException('child_jobs', '每个子任务必须是对象');
        parsed.add(SmartFollowMetadataChildUpdate.fromJson(Map<String, dynamic>.from(child)));
      }
    }
    return SmartFollowMetadataUpdate(
      updateId: ProtocolValidation.requiredId(json, 'update_id'),
      state: _str(json, const ['state', 'status']) ?? 'unknown',
      stateVersion: ProtocolValidation.nonNegativeInt(json, 'state_version'),
      childJobCount: _count(json, countAliases['child_job_count']!),
      updatedAssetCount: _count(json, countAliases['updated_asset_count']!),
      updatedFileCount: _count(json, countAliases['updated_file_count']!),
      failedCount: _count(json, countAliases['failed_count']!),
      unchangedCount: _count(json, countAliases['unchanged_count']!),
      blockedCount: _count(json, countAliases['blocked_count']!),
      knownCounts: _knownCounts(json, countAliases),
      childrenProvided: children is List,
      childUpdates: List.unmodifiable(parsed),
      errorCode: _str(json, const ['error_code']),
      errorMessage: _str(json, const ['error_message', 'message']),
      createdAt: ProtocolValidation.optionalDateTime(json, 'created_at'),
      updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
      finishedAt: ProtocolValidation.optionalDateTime(json, 'finished_at'),
      raw: Map.unmodifiable(json),
    );
  }
}

/// 父任务下的单个 RC3 MetadataUpdateJob（按原 child CopyJob 拆分）。
class SmartFollowMetadataChildUpdate {
  const SmartFollowMetadataChildUpdate({
    required this.metadataUpdateId,
    this.copyJobId,
    this.state = 'unknown',
    this.updatedFileCount = 0,
    this.failedFileCount = 0,
    this.errorCode,
    this.errorMessage,
    this.knownCounts = const {},
  });

  final String metadataUpdateId;

  /// 对应的原 child CopyJob（RC3 详情页可直达）。
  final String? copyJobId;
  final String state;
  final int updatedFileCount;
  final int failedFileCount;
  final String? errorCode;
  final String? errorMessage;
  final Set<String> knownCounts;
  static const countAliases = {
    'updated_file_count': ['updated_file_count', 'updated_files'],
    'failed_file_count': ['failed_file_count', 'failed_files'],
  };
  int? count(String key) => !knownCounts.contains(key)
      ? null
      : switch (key) {
          'updated_file_count' => updatedFileCount,
          'failed_file_count' => failedFileCount,
          _ => null,
        };

  bool get isTerminal => const {'completed', 'completed_partial', 'failed', 'cancelled'}.contains(state.trim());

  factory SmartFollowMetadataChildUpdate.fromJson(Map<String, dynamic> json) => SmartFollowMetadataChildUpdate(
    metadataUpdateId: ProtocolValidation.requiredId(json, 'metadata_update_id'),
    copyJobId: _str(json, const ['copy_job_id', 'source_copy_job_id']),
    state: _str(json, const ['state', 'status']) ?? 'unknown',
    updatedFileCount: _count(json, countAliases['updated_file_count']!),
    failedFileCount: _count(json, countAliases['failed_file_count']!),
    knownCounts: _knownCounts(json, countAliases),
    errorCode: _str(json, const ['error_code']),
    errorMessage: _str(json, const ['error_message']),
  );
}

String? _str(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw == null) continue;
    final value = raw.toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

int _count(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int && value >= 0) return value;
  }
  return 0;
}

Set<String> _knownCounts(Map<String, dynamic> json, Map<String, List<String>> aliases) => Set.unmodifiable(aliases.entries.where((entry) => entry.value.any((key) => json[key] is int && (json[key] as int) >= 0)).map((entry) => entry.key));

int _int(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw is num && raw.isFinite && raw >= 0) return raw.toInt();
  }
  return 0;
}
