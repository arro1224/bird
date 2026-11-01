import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_controller.dart';

class CompletionBackend extends FakeSmartFollowBackend {
  CompletionBackend() {
    data = {...current.raw, 'state': 'completed', 'eligible_count': 1, 'copied_asset_count': 1, 'copied_file_count': 2, 'child_job_count': 1};
    pages = {
      null: SmartFollowChildJobPage(items: [child('copy-1')], hasMore: false),
    };
  }
  late Map<String, dynamic> data;
  late Map<String?, SmartFollowChildJobPage> pages;
  final List<String?> cursors = [];
  bool failSecondPage = false;
  int reads = 0;
  bool changeAtEnd = false;

  @override
  Future<SmartFollowSession> session(String sessionId) async {
    ++reads;
    return SmartFollowSession.fromJson({...data, if (changeAtEnd && reads > 1) 'state_version': 999, 'allowed_actions': <String>[]});
  }

  @override
  Future<SmartFollowChildJobPage> childJobs(String sessionId, {String? cursor, int pageSize = 50}) async {
    cursors.add(cursor);
    if (failSecondPage && cursor != null) throw StateError('offline');
    return pages[cursor]!;
  }

  static SmartFollowChildJob child(String id, {String state = 'completed', int copied = 2}) =>
      SmartFollowChildJob.fromJson({'copy_job_id': id, 'state': state, 'asset_count': 1, 'file_count': copied, 'total_bytes': 999999, 'copied_file_count': copied, 'skipped_file_count': 0, 'failed_file_count': 0});
}

class CompletionEnvironment {
  CompletionEnvironment() {
    repository = SmartFollowRepository(backend);
    controller = SmartFollowCompletionController(
      repository: repository,
      sessionId: 'sf_fake',
      isCurrent: () => current,
      readChild: (id) async {
        childReads.add(id);
        if (gate != null) await gate!.future;
        return CopyJobDetail.fromJson({...detail, 'copy_job_id': wrongChild ? 'wrong' : id});
      },
      readCopyReport: (id) async {
        reportReads.add(id);
        if (reportUnavailable) throw StateError('report not ready');
        return CopyReport.fromJson({...report, 'copy_job_id': wrongReport ? 'wrong' : id});
      },
      readRecognition: (id) async => BirdJobStatus(id: wrongRecognition ? 'wrong' : id, type: BirdJobType.analysis, state: recognitionState, totalCount: 5, finishedCount: 5),
      readRecognitionReport: (id) async {
        ++recognitionReportReads;
        if (recognitionReportUnavailable) throw StateError('offline');
        return JobReport(jobId: id, result: JobReportResult.success, totalCount: 5, successCount: 3, failedCount: 1, skippedCount: 1);
      },
    );
  }
  final backend = CompletionBackend();
  late final SmartFollowRepository repository;
  late final SmartFollowCompletionController controller;
  bool current = true, reportUnavailable = false, wrongReport = false, wrongChild = false, wrongRecognition = false, recognitionReportUnavailable = false;
  BirdJobState recognitionState = BirdJobState.completed;
  int recognitionReportReads = 0;
  final childReads = <String>[];
  final reportReads = <String>[];
  Completer<void>? gate;
  Map<String, dynamic> detail = {
    'state': 'completed',
    'state_version': 1,
    'event_seq': 1,
    'stats': {'total_files': 2, 'copied_files': 2, 'skipped_files': 0, 'failed_files': 0, 'not_applicable_files': 0, 'total_bytes': 999999, 'copied_bytes': 128},
    'review_export': {'enabled': true},
  };
  Map<String, dynamic> report = {
    'copied_files': 2,
    'skipped_files': 0,
    'failed_files': 0,
    'not_applicable_files': 0,
    'total_bytes': 999999,
    'csv_status': 'success',
    'xmp_count': 1,
    'embed_success_count': 1,
    'embed_degraded_count': 0,
    'export_failed_count': 0,
  };
  void dispose() {
    controller.dispose();
    repository.dispose();
  }
}
