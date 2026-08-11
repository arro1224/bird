import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';

abstract interface class JobRepository {
  Future<List<BirdJobStatus>> list();
  Future<JobPage> page({String? cursor, int pageSize = 50, String? state, String? type});
  Future<BirdJobStatus> detail(String id);
  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  );
  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  );
  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  });
  Future<JobReport> report(String id);
  Future<void> delete(String id);
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  });
  Future<List<JobFailure>> failures(String jobId);
  Future<JobFailurePage> failurePage(String jobId, {String? cursor, int pageSize = 50});
}
