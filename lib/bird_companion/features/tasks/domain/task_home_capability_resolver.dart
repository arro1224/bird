import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';

/// Computes task-home entries exclusively from the frozen birdbox-v1 reads
/// and the device-scoped local pending queue.
abstract final class TaskHomeCapabilityResolver {
  static List<TaskType> resolve({
    required bool connected,
    required bool authorityReady,
    required DeviceStatus? deviceStatus,
    required BatchSummary? currentProject,
    required CardScanResult? currentScan,
    required Iterable<BirdJobStatus> jobs,
    required bool hasPendingOperations,
  }) {
    return resolveCapabilities(
      connected: connected,
      authorityReady: authorityReady,
      deviceStatus: deviceStatus,
      currentProject: currentProject,
      currentScan: currentScan,
      jobs: jobs,
      hasPendingOperations: hasPendingOperations,
    ).where((capability) => capability.enabled).map((capability) => capability.type).toList(growable: false);
  }

  static List<TaskHomeActionCapability> resolveCapabilities({
    required bool connected,
    required bool authorityReady,
    required DeviceStatus? deviceStatus,
    required BatchSummary? currentProject,
    required CardScanResult? currentScan,
    required Iterable<BirdJobStatus> jobs,
    required bool hasPendingOperations,
  }) {
    const descriptions = {
      TaskType.importIndex: '读取存储卡并建立批次',
      TaskType.aiAnalysis: '分析当前批次照片',
      TaskType.copy: '确认范围和目标设备',
      TaskType.fullBackup: '备份源设备全部摄影资料',
      TaskType.sync: '同步批次和审片结果',
    };
    if (!connected || !authorityReady || deviceStatus == null) {
      final reason = !connected
          ? '连接盒子后可用'
          : !authorityReady
          ? '正在读取盒子权威状态'
          : '盒子状态暂不可用';
      return [
        for (final type in TaskType.values)
          TaskHomeActionCapability(
            type: type,
            enabled: false,
            description: descriptions[type]!,
            disabledReason: reason,
          ),
      ];
    }

    final blockingJobs = jobs.where(_blocksNewWork).toList(growable: false);
    final scanBusy = currentScan?.state == CardScanState.scanning || blockingJobs.any((job) => job.workflowStage == 'scanning');
    final importBusy = blockingJobs.any((job) => job.type == BirdJobType.import);
    final importEnabled = currentScan != null && !scanBusy && !importBusy;
    final importReason = currentScan == null
        ? '尚未取得存储卡扫描状态'
        : scanBusy
        ? '正在扫描存储卡，请稍候'
        : importBusy
        ? '已有导入任务正在执行'
        : null;

    final projectId = currentProject?.id.trim();
    final hasProject = projectId != null && projectId.isNotEmpty;
    final hasPhotos = hasProject && currentProject!.totalFiles > 0;

    // 复制与全量备份都是「目标写任务」：同一时间只能有一个（协议 §16）。
    // 分析任务不阻止复制（§3.1），导入也不阻止；只有另一个目标写任务互斥。
    final targetWriteBusy = blockingJobs.any(
      (job) => job.type == BirdJobType.copy,
    );
    final targetWriteReason = targetWriteBusy
        ? '已有复制/备份任务正在使用目标设备'
        : null;

    final projectPipelineBusy =
        hasProject &&
        blockingJobs.any(
          (job) =>
              (job.type == BirdJobType.import ||
                  job.type == BirdJobType.analysis) &&
              _belongsToProject(job, projectId),
        );
    final analysisReason = !hasProject
        ? '当前没有可用批次'
        : !hasPhotos
        ? '当前批次没有可处理照片'
        : projectPipelineBusy
        ? '当前批次已有任务正在执行'
        : null;
    final copyReason = !hasProject
        ? '当前没有可用批次'
        : !hasPhotos
        ? '当前批次没有可处理照片'
        : targetWriteReason;

    final cardPresent = deviceStatus.card.inserted;
    final fullBackupReason = !cardPresent
        ? '未检测到相机存储卡'
        : targetWriteReason;

    return [
      TaskHomeActionCapability(
        type: TaskType.importIndex,
        enabled: importEnabled,
        description: descriptions[TaskType.importIndex]!,
        disabledReason: importReason,
      ),
      TaskHomeActionCapability(
        type: TaskType.aiAnalysis,
        enabled: hasPhotos && !projectPipelineBusy,
        description: descriptions[TaskType.aiAnalysis]!,
        disabledReason: analysisReason,
      ),
      TaskHomeActionCapability(
        type: TaskType.copy,
        enabled: hasPhotos && !targetWriteBusy,
        description: descriptions[TaskType.copy]!,
        disabledReason: copyReason,
      ),
      TaskHomeActionCapability(
        type: TaskType.fullBackup,
        enabled: cardPresent && !targetWriteBusy,
        description: descriptions[TaskType.fullBackup]!,
        disabledReason: fullBackupReason,
      ),
      TaskHomeActionCapability(
        type: TaskType.sync,
        enabled: hasPendingOperations,
        description: descriptions[TaskType.sync]!,
        disabledReason: hasPendingOperations ? null : '没有待同步的本地修改',
      ),
    ];
  }

  static bool _belongsToProject(BirdJobStatus job, String projectId) {
    final sourceProjectId = job.sourceProjectId?.trim();
    // A missing source id cannot prove that the work belongs elsewhere, so it
    // conservatively blocks a duplicate write for the current project.
    return sourceProjectId == null || sourceProjectId.isEmpty || sourceProjectId == projectId;
  }

  static bool _blocksNewWork(BirdJobStatus job) => switch (job.state) {
    BirdJobState.queued || BirdJobState.idle || BirdJobState.running || BirdJobState.paused || BirdJobState.unknown => true,
    BirdJobState.failed => job.availableActions.any(
      const {'retry', 'retry_failed', 'skip_failed', 'cancel'}.contains,
    ),
    BirdJobState.completed || BirdJobState.cancelled => false,
  };
}
