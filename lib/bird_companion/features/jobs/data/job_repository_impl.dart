import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';

class JobRepositoryImpl implements JobRepository {
  JobRepositoryImpl(this._a);
  final JobApi _a;
  @override
  Future<List<BirdJobStatus>> list() => _a.list();
  @override
  Future<BirdJobStatus> detail(String id) => _a.detail(id);
  @override
  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  ) => _a.createImport(projectId, request);
  @override
  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  ) => _a.createAnalysis(projectId, request);
  @override
  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  }) => _a.control(id, action, version: version);
  @override
  Future<JobReport> report(String id) => _a.report(id);
  @override
  Future<void> delete(String id) => _a.delete(id);
  @override
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  }) => _a.exportLogs(scope: scope, jobId: jobId);
  @override
  Future<List<JobFailure>> failures(String jobId) => _a.failures(jobId);
}
