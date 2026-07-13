import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';

class JobApi {
  JobApi(this._c);
  final ApiClient _c;
  Future<List<BirdJobStatus>> list() async {
    final d = await _c.get(ApiEndpoints.jobs);
    return (d['items'] as List? ?? const []).whereType<Map>().map((x) => BirdJobStatus.fromJson(Map<String, dynamic>.from(x))).toList();
  }

  Future<BirdJobStatus> detail(String id) => _c.get(ApiEndpoints.jobDetail.replaceFirst('{jobId}', id)).then(BirdJobStatus.fromJson);
  Future<void> control(String id, String a) => _c.post(ApiEndpoints.taskControl.replaceFirst('{jobId}', id), data: {'action': a});
  Future<void> delete(String id) => _c.delete(ApiEndpoints.jobDelete.replaceFirst('{jobId}', id));
  Future<String?> exportLogs() async => (await _c.post(ApiEndpoints.logExport))['download_url']?.toString();
  Future<List<JobFailure>> failures(String jobId) async {
    final data = await _c.get(ApiEndpoints.jobFailures.replaceFirst('{jobId}', jobId));
    return (data['items'] as List? ?? const []).whereType<Map>().map((item) => JobFailure.fromJson(Map<String, dynamic>.from(item))).toList();
  }
}
