import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskExperienceController', () {
    late TaskExperienceController controller;

    setUp(() {
      controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      );
    });

    tearDown(() => controller.dispose());

    test('provides deterministic fixtures for every P0 task type', () {
      expect(
        controller.tasks.map((task) => task.type),
        [
          TaskType.importIndex,
          TaskType.aiAnalysis,
          TaskType.copy,
          TaskType.sync,
        ],
      );
      expect(
        controller.tasks.map((task) => task.type.label),
        ['导入/索引', 'AI分析', '复制', '同步'],
      );
      expect(
        controller.tasks.map((task) => task.state),
        [
          TaskRunState.running,
          TaskRunState.paused,
          TaskRunState.failed,
          TaskRunState.completed,
        ],
      );
    });

    test('groups active, attention, and completed task records', () {
      expect(
        controller.tasksFor(TaskGroup.active).map((task) => task.type),
        [TaskType.importIndex],
      );
      expect(
        controller.tasksFor(TaskGroup.attention).map((task) => task.type),
        [TaskType.aiAnalysis, TaskType.copy],
      );
      expect(
        controller.tasksFor(TaskGroup.completed).map((task) => task.type),
        [TaskType.sync],
      );

      controller.selectGroup(TaskGroup.attention);

      expect(controller.selectedGroup, TaskGroup.attention);
      expect(controller.visibleTasks.length, 2);
    });

    test('current task exposes optional operational presentation fields', () {
      final task = controller.currentTask;

      expect(task.sourceBatch, '崇明东滩 7月16日');
      expect(task.currentFile, 'DSC_2384.ARW');
      expect(task.speed, '42 MB/s');
      expect(task.failedCount, 0);
      expect(task.connectionState, TaskConnectionState.connected);
      expect(task.reviewedCount, 2384);
      expect(task.pendingReviewCount, 1288);
    });

    test('failed copy retains failure context while disconnected', () {
      final copyTask = controller.tasks.singleWhere(
        (task) => task.type == TaskType.copy,
      );

      expect(copyTask.failedCount, 3);
      expect(copyTask.failureReason, '目标硬盘连接中断');
      expect(copyTask.connectionState, TaskConnectionState.disconnected);
      expect(
        copyTask.availableActions,
        containsAll([
          TaskAction.retry,
          TaskAction.skipFailed,
          TaskAction.exportLog,
        ]),
      );
    });

    test('skipping failed items completes copy while preserving skip context', () {
      const copyId = 'demo-copy-failed';
      final failureReason = controller.taskById(copyId).failureReason;

      controller.performAction(copyId, TaskAction.skipFailed);

      final copyTask = controller.taskById(copyId);
      expect(copyTask.state, TaskRunState.completed);
      expect(copyTask.processed, 2009);
      expect(copyTask.total, 2012);
      expect(copyTask.progressPercent, 100);
      expect(copyTask.remainingMinutes, 0);
      expect(copyTask.failedCount, 3);
      expect(copyTask.failureReason, failureReason);
      expect(copyTask.availableActions, const {TaskAction.exportLog});
    });

    test('maps pause, resume, cancel, retry, skip, and log intents', () {
      const importId = 'demo-import-running';
      const analysisId = 'demo-analysis-paused';
      const copyId = 'demo-copy-failed';

      controller.performAction(importId, TaskAction.pause);
      expect(controller.taskById(importId).state, TaskRunState.paused);
      expect(controller.lastIntent, const TaskControlIntent(importId, TaskAction.pause));

      controller.performAction(analysisId, TaskAction.resume);
      expect(controller.taskById(analysisId).state, TaskRunState.running);

      controller.performAction(analysisId, TaskAction.cancel);
      expect(controller.taskById(analysisId).state, TaskRunState.cancelled);

      controller.performAction(copyId, TaskAction.retry);
      expect(controller.taskById(copyId).state, TaskRunState.running);

      controller.resetDemo();
      controller.performAction(copyId, TaskAction.skipFailed);
      expect(controller.lastIntent, const TaskControlIntent(copyId, TaskAction.skipFailed));

      controller.performAction(copyId, TaskAction.exportLog);
      expect(controller.lastIntent, const TaskControlIntent(copyId, TaskAction.exportLog));
    });

    test('retrying and completing failed copy clears stale failure fields', () {
      const copyId = 'demo-copy-failed';

      controller.startTask(copyId);

      expect(controller.taskById(copyId).state, TaskRunState.running);
      expect(controller.taskById(copyId).failureReason, isNull);
      expect(controller.taskById(copyId).failedCount, 0);

      controller.completeTask(copyId);

      expect(controller.taskById(copyId).state, TaskRunState.completed);
      expect(controller.taskById(copyId).failureReason, isNull);
      expect(controller.taskById(copyId).failedCount, 0);
    });

    test('uses the approved keep-photo copy estimate by default', () {
      expect(controller.copyMode, CopyMode.keep);
      expect(controller.copyEstimate.photoCount, 2012);
      expect(controller.copyEstimate.spaceGb, 238.7);
      expect(controller.copyEstimate.targetName, 'Samsung T7 Shield');
      expect(controller.generateXmp, isTrue);
    });

    test('legacy current-task controls preserve progress', () {
      controller.pauseOrResume();

      expect(controller.currentTask.state, TaskRunState.paused);
      expect(controller.currentTask.processed, 2384);

      controller.pauseOrResume();

      expect(controller.currentTask.state, TaskRunState.running);
      expect(controller.currentTask.processed, 2384);
    });

    test('copy selections update estimates and reset restores fixtures', () {
      controller.selectCopyMode(CopyMode.all);
      controller.setGenerateXmp(false);
      controller.setSdState(SdCardReadState.readFailed);
      controller.selectGroup(TaskGroup.completed);

      expect(controller.copyEstimate.photoCount, 3672);
      expect(controller.generateXmp, isFalse);
      expect(controller.sdCard.state, SdCardReadState.readFailed);

      controller.resetDemo();

      expect(controller.copyMode, CopyMode.keep);
      expect(controller.copyEstimate.photoCount, 2012);
      expect(controller.generateXmp, isTrue);
      expect(controller.sdCard.state, SdCardReadState.detected);
      expect(controller.selectedGroup, TaskGroup.active);
    });

    test('starting an import creates a deterministic active batch task', () {
      final batchId = controller.startImportBatch('河岸翠鸟 0725');

      expect(batchId, 'demo-batch-20260716');
      expect(controller.activeBatchId, batchId);
      expect(controller.currentTask.type, TaskType.importIndex);
      expect(controller.currentTask.sourceBatch, '河岸翠鸟 0725');
      expect(controller.currentTask.processed, 0);
      expect(controller.currentTask.progressPercent, 0);
      expect(controller.currentTask.state, TaskRunState.running);
    });

    test('completing import prepares same-batch AI analysis without completing copy', () {
      controller.startImportBatch('河岸翠鸟 0725');

      controller.completeTask();

      final importTask = controller.taskById('demo-import-running');
      final analysisTask = controller.taskById('demo-analysis-paused');
      final copyTask = controller.taskById('demo-copy-failed');
      expect(importTask.state, TaskRunState.completed);
      expect(importTask.progressPercent, 100);
      expect(analysisTask.state, TaskRunState.queued);
      expect(analysisTask.sourceBatch, '河岸翠鸟 0725');
      expect(analysisTask.availableActions, contains(TaskAction.resume));
      expect(copyTask.state, isNot(TaskRunState.completed));
    });

    test('current task advances through queued work and no-arg completion targets it', () {
      controller.startImportBatch('河岸翠鸟 0725');
      controller.completeTask();

      expect(controller.currentTask.id, 'demo-analysis-paused');
      expect(controller.currentTask.state, TaskRunState.queued);

      controller.completeTask();

      expect(controller.taskById('demo-analysis-paused').state, TaskRunState.completed);
      expect(controller.currentTask.id, 'demo-copy-failed');
      expect(controller.currentTask.state, TaskRunState.queued);
    });

    test('explicit current task follows commands, workflow stages, and reset', () {
      expect(controller.currentTask.id, 'demo-import-running');

      controller.startTask('demo-analysis-paused');
      expect(controller.currentTask.id, 'demo-analysis-paused');

      controller.resetDemo();
      controller.startTask('demo-copy-failed');
      expect(controller.currentTask.id, 'demo-copy-failed');

      controller.resetDemo();
      controller.startImportBatch('河岸翠鸟 0725');
      expect(controller.currentTask.id, 'demo-import-running');
      controller.completeTask();
      expect(controller.currentTask.id, 'demo-analysis-paused');
      controller.startTask(controller.currentTask.id);
      controller.completeTask();
      expect(controller.currentTask.id, 'demo-copy-failed');
      controller.startTask(controller.currentTask.id);
      controller.completeTask();
      expect(controller.currentTask.id, 'demo-copy-failed');
      expect(controller.currentTask.state, TaskRunState.completed);

      controller.resetDemo();
      expect(controller.currentTask.id, 'demo-import-running');
      expect(controller.currentTask.state, TaskRunState.running);
    });

    test('terminal actions prefer concurrent active work and retain final copy', () {
      const importId = 'demo-import-running';
      const analysisId = 'demo-analysis-paused';
      const copyId = 'demo-copy-failed';

      controller.performAction(analysisId, TaskAction.cancel);
      expect(controller.currentTask.id, importId);

      controller.resetDemo();
      controller.performAction(copyId, TaskAction.skipFailed);
      expect(controller.currentTask.id, importId);

      controller.resetDemo();
      controller.completeTask(copyId);
      expect(controller.currentTask.id, importId);

      controller.startImportBatch('current task workflow');
      controller.completeTask();
      controller.startTask(analysisId);
      controller.completeTask();
      controller.startTask(copyId);
      controller.completeTask();

      expect(controller.currentTask.id, copyId);
      expect(controller.currentTask.state, TaskRunState.completed);
    });

    test('starting and completing AI analysis prepares same-batch copy', () {
      controller.startImportBatch('河岸翠鸟 0725');
      controller.completeTask();

      controller.startTask('demo-analysis-paused');

      expect(controller.taskById('demo-analysis-paused').state, TaskRunState.running);
      controller.completeTask('demo-analysis-paused');
      final analysisTask = controller.taskById('demo-analysis-paused');
      final copyTask = controller.taskById('demo-copy-failed');
      expect(analysisTask.state, TaskRunState.completed);
      expect(analysisTask.progressPercent, 100);
      expect(copyTask.state, TaskRunState.queued);
      expect(copyTask.sourceBatch, '河岸翠鸟 0725');
      expect(copyTask.availableActions, contains(TaskAction.resume));
    });

    test('same-batch copy starts connected and completes without stale failure context', () {
      controller.startImportBatch('河岸翠鸟 0725');
      controller.completeTask();
      controller.startTask('demo-analysis-paused');
      controller.completeTask('demo-analysis-paused');

      controller.startTask('demo-copy-failed');

      final runningCopy = controller.taskById('demo-copy-failed');
      expect(runningCopy.state, TaskRunState.running);
      expect(runningCopy.sourceBatch, '河岸翠鸟 0725');
      expect(runningCopy.connectionState, TaskConnectionState.connected);
      expect(runningCopy.failureReason, isNull);

      controller.completeTask('demo-copy-failed');
      final completedCopy = controller.taskById('demo-copy-failed');
      expect(completedCopy.state, TaskRunState.completed);
      expect(completedCopy.progressPercent, 100);
    });

    test('starting a second import resets downstream demo stages before advancing', () {
      controller.startImportBatch('第一轮批次');
      controller.completeTask();
      controller.startTask('demo-analysis-paused');
      controller.completeTask('demo-analysis-paused');
      controller.startTask('demo-copy-failed');

      controller.startImportBatch('第二轮批次');

      final restartedImport = controller.taskById('demo-import-running');
      final resetAnalysis = controller.taskById('demo-analysis-paused');
      final resetCopy = controller.taskById('demo-copy-failed');
      expect(restartedImport.state, TaskRunState.running);
      expect(restartedImport.sourceBatch, '第二轮批次');
      expect(resetAnalysis.state, isNot(anyOf(TaskRunState.running, TaskRunState.completed, TaskRunState.queued)));
      expect(resetCopy.state, isNot(anyOf(TaskRunState.running, TaskRunState.completed, TaskRunState.queued)));

      controller.completeTask();

      expect(controller.taskById('demo-import-running').state, TaskRunState.completed);
      expect(controller.taskById('demo-analysis-paused').state, TaskRunState.queued);
      expect(controller.taskById('demo-analysis-paused').sourceBatch, '第二轮批次');
    });

    test('workflow resolves required tasks by type instead of demo ids', () {
      final customController = TaskExperienceController(
        _TestTaskExperienceDataSource([
          _task('custom-import', TaskType.importIndex, TaskRunState.running),
          _task('custom-analysis', TaskType.aiAnalysis, TaskRunState.paused),
          _task('custom-copy', TaskType.copy, TaskRunState.failed),
          _task('custom-sync', TaskType.sync, TaskRunState.completed),
        ]),
      );
      addTearDown(customController.dispose);

      customController.startImportBatch('自定义 ID 批次');
      customController.completeTask();
      expect(customController.currentTask.id, 'custom-analysis');
      customController.startTask(customController.currentTask.id);
      customController.completeTask();
      expect(customController.currentTask.id, 'custom-copy');
    });

    test('missing required task type throws a clear StateError', () {
      final incompleteController = TaskExperienceController(
        _TestTaskExperienceDataSource([
          _task('custom-import', TaskType.importIndex, TaskRunState.running),
          _task('custom-copy', TaskType.copy, TaskRunState.failed),
          _task('custom-sync', TaskType.sync, TaskRunState.completed),
        ]),
      );
      addTearDown(incompleteController.dispose);

      expect(
        () => incompleteController.startImportBatch('缺少分析任务'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('aiAnalysis'),
          ),
        ),
      );
    });

    test('empty initial tasks support repository-backed production startup', () {
      final emptyController = TaskExperienceController(
        const _TestTaskExperienceDataSource([]),
      );
      addTearDown(emptyController.dispose);

      expect(emptyController.tasks, isEmpty);
      expect(emptyController.currentTaskOrNull, isNull);
      expect(() => emptyController.currentTask, throwsStateError);
    });

    test('repository task replacement rejects demo identifiers', () {
      final productionController = TaskExperienceController(
        const _TestTaskExperienceDataSource([]),
      );
      addTearDown(productionController.dispose);

      expect(
        () => productionController.replaceRepositoryTasks([
          _task('demo-leak', TaskType.aiAnalysis, TaskRunState.running),
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cannot enter the production'),
          ),
        ),
      );
    });
  });
}

TaskSummary _task(String id, TaskType type, TaskRunState state) => TaskSummary(
  id: id,
  type: type,
  title: type.label,
  processed: 0,
  total: 12,
  progressPercent: 0,
  remainingMinutes: 1,
  state: state,
  failedCount: state == TaskRunState.failed ? 1 : 0,
  failureReason: state == TaskRunState.failed ? 'fixture failure' : null,
  connectionState: TaskConnectionState.connected,
  availableActions: switch (state) {
    TaskRunState.running => const {TaskAction.pause, TaskAction.cancel},
    TaskRunState.queued || TaskRunState.paused => const {TaskAction.resume, TaskAction.cancel},
    TaskRunState.failed => const {TaskAction.retry, TaskAction.skipFailed},
    TaskRunState.completed || TaskRunState.cancelled => const {TaskAction.exportLog},
  },
);

class _TestTaskExperienceDataSource implements TaskExperienceDataSource {
  const _TestTaskExperienceDataSource(this.tasks);

  final List<TaskSummary> tasks;

  @override
  List<TaskSummary> initialTasks() => List.of(tasks);

  @override
  List<TaskType> executableTaskTypes() => tasks.map((task) => task.type).toList();

  @override
  SdCardSnapshot initialSdCard() => const DemoTaskExperienceDataSource().initialSdCard();

  @override
  CopyEstimate copyEstimate(CopyMode mode) => const DemoTaskExperienceDataSource().copyEstimate(mode);

  @override
  TaskCompletion completion() => const DemoTaskExperienceDataSource().completion();
}
