enum TaskRunState { queued, running, paused, failed, completed, cancelled }

enum TaskType { importIndex, aiAnalysis, copy, fullBackup, sync }

extension TaskTypeLabel on TaskType {
  String get label => switch (this) {
    TaskType.importIndex => '导入/索引',
    TaskType.aiAnalysis => 'AI分析',
    TaskType.copy => '复制照片',
    TaskType.fullBackup => '全量备份',
    TaskType.sync => '同步',
  };
}

enum TaskGroup { active, attention, completed }

enum TaskConnectionState { connected, reconnecting, disconnected }

enum TaskAction { pause, resume, cancel, retry, skipFailed, exportLog }

enum SdCardReadState { detected, scanning, missing, readFailed, empty }

/// Demo 遗留复制模式。协议冻结后 `dual`（双轨复制）已按主协议 §5 删除；
/// 生产复制流程使用 features/copy/domain/copy_models.dart 的 CopyScope。
enum CopyMode { keep, all }

class TaskHomeActionCapability {
  const TaskHomeActionCapability({
    required this.type,
    required this.enabled,
    required this.description,
    this.disabledReason,
  });

  final TaskType type;
  final bool enabled;
  final String description;
  final String? disabledReason;
}

class TaskControlIntent {
  const TaskControlIntent(this.taskId, this.action);

  final String taskId;
  final TaskAction action;

  @override
  bool operator ==(Object other) => other is TaskControlIntent && taskId == other.taskId && action == other.action;

  @override
  int get hashCode => Object.hash(taskId, action);
}

class TaskSummary {
  const TaskSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.processed,
    required this.total,
    required this.progressPercent,
    required this.remainingMinutes,
    required this.state,
    this.workflowStage,
    this.sourceBatch,
    this.sourceBatchId,
    this.currentFile,
    this.speed,
    this.failedCount,
    this.failureReason,
    this.reviewedCount,
    this.pendingReviewCount,
    this.connectionState,
    this.finishedAt,
    this.updatedAt,
    this.photoPreparation = false,
    this.pendingCancellation = false,
    this.availableActions = const {},
  });

  final String id;
  final TaskType type;
  final String title;
  final int processed;
  final int total;
  final int progressPercent;
  final int? remainingMinutes;
  final TaskRunState state;
  final String? workflowStage;
  final String? sourceBatch;
  final String? sourceBatchId;
  final String? currentFile;
  final String? speed;
  final int? failedCount;
  final String? failureReason;
  final int? reviewedCount;
  final int? pendingReviewCount;
  final TaskConnectionState? connectionState;
  final DateTime? finishedAt;
  final DateTime? updatedAt;
  final bool photoPreparation;
  final bool pendingCancellation;
  bool get waitingForImport => workflowStage == 'waiting_import' && state == TaskRunState.queued;
  bool get isFinishing => state == TaskRunState.running && (progressPercent >= 100 || workflowStage == 'finalizing');
  String get etaLabel => waitingForImport
      ? '导入完成后由盒子自动开始识别'
      : isFinishing
      ? '正在收尾，等待盒子确认完成'
      : remainingMinutes == null
      ? '剩余时间暂不可用'
      : '预计剩余 $remainingMinutes 分钟';
  String get freshnessLabel => freshnessFor(connectionState);
  String freshnessFor(TaskConnectionState? connection) {
    final time = updatedAt?.toLocal();
    final label = time == null ? '盒子未提供更新时间' : '更新于 ${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return connection == TaskConnectionState.connected || connection == null ? label : '上次进度快照 · $label';
  }

  final Set<TaskAction> availableActions;

  TaskGroup get group => switch (state) {
    TaskRunState.queued || TaskRunState.running => TaskGroup.active,
    TaskRunState.paused || TaskRunState.failed => TaskGroup.attention,
    TaskRunState.completed || TaskRunState.cancelled => TaskGroup.completed,
  };

  TaskSummary copyWith({
    TaskRunState? state,
    Set<TaskAction>? availableActions,
    String? sourceBatch,
    String? sourceBatchId,
    int? processed,
    int? progressPercent,
    int? remainingMinutes,
    bool clearFailure = false,
    String? workflowStage,
    bool? pendingCancellation,
  }) => TaskSummary(
    id: id,
    type: type,
    title: title,
    processed: processed ?? this.processed,
    total: total,
    progressPercent: progressPercent ?? this.progressPercent,
    remainingMinutes: remainingMinutes ?? this.remainingMinutes,
    state: state ?? this.state,
    workflowStage: workflowStage ?? this.workflowStage,
    sourceBatch: sourceBatch ?? this.sourceBatch,
    sourceBatchId: sourceBatchId ?? this.sourceBatchId,
    currentFile: currentFile,
    speed: speed,
    failedCount: clearFailure ? 0 : failedCount,
    failureReason: clearFailure ? null : failureReason,
    reviewedCount: reviewedCount,
    pendingReviewCount: pendingReviewCount,
    connectionState: connectionState,
    finishedAt: finishedAt,
    updatedAt: updatedAt,
    photoPreparation: photoPreparation,
    pendingCancellation: pendingCancellation ?? this.pendingCancellation,
    availableActions: availableActions ?? this.availableActions,
  );
}

class SdCardSnapshot {
  const SdCardSnapshot({
    required this.state,
    required this.name,
    required this.photoCount,
    required this.requiredSpaceGb,
    required this.rawCount,
    required this.jpegCount,
    required this.captureDate,
  });

  final SdCardReadState state;
  final String name;
  final int photoCount;
  final double requiredSpaceGb;
  final int rawCount;
  final int jpegCount;
  final DateTime captureDate;
  DateTime get scannedAt => captureDate;

  SdCardSnapshot copyWith({
    SdCardReadState? state,
    String? name,
    int? photoCount,
    double? requiredSpaceGb,
    int? rawCount,
    int? jpegCount,
    DateTime? captureDate,
  }) => SdCardSnapshot(
    state: state ?? this.state,
    name: name ?? this.name,
    photoCount: photoCount ?? this.photoCount,
    requiredSpaceGb: requiredSpaceGb ?? this.requiredSpaceGb,
    rawCount: rawCount ?? this.rawCount,
    jpegCount: jpegCount ?? this.jpegCount,
    captureDate: captureDate ?? this.captureDate,
  );
}

class CopyEstimate {
  const CopyEstimate({
    required this.mode,
    required this.totalPhotoCount,
    required this.keptCount,
    required this.pendingReviewCount,
    required this.discardedCount,
    required this.photoCount,
    required this.spaceGb,
    required this.targetName,
    required this.availableSpaceTb,
    required this.estimatedMinutes,
    this.targetOnline = true,
  });

  final CopyMode mode;
  final int totalPhotoCount;
  final int keptCount;
  final int pendingReviewCount;
  final int discardedCount;
  final int photoCount;
  final double spaceGb;
  final String targetName;
  final double availableSpaceTb;
  final int estimatedMinutes;
  final bool targetOnline;

  bool get hasEnoughSpace => availableSpaceTb * 1024 >= spaceGb;

  CopyEstimate copyWith({bool? targetOnline}) => CopyEstimate(
    mode: mode,
    totalPhotoCount: totalPhotoCount,
    keptCount: keptCount,
    pendingReviewCount: pendingReviewCount,
    discardedCount: discardedCount,
    photoCount: photoCount,
    spaceGb: spaceGb,
    targetName: targetName,
    availableSpaceTb: availableSpaceTb,
    estimatedMinutes: estimatedMinutes,
    targetOnline: targetOnline ?? this.targetOnline,
  );
}

class TaskCompletion {
  const TaskCompletion({
    required this.photoCount,
    required this.dataSizeGb,
    required this.xmpCount,
    required this.elapsedMinutes,
    required this.elapsedSeconds,
    required this.pendingReviewCount,
  });

  final int photoCount;
  final double dataSizeGb;
  final int xmpCount;
  final int elapsedMinutes;
  final int elapsedSeconds;
  final int pendingReviewCount;
}

abstract interface class TaskExperienceDataSource {
  List<TaskSummary> initialTasks();

  List<TaskType> executableTaskTypes();

  SdCardSnapshot initialSdCard();

  CopyEstimate copyEstimate(CopyMode mode);

  TaskCompletion completion();
}
