/// 复制任务阶段时间线（迁移对照 §3.5）。
///
/// 阶段含义（协议 §12 状态机到展示的映射）：
/// 等待设备 → 获取目标盘 → 复制文件 → 校验文件 → 写入审阅信息 → 安全同步 → 完成。
///
/// 写入审阅信息 / 安全同步两个阶段当前协议无运行态信号，恒 pending、
/// 终态置 done；OpenAPI 冻结后在 [CopyTimeline.compute] 单点接入。
library;

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';

enum CopyTimelineStageId {
  waitingDevice,
  acquiringTarget,
  copyingFiles,
  verifyingFiles,
  writingReview,
  safeSync,
  done,
}

enum CopyStageStatus { pending, active, done, failed, skipped }

class CopyTimelineStage {
  const CopyTimelineStage({
    required this.id,
    required this.label,
    required this.status,
  });

  final CopyTimelineStageId id;
  final String label;
  final CopyStageStatus status;
}

class CopyTimeline {
  const CopyTimeline({required this.stages});

  final List<CopyTimelineStage> stages;

  static const _stageLabels = <CopyTimelineStageId, String>{
    CopyTimelineStageId.waitingDevice: '等待设备',
    CopyTimelineStageId.acquiringTarget: '获取目标盘',
    CopyTimelineStageId.copyingFiles: '复制文件',
    CopyTimelineStageId.verifyingFiles: '校验文件',
    CopyTimelineStageId.writingReview: '写入审阅信息',
    CopyTimelineStageId.safeSync: '安全同步',
    CopyTimelineStageId.done: '完成',
  };

  /// 由任务状态/统计推导各阶段展示状态（联调期后端契约未冻结，
  /// 这里是有且唯一的映射点）。
  static CopyTimeline compute({
    required CopyJobState state,
    CopyJobStats? stats,
    CopyReport? report,
  }) {
    final statuses = List<CopyStageStatus>.filled(
      CopyTimelineStageId.values.length,
      CopyStageStatus.pending,
      growable: false,
    );

    if (state.isTerminal &&
        (identical(state, CopyJobState.completed) ||
            identical(state, CopyJobState.completedWithErrors))) {
      // 终态成功：全部阶段置 done（含暂无信号的阶段 5/6）。
      for (var i = 0; i < statuses.length; i++) {
        statuses[i] = CopyStageStatus.done;
      }
    } else if (identical(state, CopyJobState.cancelled)) {
      // 已取消：已到达的阶段视为完成，审阅/安全同步/完成阶段置 skipped。
      final phase = _phaseIndex(state, stats);
      for (var i = 0; i <= phase; i++) {
        statuses[i] = CopyStageStatus.done;
      }
      statuses[CopyTimelineStageId.writingReview.index] = CopyStageStatus.skipped;
      statuses[CopyTimelineStageId.safeSync.index] = CopyStageStatus.skipped;
      statuses[CopyTimelineStageId.done.index] = CopyStageStatus.skipped;
    } else {
      // 非终态：按当前阶段推导。
      final phase = _phaseIndex(state, stats);
      for (var i = 0; i < phase; i++) {
        statuses[i] = CopyStageStatus.done;
      }
      statuses[phase] = identical(state, CopyJobState.failed)
          ? CopyStageStatus.failed
          : CopyStageStatus.active;
    }

    return CopyTimeline(
      stages: List.unmodifiable(
        CopyTimelineStageId.values.map(
          (id) => CopyTimelineStage(
            id: id,
            label: _stageLabels[id]!,
            status: statuses[id.index],
          ),
        ),
      ),
    );
  }

  /// 当前所处阶段的下标（0-6）。联调期用 stats 启发式区分复制/校验；
  /// 失败任务无统计信息时按“复制阶段失败”处理，OpenAPI 冻结后单点调整。
  static int _phaseIndex(CopyJobState state, CopyJobStats? stats) {
    return switch (state.wire) {
      'draft' || 'queued' || 'waiting_for_source' => CopyTimelineStageId.waitingDevice.index,
      'waiting_for_target' || 'acquiring_target' => CopyTimelineStageId.acquiringTarget.index,
      'unknown' => CopyTimelineStageId.waitingDevice.index,
      _ => _filePhaseIndex(stats),
    };
  }

  /// running/pause/paused/terminal 共用：copied>=total>0 视为进入校验，
  /// 否则处于复制阶段（终态但无统计信息也归入复制阶段）。
  static int _filePhaseIndex(CopyJobStats? stats) {
    if (stats != null && stats.totalFiles > 0 && stats.copiedFiles >= stats.totalFiles) {
      return CopyTimelineStageId.verifyingFiles.index;
    }
    return CopyTimelineStageId.copyingFiles.index;
  }
}
