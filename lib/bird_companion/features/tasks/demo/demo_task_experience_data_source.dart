import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';

class DemoTaskExperienceDataSource implements TaskExperienceDataSource {
  const DemoTaskExperienceDataSource();

  @override
  List<TaskSummary> initialTasks() => const [
    TaskSummary(
      id: 'demo-import-running',
      type: TaskType.importIndex,
      title: '导入/索引',
      processed: 2384,
      total: 3672,
      progressPercent: 65,
      remainingMinutes: 18,
      state: TaskRunState.running,
      sourceBatch: '崇明东滩 7月16日',
      currentFile: 'DSC_2384.ARW',
      speed: '42 MB/s',
      failedCount: 0,
      reviewedCount: 2384,
      pendingReviewCount: 1288,
      connectionState: TaskConnectionState.connected,
      availableActions: {
        TaskAction.pause,
        TaskAction.cancel,
        TaskAction.exportLog,
      },
    ),
    TaskSummary(
      id: 'demo-analysis-paused',
      type: TaskType.aiAnalysis,
      title: 'AI分析',
      processed: 1820,
      total: 2560,
      progressPercent: 71,
      remainingMinutes: 12,
      state: TaskRunState.paused,
      sourceBatch: '东滩晨拍',
      currentFile: 'DSC_1820.ARW',
      speed: '18 张/秒',
      failedCount: 0,
      reviewedCount: 1820,
      pendingReviewCount: 740,
      connectionState: TaskConnectionState.connected,
      availableActions: {
        TaskAction.resume,
        TaskAction.cancel,
        TaskAction.exportLog,
      },
    ),
    TaskSummary(
      id: 'demo-copy-failed',
      type: TaskType.copy,
      title: '复制',
      processed: 2009,
      total: 2012,
      progressPercent: 99,
      remainingMinutes: 0,
      state: TaskRunState.failed,
      sourceBatch: '崇明东滩 7月16日',
      currentFile: 'DSC_3670.ARW',
      failedCount: 3,
      failureReason: '目标硬盘连接中断',
      connectionState: TaskConnectionState.disconnected,
      availableActions: {
        TaskAction.retry,
        TaskAction.skipFailed,
        TaskAction.exportLog,
      },
    ),
    TaskSummary(
      id: 'demo-sync-completed',
      type: TaskType.sync,
      title: '同步',
      processed: 3672,
      total: 3672,
      progressPercent: 100,
      remainingMinutes: 0,
      state: TaskRunState.completed,
      sourceBatch: '南汇海边 7月15日',
      failedCount: 0,
      connectionState: TaskConnectionState.connected,
      availableActions: {TaskAction.exportLog},
    ),
  ];

  @override
  List<TaskType> executableTaskTypes() => const [
    TaskType.importIndex,
    TaskType.aiAnalysis,
    TaskType.copy,
    TaskType.sync,
  ];

  @override
  SdCardSnapshot initialSdCard() => SdCardSnapshot(
    state: SdCardReadState.detected,
    name: 'SanDisk 128GB · U3 · V30',
    photoCount: 3672,
    requiredSpaceGb: 86.4,
    rawCount: 2518,
    jpegCount: 1154,
    captureDate: DateTime(2026, 7, 16),
  );

  @override
  CopyEstimate copyEstimate(CopyMode mode) => switch (mode) {
    CopyMode.keep => const CopyEstimate(
      mode: CopyMode.keep,
      totalPhotoCount: 3672,
      keptCount: 2012,
      pendingReviewCount: 12,
      discardedCount: 1648,
      photoCount: 2012,
      spaceGb: 238.7,
      targetName: 'Samsung T7 Shield',
      availableSpaceTb: 1.2,
      estimatedMinutes: 28,
    ),
    CopyMode.all => const CopyEstimate(
      mode: CopyMode.all,
      totalPhotoCount: 3672,
      keptCount: 2012,
      pendingReviewCount: 12,
      discardedCount: 1648,
      photoCount: 3672,
      spaceGb: 412.6,
      targetName: 'Samsung T7 Shield',
      availableSpaceTb: 1.2,
      estimatedMinutes: 46,
    ),
    CopyMode.dual => const CopyEstimate(
      mode: CopyMode.dual,
      totalPhotoCount: 3672,
      keptCount: 2012,
      pendingReviewCount: 12,
      discardedCount: 1648,
      photoCount: 3672,
      spaceGb: 651.3,
      targetName: 'Samsung T7 Shield',
      availableSpaceTb: 1.2,
      estimatedMinutes: 72,
    ),
  };

  @override
  TaskCompletion completion() => const TaskCompletion(
    photoCount: 2012,
    dataSizeGb: 238.7,
    xmpCount: 2012,
    elapsedMinutes: 27,
    elapsedSeconds: 46,
    pendingReviewCount: 12,
  );
}
