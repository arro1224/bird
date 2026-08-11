import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the source project used by task-result gallery navigation', () {
    final job = BirdJobStatus.fromJson(const {
      'job_id': 'job-copy-7',
      'job_type': 'copy',
      'job_state': 'completed',
      'source_project_id': 'project-7',
      'source_project_name': '河岸翠鸟',
      'progress': 1.0,
      'total_count': 20,
      'finished_count': 20,
      'failed_count': 0,
      'skipped_count': 0,
      'available_actions': <String>[],
    });

    expect(job.sourceProjectId, 'project-7');
    expect(job.sourceProjectName, '河岸翠鸟');
  });

  test('maps queued directly and uses v1 actions and remaining time', () {
    const job = BirdJobStatus(
      id: 'job-queued-1',
      type: BirdJobType.analysis,
      state: BirdJobState.queued,
      estimatedRemainingSeconds: 121,
      availableActions: ['resume', 'cancel'],
    );

    final task = JobStatusViewAdapter.toTaskSummary(job)!;

    expect(task.state, TaskRunState.queued);
    expect(task.remainingMinutes, 3);
    expect(task.availableActions, {
      TaskAction.resume,
      TaskAction.cancel,
      TaskAction.exportLog,
    });
  });

  test('reports legacy idle compatibility mapping', () {
    BirdJobState? reported;
    JobStatusViewAdapter.legacyStateReporter = (state) => reported = state;
    addTearDown(() => JobStatusViewAdapter.legacyStateReporter = null);

    const job = BirdJobStatus(
      id: 'job-idle-1',
      type: BirdJobType.copy,
      state: BirdJobState.idle,
    );
    final task = JobStatusViewAdapter.toTaskSummary(job)!;

    expect(task.state, TaskRunState.queued);
    expect(reported, BirdJobState.idle);
  });

  test('maps the production job contract into task presentation data', () {
    const job = BirdJobStatus(
      id: 'job-copy-7',
      type: BirdJobType.copy,
      state: BirdJobState.failed,
      progress: .75,
      totalCount: 200,
      finishedCount: 150,
      failedCount: 3,
      currentFile: 'DSC_0151.NEF',
      speedBytesPerSecond: 12582912,
      errorMessage: '目标盘已断开',
      availableActions: ['retry_failed', 'skip_failed'],
    );

    final task = JobStatusViewAdapter.toTaskSummary(
      job,
      sourceBatch: '河岸翠鸟',
      connectionState: TaskConnectionState.disconnected,
      remainingMinutes: 6,
    );

    expect(task, isNotNull);
    expect(task!.type, TaskType.copy);
    expect(task.state, TaskRunState.failed);
    expect(task.progressPercent, 75);
    expect(task.sourceBatch, '河岸翠鸟');
    expect(task.currentFile, 'DSC_0151.NEF');
    expect(task.speed, '12.0 MB/s');
    expect(task.failureReason, '目标盘已断开');
    expect(task.availableActions, containsAll([TaskAction.retry, TaskAction.skipFailed, TaskAction.exportLog]));
  });

  test('does not infer write actions when available_actions is empty', () {
    const job = BirdJobStatus(
      id: 'job-running-without-actions',
      type: BirdJobType.copy,
      state: BirdJobState.running,
    );

    final task = JobStatusViewAdapter.toTaskSummary(job)!;

    expect(task.availableActions, const {TaskAction.exportLog});
  });

  test('ignores unknown production task types', () {
    const job = BirdJobStatus(id: 'unknown', type: BirdJobType.unknown, state: BirdJobState.running);

    expect(JobStatusViewAdapter.toTaskSummary(job), isNull);
  });
}
