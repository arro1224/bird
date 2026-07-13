import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';

abstract interface class JobRepository {
  Future<List<BirdJobStatus>> list();
  Future<BirdJobStatus> detail(String id);
  Future<void> control(String id, String action);
  Future<void> delete(String id);
  Future<String?> exportLogs();
  Future<List<JobFailure>> failures(String jobId);
}
