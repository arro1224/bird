import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:flutter/foundation.dart';

class TaskExperienceController extends ChangeNotifier {
  TaskExperienceController(this._dataSource) {
    _restoreFixtures();
  }

  final TaskExperienceDataSource _dataSource;

  late List<TaskSummary> _tasks;
  late String _currentTaskId;
  late List<TaskType> executableTaskTypes;
  late SdCardSnapshot sdCard;
  late CopyMode copyMode;
  late CopyEstimate copyEstimate;
  late TaskCompletion completion;
  late TaskGroup selectedGroup;
  late TaskConnectionState connectionState;
  String? activeBatchId;
  TaskControlIntent? lastIntent;
  bool generateXmp = true;
  bool verifyAfterCopy = true;

  List<TaskSummary> get tasks => List.unmodifiable(_tasks);

  TaskSummary get currentTask => taskById(_currentTaskId);

  TaskSummary _preferredCurrentTask() {
    for (final state in const [
      TaskRunState.running,
      TaskRunState.queued,
      TaskRunState.paused,
      TaskRunState.failed,
      TaskRunState.completed,
      TaskRunState.cancelled,
    ]) {
      for (final task in _tasks) {
        if (task.state == state) return task;
      }
    }
    return _tasks.first;
  }

  TaskSummary? _activeTask() {
    for (final state in const [TaskRunState.running, TaskRunState.queued]) {
      for (final task in _tasks) {
        if (task.state == state) return task;
      }
    }
    return null;
  }

  List<TaskSummary> get visibleTasks => tasksFor(selectedGroup);

  bool get hasDisconnectedTask => connectionState == TaskConnectionState.disconnected;

  List<TaskSummary> tasksFor(TaskGroup group) => List.unmodifiable(
    _tasks.where((task) => task.group == group),
  );

  TaskSummary taskById(String taskId) => _tasks.firstWhere(
    (task) => task.id == taskId,
  );

  TaskSummary _taskByType(TaskType type, [Iterable<TaskSummary>? tasks]) {
    final matches = (tasks ?? _tasks).where((task) => task.type == type).toList();
    if (matches.isEmpty) {
      throw StateError('Missing required task type: ${type.name}');
    }
    if (matches.length > 1) {
      throw StateError('Expected one ${type.name} task, found ${matches.length}');
    }
    return matches.single;
  }

  void selectGroup(TaskGroup group) {
    if (selectedGroup == group) return;
    selectedGroup = group;
    notifyListeners();
  }

  void performAction(String taskId, TaskAction action) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) {
      throw ArgumentError.value(taskId, 'taskId', 'Unknown task');
    }
    final task = _tasks[index];
    if (!task.availableActions.contains(action)) {
      throw StateError('${action.name} is unavailable for $taskId');
    }

    lastIntent = TaskControlIntent(taskId, action);
    final (state, actions) = switch (action) {
      TaskAction.pause => (
        TaskRunState.paused,
        const {TaskAction.resume, TaskAction.cancel, TaskAction.exportLog},
      ),
      TaskAction.resume || TaskAction.retry => (
        TaskRunState.running,
        const {TaskAction.pause, TaskAction.cancel, TaskAction.exportLog},
      ),
      TaskAction.cancel => (
        TaskRunState.cancelled,
        const {TaskAction.exportLog},
      ),
      TaskAction.skipFailed => (
        TaskRunState.completed,
        const {TaskAction.exportLog},
      ),
      TaskAction.exportLog => (task.state, task.availableActions),
    };
    _tasks[index] = task.copyWith(
      state: state,
      availableActions: actions,
      progressPercent: action == TaskAction.skipFailed ? 100 : null,
      remainingMinutes: action == TaskAction.skipFailed ? 0 : null,
      clearFailure: action == TaskAction.retry,
    );
    if (action != TaskAction.exportLog) {
      _currentTaskId = switch (state) {
        TaskRunState.completed || TaskRunState.cancelled => _activeTask()?.id ?? taskId,
        _ => taskId,
      };
    }
    notifyListeners();
  }

  void pauseOrResume() {
    final action = currentTask.state == TaskRunState.paused ? TaskAction.resume : TaskAction.pause;
    performAction(currentTask.id, action);
  }

  void cancel() {
    performAction(currentTask.id, TaskAction.cancel);
  }

  void setSdState(SdCardReadState state) {
    sdCard = sdCard.copyWith(state: state);
    notifyListeners();
  }

  void selectCopyMode(CopyMode mode) {
    copyMode = mode;
    copyEstimate = _dataSource.copyEstimate(mode);
    notifyListeners();
  }

  void setGenerateXmp(bool value) {
    generateXmp = value;
    notifyListeners();
  }

  void setVerifyAfterCopy(bool value) {
    verifyAfterCopy = value;
    notifyListeners();
  }

  void setCopyTargetOnline(bool value) {
    copyEstimate = copyEstimate.copyWith(targetOnline: value);
    notifyListeners();
  }

  void setConnectionState(TaskConnectionState value) {
    if (connectionState == value) return;
    connectionState = value;
    notifyListeners();
  }

  void startTask(String taskId) {
    final task = taskById(taskId);
    final action = task.availableActions.contains(TaskAction.resume)
        ? TaskAction.resume
        : task.availableActions.contains(TaskAction.retry)
        ? TaskAction.retry
        : null;
    if (action == null) {
      throw StateError('Task $taskId is not ready to start');
    }
    performAction(taskId, action);
  }

  void completeTask([String? taskId]) {
    final task = taskId == null ? currentTask : taskById(taskId);
    final completedTask = task.copyWith(
      state: TaskRunState.completed,
      processed: task.total,
      progressPercent: 100,
      remainingMinutes: 0,
      availableActions: const {TaskAction.exportLog},
      clearFailure: true,
    );
    _replaceTask(completedTask);
    _currentTaskId = _activeTask()?.id ?? completedTask.id;
    if (completedTask.type == TaskType.importIndex) {
      final analysisTask = _taskByType(TaskType.aiAnalysis);
      _replaceTask(
        analysisTask.copyWith(
          state: TaskRunState.queued,
          sourceBatch: completedTask.sourceBatch,
          processed: 0,
          progressPercent: 0,
          availableActions: const {
            TaskAction.resume,
            TaskAction.cancel,
            TaskAction.exportLog,
          },
        ),
      );
      _currentTaskId = analysisTask.id;
    } else if (completedTask.type == TaskType.aiAnalysis) {
      final copyTask = _taskByType(TaskType.copy);
      _replaceTask(
        TaskSummary(
          id: copyTask.id,
          type: copyTask.type,
          title: copyTask.title,
          processed: 0,
          total: copyEstimate.photoCount,
          progressPercent: 0,
          remainingMinutes: copyEstimate.estimatedMinutes,
          state: TaskRunState.queued,
          sourceBatch: completedTask.sourceBatch,
          failedCount: 0,
          connectionState: connectionState,
          availableActions: const {
            TaskAction.resume,
            TaskAction.cancel,
            TaskAction.exportLog,
          },
        ),
      );
      _currentTaskId = copyTask.id;
    }
    notifyListeners();
  }

  String startImportBatch(String batchName) {
    final normalizedName = batchName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(batchName, 'batchName', 'Batch name cannot be empty');
    }
    final date = sdCard.captureDate;
    activeBatchId = 'demo-batch-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final fixtures = _dataSource.initialTasks();
    _replaceTask(_taskByType(TaskType.aiAnalysis, fixtures));
    _replaceTask(_taskByType(TaskType.copy, fixtures));
    final importTask = _taskByType(TaskType.importIndex, fixtures);
    _replaceTask(
      importTask.copyWith(
        state: TaskRunState.running,
        sourceBatch: normalizedName,
        processed: 0,
        progressPercent: 0,
        remainingMinutes: 32,
        availableActions: const {TaskAction.pause, TaskAction.cancel, TaskAction.exportLog},
      ),
    );
    _currentTaskId = importTask.id;
    selectedGroup = TaskGroup.active;
    notifyListeners();
    return activeBatchId!;
  }

  void resetDemo() {
    _restoreFixtures();
    notifyListeners();
  }

  void _replaceTask(TaskSummary task) {
    final index = _tasks.indexWhere((candidate) => candidate.id == task.id);
    _tasks[index] = task;
  }

  void _restoreFixtures() {
    _tasks = List.of(_dataSource.initialTasks());
    if (_tasks.isEmpty) {
      throw StateError('Task experience requires at least one task');
    }
    _currentTaskId = _preferredCurrentTask().id;
    executableTaskTypes = List.unmodifiable(
      _dataSource.executableTaskTypes(),
    );
    sdCard = _dataSource.initialSdCard();
    copyMode = CopyMode.keep;
    copyEstimate = _dataSource.copyEstimate(copyMode);
    completion = _dataSource.completion();
    selectedGroup = TaskGroup.active;
    connectionState = TaskConnectionState.connected;
    activeBatchId = null;
    lastIntent = null;
    generateXmp = true;
    verifyAfterCopy = true;
  }
}
