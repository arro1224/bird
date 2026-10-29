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
    var percent = stats.effectiveProgressPercent;
    // Do not display a stale copied-only 80% alongside an ended task.
    if (state.isTerminal && percent != 1) percent = null;
    return CopyTaskProgress(
      total: count('total_files', stats.totalFiles),
      copied: count('copied_files', stats.copiedFiles),
      failed: count('failed_files', stats.failedFiles),
      skipped: count('skipped_files', stats.skippedFiles),
      notApplicable: count('not_applicable_files', stats.notApplicableFiles),
      copiedBytes: stats.copiedBytesKnown ? _count(stats.copiedBytes) : null,
      percent: percent,
    );
  }

  factory CopyTaskProgress.fromReport(CopyReport report) =>
      CopyTaskProgress(total: _count(report.actualFileCount), copied: _count(report.copiedFiles), failed: _count(report.failedFiles), skipped: _count(report.skippedFiles), notApplicable: _count(report.notApplicableFiles));

  int? get processed => [copied, failed, skipped, notApplicable].any((count) => count == null) ? null : copied! + failed! + skipped! + notApplicable!;
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
  if (frozen != null) return frozen;
  final id = snapshot?.mediaId ?? reportSnapshot?.mediaId;
  final online = devices.where((device) => id != null && device.mediaId == id && device.online).firstOrNull;
  if (online != null) {
    final label = CopyJobDeviceSnapshot(mediaId: online.mediaId, displayName: online.presentationName).presentationLabel;
    if (label != null) return label;
  }
  return '${source ? '源' : '目标'}存储设备（名称暂不可用）';
}
