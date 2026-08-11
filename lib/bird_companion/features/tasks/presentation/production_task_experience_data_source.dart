import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';

/// Empty startup state for the production task experience.
///
/// This class intentionally contains no demo identifiers or fixture counts.
class ProductionTaskExperienceDataSource implements TaskExperienceDataSource {
  const ProductionTaskExperienceDataSource();

  @override
  List<TaskSummary> initialTasks() => const [];

  @override
  List<TaskType> executableTaskTypes() => const [];

  @override
  SdCardSnapshot initialSdCard() => SdCardSnapshot(
    state: SdCardReadState.missing,
    name: '',
    photoCount: 0,
    requiredSpaceGb: 0,
    rawCount: 0,
    jpegCount: 0,
    captureDate: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  CopyEstimate copyEstimate(CopyMode mode) => CopyEstimate(
    mode: mode,
    totalPhotoCount: 0,
    keptCount: 0,
    pendingReviewCount: 0,
    discardedCount: 0,
    photoCount: 0,
    spaceGb: 0,
    targetName: '',
    availableSpaceTb: 0,
    estimatedMinutes: 0,
    targetOnline: false,
  );

  @override
  TaskCompletion completion() => const TaskCompletion(
    photoCount: 0,
    dataSizeGb: 0,
    xmpCount: 0,
    elapsedMinutes: 0,
    elapsedSeconds: 0,
    pendingReviewCount: 0,
  );
}
