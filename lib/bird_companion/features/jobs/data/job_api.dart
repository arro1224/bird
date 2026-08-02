import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';

class JobApi {
  JobApi(this._c);
  final ApiClient _c;
  Future<List<BirdJobStatus>> list() async {
    final d = await _c.get(ApiEndpoints.jobs);
    return (d['items'] as List? ?? const []).whereType<Map>().map((x) => BirdJobStatus.fromJson(Map<String, dynamic>.from(x))).toList();
  }

  Future<BirdJobStatus> detail(String id) => _c.get(ApiEndpoints.jobDetail.replaceFirst('{jobId}', id)).then(BirdJobStatus.fromJson);
  Future<BirdJobStatus> createImport(
    String projectId,
    ImportJobRequest request,
  ) => _c
      .post(
        ApiEndpoints.projectImports.replaceFirst('{projectId}', projectId),
        data: request.toJson(),
      )
      .then(BirdJobStatus.fromJson);

  Future<BirdJobStatus> createAnalysis(
    String projectId,
    AnalysisJobRequest request,
  ) => _c
      .post(
        ApiEndpoints.projectAnalysisJobs.replaceFirst(
          '{projectId}',
          projectId,
        ),
        data: request.toJson(),
      )
      .then(BirdJobStatus.fromJson);

  Future<BirdJobStatus> control(
    String id,
    String action, {
    required int version,
  }) => _c
      .post(
        ApiEndpoints.taskControl.replaceFirst('{jobId}', id),
        data: {'action': action, 'version': version},
      )
      .then(BirdJobStatus.fromJson);

  Future<JobReport> report(String id) => _c.get(ApiEndpoints.jobReport.replaceFirst('{jobId}', id)).then(JobReport.fromJson);
  Future<void> delete(String id) => _c.delete(ApiEndpoints.jobDelete.replaceFirst('{jobId}', id));
  Future<String?> exportLogs({
    String scope = 'device_and_jobs',
    String? jobId,
  }) async => (await _c.post(
    ApiEndpoints.logExport,
    data: {
      'scope': scope,
      'job_id': ?jobId,
    },
  ))['download_url']?.toString();
  Future<List<JobFailure>> failures(String jobId) async {
    final data = await _c.get(ApiEndpoints.jobFailures.replaceFirst('{jobId}', jobId));
    return (data['items'] as List? ?? const []).whereType<Map>().map((item) => JobFailure.fromJson(Map<String, dynamic>.from(item))).toList();
  }
}
