import 'copy_job_models.dart';
import 'copy_models.dart';

/// Shared list/detail/report outcome projection. No inferred percentage or
/// denominator: backend total_files coverage still needs board confirmation.
class CopyTaskProgress {
  const CopyTaskProgress({this.total, this.copied, this.failed, this.skipped, this.notApplicable, this.copiedBytes, this.percent});
  final int? total, copied, failed, skipped, notApplicable, copiedBytes;
  final double? percent;
  static int? _count(int? value) => value != null && value >= 0 ? value : null;

  factory CopyTaskProgress.fromStats(CopyJobStats? stats, CopyJobState state) {
    if (stats == null) return const CopyTaskProgress();
    int? count(String key, int value) => stats.knownFileCounts.contains(key) ? _count(value) : null;
    final total = count('total_files', stats.totalFiles);
    final copied = count('copied_files', stats.copiedFiles);
    final failed = count('failed_files', stats.failedFiles);
    final skipped = count('skipped_files', stats.skippedFiles);
    final notApplicable = count('not_applicable_files', stats.notApplicableFiles);
    final processed = [copied, failed, skipped, notApplicable].any((value) => value == null) ? null : copied! + failed! + skipped! + notApplicable!;
    var percent = stats.effectiveProgressPercent;
    if (state.isTerminal) {
      // v10 问题 11：终态已处理数达到盒子文件总数时显示 100%；
      // 否则隐藏过期分数，避免"已完成却显示 80%"。计数来自后端，不做本地累加。
      if (percent != 1) percent = null;
      if (percent == null && total != null && processed != null && processed >= total && total > 0) percent = 1;
    }
    return CopyTaskProgress(
      total: total,
      copied: copied,
      failed: failed,
      skipped: skipped,
      notApplicable: notApplicable,
      copiedBytes: stats.copiedBytesKnown ? _count(stats.copiedBytes) : null,
      percent: percent,
    );
  }

  factory CopyTaskProgress.fromReport(CopyReport report) {
    final total = _count(report.actualFileCount);
    final copied = _count(report.copiedFiles);
    final failed = _count(report.failedFiles);
    final skipped = _count(report.skippedFiles);
    final notApplicable = _count(report.notApplicableFiles);
    final processed = [copied, failed, skipped, notApplicable].any((value) => value == null) ? null : copied! + failed! + skipped! + notApplicable!;
    // 终态报告：处理总数达到实际文件数即 100%（含失败/跳过/不适用）。
    final percent = total != null && processed != null && total > 0 && processed >= total ? 1.0 : null;
    return CopyTaskProgress(total: total, copied: copied, failed: failed, skipped: skipped, notApplicable: notApplicable, percent: percent);
  }

  int? get processed => [copied, failed, skipped, notApplicable].any((count) => count == null) ? null : copied! + failed! + skipped! + notApplicable!;

  /// 未归类项 = 盒子文件总数 − 已处理数（v10 问题 2 统计守恒检查）。
  int? get unprocessed => total == null || processed == null ? null : total! - processed!;

  String summary(CopyJobState state) {
    final verb = switch (state.wire) {
      'completed' || 'completed_with_errors' => '处理完成',
      _ => '已处理',
    };
    final count = processed;
    return '$verb ${count == null ? '数量暂不可用' : '$count 项'}（复制 ${copied ?? '—'}，跳过 ${skipped ?? '—'}，失败 ${failed ?? '—'}，不适用 ${notApplicable ?? '—'}）';
  }
}

class CopyTaskTiming {
  const CopyTaskTiming({this.elapsedSeconds, this.bytesPerSecond, required this.source});
  final num? elapsedSeconds, bytesPerSecond;
  final String source;
  factory CopyTaskTiming.forTask(CopyJobDetail detail, CopyReport? report) {
    if (detail.state.isTerminal && report != null) return CopyTaskTiming.fromReport(report);
    return CopyTaskTiming(elapsedSeconds: detail.stats?.elapsedSeconds, bytesPerSecond: detail.stats?.bytesPerSecond, source: '任务详情');
  }
  factory CopyTaskTiming.fromReport(CopyReport report) => CopyTaskTiming(elapsedSeconds: report.elapsedSeconds, bytesPerSecond: report.bytesPerSecond, source: '终态报告');
  static bool valid(num? value) => value != null && value.isFinite && value >= 0;
  String get elapsedLabel => valid(elapsedSeconds) ? formatSeconds(elapsedSeconds!) : '暂不可用';
  String get speedLabel => valid(bytesPerSecond) ? '${formatBytes(bytesPerSecond!)}/s' : '暂不可用';
}

String formatSeconds(num seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds - minutes * 60;
  String number(num value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  return minutes > 0 ? '$minutes 分 ${number(rest)} 秒' : '${number(seconds)} 秒';
}

String formatBytes(num bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${bytes == bytes.roundToDouble() ? bytes.toInt() : bytes} B';
}

String copyTaskDeviceName({required bool source, CopyJobDeviceSnapshot? snapshot, CopyJobDeviceSnapshot? reportSnapshot, List<StorageDeviceSummary> devices = const []}) {
  if (snapshot?.mediaId != null && reportSnapshot?.mediaId != null && snapshot!.mediaId != reportSnapshot!.mediaId) reportSnapshot = null;
  final frozen = snapshot?.presentationLabel ?? reportSnapshot?.presentationLabel;
  final id = snapshot?.mediaId ?? reportSnapshot?.mediaId;
  final current = id == null ? null : devices.where((device) => device.mediaId == id).firstOrNull;
  // v10 问题 12：目标盘拔出后仍要显示任务快照名，并标注（已拔出）。
  // 设备列表为空表示本次没读到（不是"设备不存在"），不得据此误报拔出。
  final offline = id != null && devices.isNotEmpty && current?.online != true;
  if (frozen != null) return offline ? '$frozen（已拔出）' : frozen;
  final online = current?.online == true ? current : null;
  if (online != null) {
    final label = CopyJobDeviceSnapshot(mediaId: online.mediaId, displayName: online.presentationName).presentationLabel;
    if (label != null) return offline ? '$label（已拔出）' : label;
  }
  return '${source ? '源' : '目标'}存储设备（名称暂不可用）';
}
