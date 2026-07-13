import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('task control refreshes the displayed task and prevents a second concurrent request', () async {
    final repository = _Jobs();
    final cubit = JobDetailCubit(repository, EventClient(), 'job-1');
    await cubit.load();

    final first = cubit.control('pause');
    final second = cubit.control('pause');
    await Future.wait([first, second]);

    expect(repository.controlCalls, 1);
    expect(cubit.state.job?.state, BirdJobState.paused);
    await cubit.close();
  });
}

class _Jobs implements JobRepository {
  var controlCalls = 0;
  var state = BirdJobState.running;

  @override
  Future<void> control(String id, String action) async {
    controlCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    state = action == 'pause' ? BirdJobState.paused : BirdJobState.running;
  }

  @override
  Future<void> delete(String id) async => state = BirdJobState.cancelled;

  @override
  Future<BirdJobStatus> detail(String id) async => BirdJobStatus(id: id, type: BirdJobType.copy, state: state, totalCount: 2, finishedCount: 1);

  @override
  Future<String?> exportLogs() async => null;

  @override
  Future<List<JobFailure>> failures(String jobId) async => const [];

  @override
  Future<List<BirdJobStatus>> list() async => [await detail('job-1')];
}
