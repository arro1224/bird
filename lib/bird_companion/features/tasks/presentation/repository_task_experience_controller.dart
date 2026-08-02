import 'dart:async';

import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/storage/domain/storage_repository.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';

/// Coordinates the production task flow using box-authoritative state.
class RepositoryTaskExperienceController extends TaskExperienceController {
  RepositoryTaskExperienceController({
    required StorageRepository storageRepository,
    required BatchRepository batchRepository,
    required JobRepository jobRepository,
    required CopyRepository copyRepository,
    required EventClient eventClient,
    required DeviceSessionCubit deviceSessionCubit,
    Duration pollInterval = const Duration(seconds: 4),
  }) : this._(
         storageRepository: storageRepository,
         batchRepository: batchRepository,
         jobRepository: jobRepository,
         copyRepository: copyRepository,
         eventClient: eventClient,
         deviceSessionCubit: deviceSessionCubit,
         pollInterval: pollInterval,
       );

  RepositoryTaskExperienceController._({
    required this._storageRepository,
    required this._batchRepository,
    required this._jobRepository,
    required this.copyRepository,
    required this._eventClient,
    required this._deviceSessionCubit,
    required this._pollInterval,
  }) : super(const ProductionTaskExperienceDataSource()) {
    setConnectionState(_mapConnection(_deviceSessionCubit.state.phase));
    _sessionSubscription = _deviceSessionCubit.stream.listen(_onSession);
    _eventSubscription = _eventClient.events.listen(_onEvent);
    _eventConnectionSubscription = _eventClient.connectionStates.listen((_) {
      _configurePolling();
    });
  }

  final StorageRepository _storageRepository;
  final BatchRepository _batchRepository;
  final JobRepository _jobRepository;
  final CopyRepository copyRepository;
  final EventClient _eventClient;
  final DeviceSessionCubit _deviceSessionCubit;
  final Duration _pollInterval;
  final Map<String, BirdJobStatus> _jobs = {};
  final Set<String> _analysisRequestedProjects = {};
  final StreamController<String> _analysisCompleted = StreamController<String>.broadcast();
  final StreamController<String> _copyCompleted = StreamController<String>.broadcast();

  StreamSubscription<DeviceSessionState>? _sessionSubscription;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<EventConnectionState>? _eventConnectionSubscription;
  Timer? _pollTimer;
  String? _currentJobId;
  bool _refreshing = false;
  bool _disposed = false;

  Stream<String> get analysisCompletedProjects => _analysisCompleted.stream;
  Stream<String> get copyCompletedJobs => _copyCompleted.stream;
  String? get currentJobId => _currentJobId;
  List<BirdJobStatus> get jobs => List.unmodifiable(_jobs.values);

  Future<void> initialize() async {
    if (!_deviceSessionCubit.state.isConnected) return;
    await refreshFromBox(includeScan: true);
  }

  Future<void> refreshFromBox({bool includeScan = false}) async {
    if (_refreshing || !_deviceSessionCubit.state.isConnected) return;
    _refreshing = true;
    setBusyState(loading: true, clearError: true);
    try {
      final results = await Future.wait<Object?>([
        _jobRepository.list(),
        _batchRepository.current(),
        if (includeScan) _storageRepository.currentScan(),
      ]);
      final jobs = results[0] as List<BirdJobStatus>;
      _replaceJobs(jobs);
      final currentProject = results[1] as BatchSummary?;
      if (currentProject != null) {
        final projectId = currentProject.id;
        _guardProductionId(projectId, 'project_id');
        activeBatchId = projectId;
      }
      if (includeScan) {
        _applyScan(results[2]! as CardScanResult);
      }
      await _createAnalysisForCompletedImports();
    } catch (caught) {
      setBusyState(error: caught);
    } finally {
      _refreshing = false;
      setBusyState(loading: false);
      _configurePolling();
    }
  }

  Future<void> rescan() async {
    if (acting) return;
    setBusyState(acting: true, clearError: true);
    replaceSdCard(sdCard.copyWith(state: SdCardReadState.scanning));
    try {
      final scanJob = await _storageRepository.rescan();
      _guardProductionId(scanJob.id, 'job_id');
      _mergeJob(scanJob);
      _currentJobId = scanJob.id;
      final scan = await _storageRepository.currentScan();
      _applyScan(scan);
    } catch (caught) {
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  @override
  Future<String> startImportBatch(String batchName) async {
    if (acting) {
      throw StateError('A task action is already in progress');
    }
    if (!_deviceSessionCubit.state.isConnected) {
      throw StateError('The box is not connected');
    }
    final normalizedName = batchName.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(
        batchName,
        'batchName',
        'Batch name cannot be empty',
      );
    }
    var scan = await _storageRepository.currentScan();
    _applyScan(scan);
    if (!scan.canCreateProject) {
      throw StateError('The current SD card is not ready');
    }
    final cardId = scan.cardId!.trim();
    _guardProductionId(cardId, 'card_id');

    setBusyState(acting: true, clearError: true);
    try {
      final project = await _batchRepository.create(
        ProjectCreateRequest(name: normalizedName, cardId: cardId),
      );
      _guardProductionId(project.id, 'project_id');
      final importJob = await _jobRepository.createImport(
        project.id,
        const ImportJobRequest(),
      );
      _guardProductionId(importJob.id, 'job_id');

      // Commit local identifiers only after both server writes succeeded.
      activeBatchId = project.id;
      _currentJobId = importJob.id;
      _mergeJob(importJob);
      selectGroup(TaskGroup.active);
      return project.id;
    } catch (caught) {
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  Future<void> controlJob(String taskId, TaskAction action) async {
    if (acting) return;
    final current = _jobs[taskId];
    if (current == null) {
      throw ArgumentError.value(taskId, 'taskId', 'Unknown task');
    }
    final wireAction = switch (action) {
      TaskAction.pause => 'pause',
      TaskAction.resume => 'resume',
      TaskAction.cancel => 'cancel',
      TaskAction.retry => 'retry_failed',
      TaskAction.skipFailed => 'skip_failed',
      TaskAction.exportLog => null,
    };
    if (wireAction == null) {
      await _jobRepository.exportLogs(scope: 'jobs', jobId: taskId);
      return;
    }
    if (!current.availableActions.contains(wireAction) && !(wireAction == 'retry_failed' && current.availableActions.contains('retry'))) {
      throw StateError('$wireAction is unavailable for $taskId');
    }

    setBusyState(acting: true, clearError: true);
    try {
      final updated = await _jobRepository.control(
        taskId,
        wireAction,
        version: current.version,
      );
      _mergeJob(updated);
    } catch (caught) {
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  Future<JobReport> report(String jobId) => _jobRepository.report(jobId);

  Future<void> _onSession(DeviceSessionState state) async {
    final previous = connectionState;
    setConnectionState(_mapConnection(state.phase));
    if (state.isConnected && previous != TaskConnectionState.connected) {
      await refreshFromBox(includeScan: true);
    } else {
      _configurePolling();
    }
  }

  void _onEvent(DeviceEvent event) {
    if (!_deviceSessionCubit.state.isConnected) return;
    if (!event.type.contains('job')) return;
    try {
      final raw = event.payload['job'];
      final payload = raw is Map ? Map<String, dynamic>.from(raw) : event.payload;
      final job = BirdJobStatus.fromJson(payload);
      _guardProductionId(job.id, 'job_id');
      final previousState = _jobs[job.id]?.state;
      _mergeJob(job);
      if (job.state == BirdJobState.completed && previousState != BirdJobState.completed) {
        unawaited(_afterJobUpdate(job));
      }
    } catch (_) {
      // Unknown heartbeat and partial event payloads are ignored. REST
      // recovery remains authoritative.
    }
  }

  Future<void> _afterJobUpdate(BirdJobStatus job) async {
    if (job.type == BirdJobType.import && job.state == BirdJobState.completed) {
      await _createAnalysis(job.sourceProjectId);
    } else if (job.type == BirdJobType.analysis && job.state == BirdJobState.completed) {
      final projectId = job.sourceProjectId;
      if (projectId != null && projectId.isNotEmpty && !_disposed) {
        _analysisCompleted.add(projectId);
      }
    } else if (job.type == BirdJobType.copy && job.state == BirdJobState.completed && !_disposed) {
      _copyCompleted.add(job.id);
    }
  }

  Future<void> _createAnalysisForCompletedImports() async {
    for (final job in List<BirdJobStatus>.of(_jobs.values)) {
      if (job.type == BirdJobType.analysis && job.sourceProjectId != null) {
        _analysisRequestedProjects.add(job.sourceProjectId!);
      }
    }
    for (final job in List<BirdJobStatus>.of(_jobs.values)) {
      if (job.type == BirdJobType.import && job.state == BirdJobState.completed) {
        await _createAnalysis(job.sourceProjectId);
      }
    }
  }

  Future<void> _createAnalysis(String? projectId) async {
    if (projectId == null || projectId.trim().isEmpty) return;
    _guardProductionId(projectId, 'project_id');
    if (!_analysisRequestedProjects.add(projectId)) return;
    try {
      final job = await _jobRepository.createAnalysis(
        projectId,
        const AnalysisJobRequest(),
      );
      _guardProductionId(job.id, 'job_id');
      _currentJobId = job.id;
      _mergeJob(job);
    } catch (caught) {
      _analysisRequestedProjects.remove(projectId);
      setBusyState(error: caught);
    }
  }

  void _replaceJobs(Iterable<BirdJobStatus> jobs) {
    final previous = Map<String, BirdJobStatus>.of(_jobs);
    _jobs
      ..clear()
      ..addEntries(
        jobs.map((job) {
          _guardProductionId(job.id, 'job_id');
          return MapEntry(job.id, job);
        }),
      );
    _syncTaskSnapshots();
    for (final job in _jobs.values) {
      if (job.state == BirdJobState.completed && previous[job.id]?.state != BirdJobState.completed && previous.containsKey(job.id)) {
        unawaited(_afterJobUpdate(job));
      }
    }
  }

  void _mergeJob(BirdJobStatus job) {
    _guardProductionId(job.id, 'job_id');
    _jobs[job.id] = job;
    _currentJobId = job.id;
    _syncTaskSnapshots();
    _configurePolling();
  }

  void _syncTaskSnapshots() {
    final snapshots =
        _jobs.values
            .map(
              (job) => JobStatusViewAdapter.toTaskSummary(
                job,
                sourceBatch: job.sourceProjectId,
                connectionState: connectionState,
              ),
            )
            .whereType<TaskSummary>()
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
    replaceRepositoryTasks(snapshots);
  }

  void _applyScan(CardScanResult scan) {
    final cardId = scan.cardId?.trim();
    if (cardId != null && cardId.isNotEmpty) {
      _guardProductionId(cardId, 'card_id');
    }
    replaceSdCard(
      SdCardSnapshot(
        state: switch (scan.state) {
          CardScanState.detected => SdCardReadState.detected,
          CardScanState.scanning => SdCardReadState.scanning,
          CardScanState.missing => SdCardReadState.missing,
          CardScanState.unreadable || CardScanState.unknown => SdCardReadState.readFailed,
          CardScanState.empty => SdCardReadState.empty,
        },
        name: scan.cardName ?? '',
        photoCount: scan.photoCount,
        requiredSpaceGb: scan.requiredBytes / (1024 * 1024 * 1024),
        rawCount: scan.rawCount,
        jpegCount: scan.jpegCount,
        captureDate: DateTime.now(),
      ),
    );
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final needsPolling =
        _deviceSessionCubit.state.isConnected &&
        _eventClient.currentState != EventConnectionState.connected &&
        _jobs.values.any(
          (job) => job.state == BirdJobState.running || job.state == BirdJobState.queued,
        );
    if (needsPolling) {
      _pollTimer = Timer.periodic(
        _pollInterval,
        (_) => unawaited(refreshFromBox()),
      );
    }
  }

  TaskConnectionState _mapConnection(DeviceSessionPhase phase) => switch (phase) {
    DeviceSessionPhase.connected => TaskConnectionState.connected,
    DeviceSessionPhase.connecting || DeviceSessionPhase.reconnecting => TaskConnectionState.reconnecting,
    DeviceSessionPhase.disconnected || DeviceSessionPhase.incompatible => TaskConnectionState.disconnected,
  };

  void _guardProductionId(String value, String field) {
    if (value.startsWith('demo-')) {
      throw StateError('$field cannot use a demo identifier in production');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    unawaited(_sessionSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_eventConnectionSubscription?.cancel());
    unawaited(_analysisCompleted.close());
    unawaited(_copyCompleted.close());
    super.dispose();
  }
}
