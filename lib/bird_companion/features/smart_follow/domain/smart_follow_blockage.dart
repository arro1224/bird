enum SmartFollowBlockedKind { insufficientSpace, targetMissing, targetChanged, targetReadOnly, roleConflict, sourceUnavailable, storageBlocked }

/// Storage facts are a box snapshot. Missing byte values remain unknown and
/// are never reconstructed from each other or from phone storage capacity.
class SmartFollowBlockage {
  SmartFollowBlockage(Map<String, dynamic> summary, {this.observedAt})
    : kind = _kind(summary['blocked_kind']?.toString()) ?? _kind(summary['blocked_reason']?.toString()) ?? SmartFollowBlockedKind.storageBlocked,
      details = summary['blocked_details'] is Map ? Map<String, dynamic>.from(summary['blocked_details'] as Map) : const {};

  final SmartFollowBlockedKind kind;
  final Map<String, dynamic> details;
  final DateTime? observedAt;
  int? bytes(String field) {
    final value = details[field];
    return value is int && value >= 0 ? value : null;
  }

  String get label => switch (kind) {
    SmartFollowBlockedKind.insufficientSpace => '目标盘空间不足',
    SmartFollowBlockedKind.targetMissing => '原目标盘未连接',
    SmartFollowBlockedKind.targetChanged => '目标盘已变化',
    SmartFollowBlockedKind.targetReadOnly => '目标盘只读',
    SmartFollowBlockedKind.roleConflict => '存储角色冲突',
    SmartFollowBlockedKind.sourceUnavailable => '源卡暂不可用',
    SmartFollowBlockedKind.storageBlocked => '存储受阻，等待处理',
  };

  String get hint => switch (kind) {
    SmartFollowBlockedKind.insufficientSpace => '目标盘可用空间触及预留线，原队列已保留。请释放空间后，在原任务允许重试时重试；无需拔盘或新建任务。',
    SmartFollowBlockedKind.targetMissing => '请连接原来的目标盘；已写入的文件和原队列会保留。',
    SmartFollowBlockedKind.targetChanged => '当前目标盘与原任务不一致，请恢复原目标盘后重试，不会自动换盘复制。',
    SmartFollowBlockedKind.targetReadOnly => '请解除原目标盘的只读状态，确认可写后在原任务重试。',
    SmartFollowBlockedKind.roleConflict => '目标存储存在角色冲突，请核对源卡和目标盘的用途后重试。',
    SmartFollowBlockedKind.sourceUnavailable => '复制还需要原相机卡，请恢复同一张源卡后重试；已复制的文件保留。',
    SmartFollowBlockedKind.storageBlocked => '盒子报告存储受阻，原队列已保留。请核对存储状态并刷新原因，不据此判断目标盘已拔出。',
  };

  static SmartFollowBlockedKind? _kind(String? raw) => switch (raw?.toLowerCase()) {
    'insufficient_space' || 'copy_insufficient_space' => SmartFollowBlockedKind.insufficientSpace,
    'target_missing' || 'copy_target_missing' => SmartFollowBlockedKind.targetMissing,
    'target_changed' || 'copy_target_changed' => SmartFollowBlockedKind.targetChanged,
    'target_read_only' || 'copy_target_read_only' => SmartFollowBlockedKind.targetReadOnly,
    'role_conflict' || 'copy_role_conflict' => SmartFollowBlockedKind.roleConflict,
    'source_unavailable' || 'copy_source_unavailable' => SmartFollowBlockedKind.sourceUnavailable,
    'storage_blocked' => SmartFollowBlockedKind.storageBlocked,
    _ => null,
  };
}
