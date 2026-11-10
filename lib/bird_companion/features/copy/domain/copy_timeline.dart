/// Evidence-based task stages. Missing stage signals remain unknown.
library;

import 'copy_job_models.dart';

enum CopyTimelineStageId { waitingDevice, acquiringTarget, copyingFiles, verifyingFiles, writingReview, safeSync, done }

enum CopyStageStatus { pending, active, done, failed, skipped, unknown, partial, observed }

class CopyTimelineStage {
  const CopyTimelineStage({required this.id, required this.label, required this.status, this.note, this.recordedAt});
  final CopyTimelineStageId id;
  final String label;
  final CopyStageStatus status;
  final String? note;
  final DateTime? recordedAt;
}

class CopyTimeline {
  const CopyTimeline({required this.stages});
  final List<CopyTimelineStage> stages;
  static const _labels = ['等待设备', '获取目标盘', '复制文件', '校验文件', '写入审阅信息', '安全同步', '任务结束'];

  static CopyTimeline compute({required CopyJobState state, CopyJobStats? stats, CopyReport? report, bool? reviewExportEnabled, List<CopyJobEvent> events = const []}) {
    final statuses = List.filled(CopyTimelineStageId.values.length, CopyStageStatus.unknown);
    final notes = <CopyTimelineStageId, String>{};
    final recorded = <CopyTimelineStageId, DateTime?>{};
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
    // A state event proves that a stage was reached, not that it completed.
    // Keep the resource's current state authoritative (especially pause/wait).
    final ordered = events.where((event) => event.seq != null && event.seq! > 0).toList()..sort((a, b) => a.seq!.compareTo(b.seq!));
    for (final event in ordered) {
      if (event.type != 'state_changed') continue;
      // Legacy mock/older boxes sent only these exact messages. Never infer
      // stages from arbitrary text, item completion, or file verification.
      final legacy = switch (event.message) {
        '正在获取目标盘' => 'acquiring_target',
        '开始复制文件' || '任务已继续' => 'running',
        _ => null,
      };
      final wire = event.payload.containsKey('state') ? event.payload['state'] : legacy;
      final id = switch (wire) {
        'queued' || 'waiting_for_source' => CopyTimelineStageId.waitingDevice,
        'acquiring_target' || 'waiting_for_target' => CopyTimelineStageId.acquiringTarget,
        'running' => CopyTimelineStageId.copyingFiles,
        _ => null,
      };
      if (id == null || recorded.containsKey(id)) continue;
      recorded[id] = event.createdAt;
      if (statuses[id.index] == CopyStageStatus.unknown) {
        set(id, CopyStageStatus.observed, state == CopyJobState.paused && id == CopyTimelineStageId.copyingFiles ? '任务已暂停；已记录开始，未提供独立结束状态' : '已记录进入此阶段；未提供独立结束状态');
      }
    }
    return CopyTimeline(
      stages: List.unmodifiable(CopyTimelineStageId.values.map((id) => CopyTimelineStage(id: id, label: _labels[id.index], status: statuses[id.index], note: notes[id], recordedAt: recorded[id]))),
    );
  }
}
