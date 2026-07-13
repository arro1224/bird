import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';

class JobRepositoryImpl implements JobRepository {
  JobRepositoryImpl(this._a);
  final JobApi _a;
  @override
  Future<List<BirdJobStatus>> list() => _a.list();
  @override
  Future<BirdJobStatus> detail(String id) => _a.detail(id);
  @override
  Future<void> control(String i, String a) => _a.control(i, a);
  @override
  Future<void> delete(String id) => _a.delete(id);
  @override
  Future<String?> exportLogs() => _a.exportLogs();
  @override
  Future<List<JobFailure>> failures(String jobId) => _a.failures(jobId);
}
