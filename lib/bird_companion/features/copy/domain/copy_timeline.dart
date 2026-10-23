/// Evidence-based task stages. Missing stage signals remain unknown.
library;

import 'copy_job_models.dart';

enum CopyTimelineStageId { waitingDevice, acquiringTarget, copyingFiles, verifyingFiles, writingReview, safeSync, done }

enum CopyStageStatus { pending, active, done, failed, skipped, unknown, partial }

class CopyTimelineStage {
  const CopyTimelineStage({required this.id, required this.label, required this.status, this.note});
  final CopyTimelineStageId id;
  final String label;
  final CopyStageStatus status;
  final String? note;
}

class CopyTimeline {
  const CopyTimeline({required this.stages});
  final List<CopyTimelineStage> stages;
  static const _labels = ['等待设备', '获取目标盘', '复制文件', '校验文件', '写入审阅信息', '安全同步', '任务结束'];

  static CopyTimeline compute({required CopyJobState state, CopyJobStats? stats, CopyReport? report, bool? reviewExportEnabled}) {
    final statuses = List.filled(CopyTimelineStageId.values.length, CopyStageStatus.unknown);
    final notes = <CopyTimelineStageId, String>{};
    void set(CopyTimelineStageId id, CopyStageStatus status, [String? note]) {
      statuses[id.index] = status;
      if (note != null) notes[id] = note;
    }

    switch (state.wire) {
      case 'draft':
      case 'preflighted':
      case 'queued':
        set(CopyTimelineStageId.waitingDevice, CopyStageStatus.active);
        set(CopyTimelineStageId.acquiringTarget, CopyStageStatus.pending);
        set(CopyTimelineStageId.copyingFiles, CopyStageStatus.pending);
        set(CopyTimelineStageId.done, CopyStageStatus.pending);
      case 'waiting_for_source':
        set(CopyTimelineStageId.waitingDevice, CopyStageStatus.active);
      case 'waiting_for_target':
      case 'acquiring_target':
        set(CopyTimelineStageId.acquiringTarget, CopyStageStatus.active);
      case 'running':
      case 'pause_requested':
      case 'cancel_requested':
        set(CopyTimelineStageId.copyingFiles, CopyStageStatus.active, '任务运行中；子阶段未独立提供');
      case 'paused':
        notes[CopyTimelineStageId.copyingFiles] = '任务已暂停；子阶段未独立提供';
      case 'completed':
      case 'completed_with_errors':
        final partial = state == CopyJobState.completedWithErrors || report?.isPartialSuccess == true;
        set(CopyTimelineStageId.done, partial ? CopyStageStatus.partial : CopyStageStatus.done, partial ? '部分完成' : '任务已完成');
      case 'failed':
        set(CopyTimelineStageId.done, CopyStageStatus.failed, '任务失败；失败阶段未独立提供');
      case 'cancelled':
        set(CopyTimelineStageId.done, CopyStageStatus.skipped, '任务已取消');
    }
    // Counters are outcomes, not evidence of a separate verifying/sync phase.
    notes[CopyTimelineStageId.verifyingFiles] = '未提供独立状态';
    notes[CopyTimelineStageId.safeSync] = '未提供独立状态';
    if (report?.isPartialSuccess == true && (report!.csvStatus == 'failed' || (report.exportFailedCount ?? 0) > 0 || (report.embedDegradedCount ?? 0) > 0)) {
      final failed = report.csvStatus == 'failed' || (report.exportFailedCount ?? 0) > 0;
      set(CopyTimelineStageId.writingReview, failed ? CopyStageStatus.failed : CopyStageStatus.partial, failed ? '审阅导出失败' : '审阅信息存在嵌入降级');
    } else if (reviewExportEnabled == false) {
      set(CopyTimelineStageId.writingReview, CopyStageStatus.skipped, '未启用');
    } else {
      // CSV success alone cannot certify XMP/embedded output as successful.
      notes[CopyTimelineStageId.writingReview] = switch (report?.csvStatus) {
        'success' => 'CSV 已导出；整体阶段未提供独立结果',
        'not_requested' => 'CSV 未启用；整体阶段未提供独立结果',
        _ => '未提供独立状态',
      };
    }
    return CopyTimeline(
      stages: List.unmodifiable(CopyTimelineStageId.values.map((id) => CopyTimelineStage(id: id, label: _labels[id.index], status: statuses[id.index], note: notes[id]))),
    );
  }
}
