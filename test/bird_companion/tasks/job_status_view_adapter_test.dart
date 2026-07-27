import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('ignores unknown production task types', () {
    const job = BirdJobStatus(id: 'unknown', type: BirdJobType.unknown, state: BirdJobState.running);

    expect(JobStatusViewAdapter.toTaskSummary(job), isNull);
  });
}
