import 'package:flutter/foundation.dart';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

class SmartFollowCompletionChild {
  const SmartFollowCompletionChild(this.job, {this.detail, this.report, this.issue});
  final SmartFollowChildJob job;
  final CopyJobDetail? detail;
  final CopyReport? report;
  final String? issue;
}

/// A read-only projection. Nullable counts deliberately retain missing facts.
class SmartFollowCompletionResult {
  const SmartFollowCompletionResult({required this.session, this.recognition, this.recognitionReport, this.children = const [], this.issues = const [], this.historyComplete = false, this.reportsComplete = false});
  final SmartFollowSession session;
  final BirdJobStatus? recognition;
  final JobReport? recognitionReport;
  final List<SmartFollowCompletionChild> children;
  final List<String> issues;
  final bool historyComplete;
  final bool reportsComplete;

  int? sessionCount(String key) {
    final value = session.raw[key];
    return value is int && value >= 0 ? value : null;
  }

  int? sum(int? Function(SmartFollowCompletionChild child) read) {
    if (!reportsComplete) return null;
    var total = 0;
    for (final child in children) {
      final value = read(child);
      if (value == null || value < 0) return null;
      total += value;
    }
    return total;
  }

  int? get copiedFiles => sum((c) => c.report?.copiedFiles);
  int? get skippedFiles => sum((c) => c.report?.skippedFiles);
  int? get failedFiles => sum((c) => c.report?.failedFiles);
  int? get notApplicableFiles => sum((c) => c.report?.notApplicableFiles);
  int? get copiedBytes => sum((c) => c.detail?.stats?.copiedBytesKnown == true ? c.detail!.stats!.copiedBytes : null);

  bool get summaryComplete =>
      reportsComplete &&
      issues.isEmpty &&
      ['eligible_count', 'copied_asset_count', 'copied_file_count', 'failed_asset_count'].every((key) => sessionCount(key) != null) &&
      copiedFiles != null &&
      skippedFiles != null &&
      failedFiles != null &&
      notApplicableFiles != null &&
      copiedBytes != null;

  bool get metadataFailure => children.any((c) => c.report?.csvStatus == 'failed' || (c.report?.exportFailedCount ?? 0) > 0);
  String get informationStatus {
    if (!reportsComplete) return '报告待补齐';
    if (children.isEmpty) return '无复制批次';
    if (metadataFailure) return '部分批次信息保存异常，请查看批次详情';
    if (children.any((c) => (c.report?.embedDegradedCount ?? 0) > 0)) return '部分文件使用配套 XMP 保存信息；不代表照片复制失败，请保留配套文件';
    if (children.every((c) => c.detail?.reviewExportEnabled == false)) return '所有批次均未开启识别信息保存';
    return '请查看各批次保存结果；未提供的字段无法确认';
  }

  String get title {
    if (!session.isFinished) return '仍在处理';
    if (session.state == SmartFollowState.failed) return '跟随复制失败';
    if (session.state == SmartFollowState.completedPartial ||
        metadataFailure ||
        children.any((c) => c.detail != null && c.detail!.state.isTerminal && c.detail!.state != CopyJobState.completed) ||
        (failedFiles ?? 0) > 0 ||
        (sessionCount('failed_asset_count') ?? 0) > 0) {
      return '跟随复制部分完成';
    }
    return summaryComplete ? '跟随复制已完成' : '复制流程已结束，报告待补齐';
  }
}

class SmartFollowCompletionController extends ChangeNotifier {
  SmartFollowCompletionController({required this.repository, required this.sessionId, required this.readChild, required this.readCopyReport, required this.readRecognition, required this.readRecognitionReport, this.isCurrent})
    : _deviceGeneration = repository.deviceGeneration;
  final SmartFollowRepository repository;
  final String sessionId;
  final Future<CopyJobDetail> Function(String) readChild;
  final Future<CopyReport> Function(String) readCopyReport;
  final Future<BirdJobStatus> Function(String) readRecognition;
  final Future<JobReport> Function(String) readRecognitionReport;
  final bool Function()? isCurrent;
  final int _deviceGeneration;
  SmartFollowCompletionResult? result;
  String? error;
  bool busy = false;
  bool _disposed = false;
  Future<void>? _loading;

  Future<void> refresh() => _loading ??= _load().whenComplete(() => _loading = null);

  void _check(int generation) {
    if (_disposed || repository.deviceGeneration != generation || !(isCurrent?.call() ?? true)) throw StateError('盒子连接已变化，请重新打开原任务');
  }

  Future<void> _load() async {
    if (_disposed) return;
    busy = true;
    error = null;
    result = null;
    notifyListeners();
    final generation = _deviceGeneration;
    try {
      _check(generation);
      final session = await repository.refresh(sessionId);
      _check(generation);
      if (!session.isFinished) {
        result = SmartFollowCompletionResult(session: session);
        return;
      }
      final issues = <String>[];
      BirdJobStatus? recognition;
      JobReport? recognitionReport;
      try {
        final job = await readRecognition(session.recognitionJobId);
        _check(generation);
        if (job.id != session.recognitionJobId || job.type != BirdJobType.analysis || (job.smartFollowSessionId != null && job.smartFollowSessionId != sessionId)) throw StateError('识别任务不匹配');
        recognition = job;
        if ({BirdJobState.completed, BirdJobState.failed, BirdJobState.cancelled}.contains(job.state)) {
          final report = await readRecognitionReport(job.id);
          _check(generation);
          if (report.jobId != job.id) throw StateError('识别报告不匹配');
          recognitionReport = report;
        }
      } catch (_) {
        _check(generation);
        issues.add('识别结果暂不可用，请刷新重试');
      }
      final jobs = <String, SmartFollowChildJob>{};
      var historyComplete = false;
      try {
        String? cursor;
        final cursors = <String>{};
        do {
          final page = await repository.childJobs(sessionId, cursor: cursor);
          _check(generation);
          for (final item in page.items) {
            final previous = jobs[item.copyJobId];
            if (previous != null &&
                (previous.state != item.state ||
                    previous.assetCount != item.assetCount ||
                    previous.fileCount != item.fileCount ||
                    previous.totalBytes != item.totalBytes ||
                    previous.copiedFileCount != item.copiedFileCount ||
                    previous.skippedFileCount != item.skippedFileCount ||
                    previous.failedFileCount != item.failedFileCount)) {
              throw StateError('重复批次的内容不一致');
            }
            jobs[item.copyJobId] = item;
          }
          if (!page.paginationValid) throw StateError('批次分页元数据未完整返回');
          if (!page.hasMore) {
            historyComplete = true;
            break;
          }
          cursor = page.nextCursor;
          if (cursor == null || cursor.isEmpty || !cursors.add(cursor) || cursors.length > 10000) throw StateError('批次分页未完整返回');
        } while (true);
      } catch (_) {
        _check(generation);
        issues.add('复制批次列表未读完整，报告待补齐');
      }
      final rawChildCount = session.raw['child_job_count'];
      if (rawChildCount is! int || rawChildCount < 0 || rawChildCount != jobs.length) {
        historyComplete = false;
        issues.add('批次数量未提供或与会话不一致，报告待核对');
      }
      final children = <SmartFollowCompletionChild>[];
      // Bounded requests; each batch keeps its own report failure and history.
      final values = jobs.values.toList();
      for (var offset = 0; offset < values.length; offset += 4) {
        final group = values.skip(offset).take(4).map((job) async {
          CopyJobDetail? detail;
          try {
            _check(generation);
            detail = await readChild(job.copyJobId);
            _check(generation);
            if (detail.copyJobId != job.copyJobId || (detail.targetDevice?.mediaId != null && session.targetMediaId != null && detail.targetDevice!.mediaId != session.targetMediaId)) throw StateError('复制任务不匹配');
            if (!job.state.isTerminal || !detail.state.isTerminal) return SmartFollowCompletionChild(job, detail: detail, issue: '复制批次仍在处理，尚无最终报告');
            if (job.state != detail.state) throw StateError('批次状态不一致');
            final report = await readCopyReport(job.copyJobId);
            _check(generation);
            if (report.copyJobId != job.copyJobId || (report.targetDevice?.mediaId != null && session.targetMediaId != null && report.targetDevice!.mediaId != session.targetMediaId)) throw StateError('复制报告不匹配');
            final stats = detail.stats;
            if (stats != null) {
              final pairs = {
                'copied_files': (stats.copiedFiles, report.copiedFiles),
                'failed_files': (stats.failedFiles, report.failedFiles),
                'skipped_files': (stats.skippedFiles, report.skippedFiles),
                'not_applicable_files': (stats.notApplicableFiles, report.notApplicableFiles),
              };
              for (final entry in pairs.entries) {
                if (stats.knownFileCounts.contains(entry.key) && entry.value.$2 != null && entry.value.$1 != entry.value.$2) throw StateError('复制报告统计不一致');
              }
            }
            return SmartFollowCompletionChild(job, detail: detail, report: report);
          } catch (_) {
            _check(generation);
            return SmartFollowCompletionChild(job, detail: detail?.copyJobId == job.copyJobId ? detail : null, issue: '批次报告暂不可用或不一致，请重试');
          }
        });
        children.addAll(await Future.wait(group));
        _check(generation);
      }
      final latest = await repository.refresh(sessionId);
      _check(generation);
      // Compare the scalar fields consumed by C1; nested JSON objects are not
      // referentially equal across two ordinary HTTP reads.
      const resultKeys = [
        'state',
        'recognition_job_id',
        'target_media_id',
        'eligible_count',
        'copied_asset_count',
        'copied_file_count',
        'failed_asset_count',
        'recognition_pending_confirmation_count',
        'overwritten_file_count',
        'child_job_count',
        'metadata_update_available',
        'active_metadata_update_id',
        'error_code',
        'error_message',
      ];
      if (latest.stateVersion != session.stateVersion || resultKeys.any((key) => latest.raw[key] != session.raw[key])) throw StateError('会话结果已变化，请刷新后查看');
      var reportsComplete = historyComplete && children.every((child) => child.report != null && child.issue == null);
      if (children.isEmpty && (session.raw['copied_file_count'] != 0 || session.raw['copied_asset_count'] != 0)) reportsComplete = false;
      var projection = SmartFollowCompletionResult(
        session: session,
        recognition: recognition,
        recognitionReport: recognitionReport,
        children: List.unmodifiable(children),
        issues: issues,
        historyComplete: historyComplete,
        reportsComplete: reportsComplete,
      );
      final eligible = projection.sessionCount('eligible_count');
      final copiedPhotos = projection.sessionCount('copied_asset_count');
      if (eligible != null && copiedPhotos != null && copiedPhotos > eligible) {
        issues.add('已复制照片数超过符合条件照片数，报告待核对');
        reportsComplete = false;
      }
      if (projection.copiedFiles != null && projection.sessionCount('copied_file_count') != null && projection.copiedFiles != projection.sessionCount('copied_file_count')) {
        issues.add('会话与批次的已复制文件数不一致，报告待核对');
        reportsComplete = false;
      }
      projection = SmartFollowCompletionResult(
        session: session,
        recognition: recognition,
        recognitionReport: recognitionReport,
        children: List.unmodifiable(children),
        issues: List.unmodifiable(issues),
        historyComplete: historyComplete,
        reportsComplete: reportsComplete,
      );
      result = projection;
    } catch (_) {
      if (!_disposed) error = (isCurrent?.call() ?? true) && repository.deviceGeneration == generation ? '结果暂时无法确认，请刷新重试' : '盒子连接已变化，请重新打开原任务';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
