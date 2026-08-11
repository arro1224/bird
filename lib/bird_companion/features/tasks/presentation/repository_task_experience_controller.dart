import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/storage/domain/storage_repository.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_home_capability_resolver.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/foundation.dart';

/// Coordinates the production task flow using box-authoritative state.
class RepositoryTaskExperienceController extends TaskExperienceController {
  RepositoryTaskExperienceController({
    required DeviceRepository deviceRepository,
    required StorageRepository storageRepository,
    required BatchRepository batchRepository,
    required JobRepository jobRepository,
    required CopyRepository copyRepository,
    required EventClient eventClient,
    required DeviceSessionCubit deviceSessionCubit,
    required PendingOperationStore pendingOperationStore,
    AppDataChangeBus? dataChangeBus,
    Duration pollInterval = const Duration(seconds: 4),
  }) : this._(
         storageRepository: storageRepository,
         deviceRepository: deviceRepository,
         batchRepository: batchRepository,
         jobRepository: jobRepository,
         copyRepository: copyRepository,
         eventClient: eventClient,
         deviceSessionCubit: deviceSessionCubit,
         pendingOperationStore: pendingOperationStore,
         dataChangeBus: dataChangeBus,
         pollInterval: pollInterval,
       );

  RepositoryTaskExperienceController._({
    required this._deviceRepository,
    required this._storageRepository,
    required this._batchRepository,
    required this._jobRepository,
    required this.copyRepository,
    required this._eventClient,
    required this._deviceSessionCubit,
    required this._pendingOperationStore,
    required this._dataChangeBus,
    required this._pollInterval,
  }) : super(const ProductionTaskExperienceDataSource()) {
    setConnectionState(_mapConnection(_deviceSessionCubit.state.phase));
    _lastEventConnectionState = _eventClient.currentState;
    _sessionSubscription = _deviceSessionCubit.stream.listen(_onSession);
    _eventSubscription = _eventClient.events.listen(_onEvent);
    _eventConnectionSubscription = _eventClient.connectionStates.listen(
      _onEventConnectionState,
    );
    _pendingOperationSubscription = _pendingOperationStore.changes.listen((_) {
      _recomputeExecutableTaskTypes();
    });
    _recomputeExecutableTaskTypes();
  }

  final DeviceRepository _deviceRepository;
  final StorageRepository _storageRepository;
  final BatchRepository _batchRepository;
  final JobRepository _jobRepository;
  final CopyRepository copyRepository;
  final EventClient _eventClient;
  final DeviceSessionCubit _deviceSessionCubit;
  final PendingOperationStore _pendingOperationStore;
  final AppDataChangeBus? _dataChangeBus;
  final Duration _pollInterval;
  final Map<String, BirdJobStatus> _jobs = {};
  final Set<String> _analysisRequestedProjects = {};
  final Map<String, Future<String>> _analysisRequests = {};
  final StreamController<String> _analysisCompleted = StreamController<String>.broadcast();
  final StreamController<String> _copyCompleted = StreamController<String>.broadcast();

  StreamSubscription<DeviceSessionState>? _sessionSubscription;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<EventConnectionState>? _eventConnectionSubscription;
  StreamSubscription<List<PendingOperation>>? _pendingOperationSubscription;
  Timer? _pollTimer;
  String? _currentJobId;
  bool _refreshing = false;
  bool _refreshRequested = false;
  bool _refreshRequestedIncludeScan = false;
  bool _authorityReady = false;
  bool _disposed = false;
  bool _loadingMoreJobs = false;
  bool _hasMoreJobs = false;
  String? _nextJobsCursor;
  DeviceStatus? _deviceStatus;
  BatchSummary? _currentProject;
  CardScanResult? _currentScan;
  EventConnectionState? _lastEventConnectionState;

  Stream<String> get analysisCompletedProjects => _analysisCompleted.stream;
  Stream<String> get copyCompletedJobs => _copyCompleted.stream;
  String? get currentJobId => _currentJobId;
  List<BirdJobStatus> get jobs => List.unmodifiable(_jobs.values);
  @override
  bool get hasMoreTasks => _hasMoreJobs;
  @override
  bool get loadingMoreTasks => _loadingMoreJobs;
  bool get homeInputsReady => _authorityReady;

  @override
  List<TaskHomeActionCapability> get taskHomeCapabilities {
    final activeDeviceId = _deviceSessionCubit.state.device?.id.trim();
    final hasPendingOperations =
        activeDeviceId != null &&
        activeDeviceId.isNotEmpty &&
        _pendingOperationStore.readAll().any(
          (operation) => operation.deviceId == activeDeviceId,
        );
    return TaskHomeCapabilityResolver.resolveCapabilities(
      connected: _deviceSessionCubit.state.isConnected,
      authorityReady: _authorityReady,
      deviceStatus: _deviceStatus,
      currentProject: _currentProject,
      currentScan: _currentScan,
      jobs: _jobs.values,
      hasPendingOperations: hasPendingOperations,
    );
  }

  @override
  bool get canSubmitTaskWrites => super.canSubmitTaskWrites && _authorityReady;

  Future<void> initialize() async {
    if (!_deviceSessionCubit.state.isConnected) return;
    await refreshFromBox(includeScan: true);
  }

  Future<void> refreshFromBox({bool includeScan = false}) async {
    if (_disposed || !_deviceSessionCubit.state.isConnected) return;
    if (_refreshing) {
      _refreshRequested = true;
      _refreshRequestedIncludeScan |= includeScan;
      return;
    }
    final requestedDeviceId = _deviceSessionCubit.state.device?.id.trim();
    if (requestedDeviceId == null || requestedDeviceId.isEmpty) return;
    _refreshing = true;
    setBusyState(loading: true, clearError: true);
    try {
      final results = await Future.wait<Object?>([
        _deviceRepository.fetchStatus(),
        _jobRepository.page(),
        _batchRepository.current(),
        if (includeScan) _storageRepository.currentScan(),
      ]);
      if (_disposed || !_isCurrentDevice(requestedDeviceId)) return;
      final deviceStatus = results[0] as DeviceStatus;
      _guardProductionId(deviceStatus.connection.id, 'device_id');
      if (deviceStatus.connection.id != requestedDeviceId) {
        throw StateError('The REST snapshot belongs to a different device session');
      }
      _deviceStatus = deviceStatus;
      final jobPage = results[1] as JobPage;
      final authoritativeJobs = <String, BirdJobStatus>{
        for (final job in jobPage.items) job.id: job,
      };
      final currentJob = deviceStatus.currentJob;
      if (currentJob != null) authoritativeJobs[currentJob.id] = currentJob;
      _replaceJobs(authoritativeJobs.values);
      _hasMoreJobs = jobPage.hasMore && jobPage.nextCursor != null;
      _nextJobsCursor = jobPage.nextCursor;
      final currentProject = results[2] as BatchSummary?;
      _currentProject = currentProject;
      if (currentProject != null) {
        final projectId = currentProject.id;
        _guardProductionId(projectId, 'project_id');
        activeBatchId = projectId;
      } else {
        // The box is authoritative. Do not retain a project selected before a
        // device switch or after the server has cleared its current project.
        activeBatchId = null;
      }
      if (includeScan) {
        _applyScan(results[3]! as CardScanResult);
      }
      await _createAnalysisForCompletedImports();
      _authorityReady = true;
      _recomputeExecutableTaskTypes();
    } catch (caught) {
      if (!_disposed && _isCurrentDevice(requestedDeviceId)) {
        _authorityReady = false;
        _recomputeExecutableTaskTypes();
        setBusyState(error: caught);
      }
    } finally {
      _refreshing = false;
      if (!_disposed) {
        setBusyState(loading: false);
        _configurePolling();
      }
      if (_refreshRequested && !_disposed) {
        final nextIncludeScan = _refreshRequestedIncludeScan;
        _refreshRequested = false;
        _refreshRequestedIncludeScan = false;
        if (_deviceSessionCubit.state.isConnected) {
          unawaited(refreshFromBox(includeScan: nextIncludeScan));
        }
      }
    }
  }

  @override
  Future<void> loadMoreTasks() async {
    final cursor = _nextJobsCursor;
    if (_loadingMoreJobs || !_hasMoreJobs || cursor == null) return;
    _loadingMoreJobs = true;
    notifyListeners();
    try {
      final page = await _jobRepository.page(cursor: cursor);
      for (final job in page.items) {
        _guardProductionId(job.id, 'job_id');
        _jobs.putIfAbsent(job.id, () => job);
      }
      _hasMoreJobs = page.hasMore && page.nextCursor != null && page.nextCursor != cursor;
      _nextJobsCursor = page.nextCursor;
      _syncTaskSnapshots();
      _recomputeExecutableTaskTypes();
    } catch (caught) {
      setBusyState(error: caught);
    } finally {
      _loadingMoreJobs = false;
      notifyListeners();
    }
  }

  Future<void> rescan() async {
    if (acting) return;
    setBusyState(acting: true, clearError: true);
    replaceSdCard(sdCard.copyWith(state: SdCardReadState.scanning));
    final previousScan = _currentScan;
    _currentScan = CardScanResult(
      state: CardScanState.scanning,
      cardId: previousScan?.cardId,
      cardName: previousScan?.cardName,
      photoCount: previousScan?.photoCount ?? 0,
      rawCount: previousScan?.rawCount ?? 0,
      jpegCount: previousScan?.jpegCount ?? 0,
      requiredBytes: previousScan?.requiredBytes ?? 0,
    );
    _recomputeExecutableTaskTypes();
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
    if (!_authorityReady || _refreshing || loading) {
      throw StateError('The task home state is refreshing');
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
      _currentProject = project;
      _currentJobId = importJob.id;
      _mergeJob(importJob);
      selectGroup(TaskGroup.active);
      _dataChangeBus?.publish(
        {
          AppDataResource.batches,
          AppDataResource.photos,
          AppDataResource.jobs,
          AppDataResource.device,
        },
        reason: 'import_project_created',
      );
      return project.id;
    } catch (caught) {
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  Future<String> startAnalysisForActiveProject() async {
    if (!_deviceSessionCubit.state.isConnected) {
      throw StateError('The box is not connected');
    }
    if (!_authorityReady || _refreshing || loading) {
      throw StateError('The task home state is refreshing');
    }
    final projectId = activeBatchId?.trim();
    if (projectId == null || projectId.isEmpty) {
      throw StateError('There is no active project to analyze');
    }
    _guardProductionId(projectId, 'project_id');

    final inFlight = _analysisRequests[projectId];
    if (inFlight != null) return inFlight;
    if (acting) {
      throw StateError('A task action is already in progress');
    }

    for (final job in _jobs.values) {
      if (job.type == BirdJobType.analysis && job.sourceProjectId == projectId && (job.state == BirdJobState.queued || job.state == BirdJobState.running || job.state == BirdJobState.paused)) {
        _currentJobId = job.id;
        return job.id;
      }
    }

    final request = _submitManualAnalysis(projectId);
    _analysisRequests[projectId] = request;
    try {
      return await request;
    } finally {
      if (identical(_analysisRequests[projectId], request)) {
        final _ = _analysisRequests.remove(projectId);
      }
    }
  }

  Future<String> _submitManualAnalysis(String projectId) async {
    setBusyState(acting: true, clearError: true);
    _analysisRequestedProjects.add(projectId);
    try {
      final job = await _jobRepository.createAnalysis(
        projectId,
        const AnalysisJobRequest(),
      );
      _guardProductionId(job.id, 'job_id');
      _mergeJob(job);
      return job.id;
    } catch (caught) {
      _analysisRequestedProjects.remove(projectId);
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  Future<void> controlJob(String taskId, TaskAction action) async {
    if (!_deviceSessionCubit.state.isConnected) {
      throw StateError('The box is not connected');
    }
    if (!_authorityReady || _refreshing || loading) {
      throw StateError('The task state is refreshing');
    }
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
    if (!jobControlActions.contains(wireAction) || !current.availableActions.contains(wireAction)) {
      throw StateError('$wireAction is unavailable for $taskId');
    }
    final version = current.version;
    if (version == null) {
      throw StateError('The task version is unavailable');
    }

    setBusyState(acting: true, clearError: true);
    try {
      final updated = await _jobRepository.control(
        taskId,
        wireAction,
        version: version,
      );
      _mergeJob(updated);
    } catch (caught) {
      if (caught is ApiException && caught.statusCode == 409) {
        try {
          await refreshJobDetail(taskId);
        } catch (_) {
          // Preserve the original conflict. The next explicit refresh can
          // recover if the detail request is also temporarily unavailable.
        }
      }
      setBusyState(error: caught);
      rethrow;
    } finally {
      setBusyState(acting: false);
    }
  }

  Future<BirdJobStatus> refreshJobDetail(String jobId) async {
    if (!_deviceSessionCubit.state.isConnected) {
      throw StateError('The box is not connected');
    }
    _guardProductionId(jobId, 'job_id');
    try {
      final job = await _jobRepository.detail(jobId);
      _mergeJob(job);
      return job;
    } catch (caught) {
      setBusyState(error: caught);
      rethrow;
    }
  }

  Future<JobReport> report(String jobId) => _jobRepository.report(jobId);

  Future<void> _onSession(DeviceSessionState state) async {
    if (_disposed) return;
    final previous = connectionState;
    if (!state.isConnected) _authorityReady = false;
    setConnectionState(_mapConnection(state.phase));
    _recomputeExecutableTaskTypes();
    if (state.isConnected && previous != TaskConnectionState.connected) {
      await refreshFromBox(includeScan: true);
    } else {
      _configurePolling();
    }
  }

  void _onEventConnectionState(EventConnectionState state) {
    if (_disposed) return;
    final previous = _lastEventConnectionState;
    _lastEventConnectionState = state;
    _configurePolling();
    if (state == EventConnectionState.connected && previous != null && previous != EventConnectionState.connected && _deviceSessionCubit.state.isConnected) {
      // Events may have been missed while the socket was unavailable. REST is
      // the frozen v1 source of truth, so always converge with a full snapshot
      // before accepting new task writes after event recovery.
      unawaited(refreshFromBox(includeScan: true));
    }
  }

  void _onEvent(DeviceEvent event) {
    if (_disposed || !_deviceSessionCubit.state.isConnected) return;
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
    if (_disposed || projectId == null || projectId.trim().isEmpty) return;
    _guardProductionId(projectId, 'project_id');
    if (!_analysisRequestedProjects.add(projectId)) return;
    try {
      final job = await _jobRepository.createAnalysis(
        projectId,
        const AnalysisJobRequest(),
      );
      if (_disposed) return;
      _guardProductionId(job.id, 'job_id');
      _currentJobId = job.id;
      _mergeJob(job);
    } catch (caught) {
      _analysisRequestedProjects.remove(projectId);
      if (!_disposed) setBusyState(error: caught);
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
    _recomputeExecutableTaskTypes();
    for (final job in _jobs.values) {
      if (job.state == BirdJobState.completed && previous[job.id]?.state != BirdJobState.completed && previous.containsKey(job.id)) {
        unawaited(_afterJobUpdate(job));
      }
    }
  }

  void _mergeJob(BirdJobStatus job) {
    _guardProductionId(job.id, 'job_id');
    final current = _jobs[job.id];
    if (current?.version != null && job.version != null && job.version! < current!.version!) {
      return;
    }
    if (_jobs.containsKey(job.id)) {
      _jobs[job.id] = job;
    } else {
      final previous = Map<String, BirdJobStatus>.of(_jobs);
      _jobs
        ..clear()
        ..[job.id] = job
        ..addAll(previous);
    }
    _currentJobId = job.id;
    _syncTaskSnapshots();
    _recomputeExecutableTaskTypes();
    _configurePolling();
  }

  void _syncTaskSnapshots() {
    final snapshots = _jobs.values
        .map(
          (job) => JobStatusViewAdapter.toTaskSummary(
            job,
            connectionState: connectionState,
          ),
        )
        .whereType<TaskSummary>()
        .toList();
    replaceRepositoryTasks(snapshots);
  }

  void _applyScan(CardScanResult scan) {
    _currentScan = scan;
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
      errorCode: scan.errorCode,
      errorMessage: scan.errorMessage,
    );
    _recomputeExecutableTaskTypes();
  }

  void _recomputeExecutableTaskTypes() {
    final activeDeviceId = _deviceSessionCubit.state.device?.id.trim();
    final hasPendingOperations =
        activeDeviceId != null &&
        activeDeviceId.isNotEmpty &&
        _pendingOperationStore.readAll().any(
          (operation) => operation.deviceId == activeDeviceId,
        );
    final next = TaskHomeCapabilityResolver.resolve(
      connected: _deviceSessionCubit.state.isConnected,
      authorityReady: _authorityReady,
      deviceStatus: _deviceStatus,
      currentProject: _currentProject,
      currentScan: _currentScan,
      jobs: _jobs.values,
      hasPendingOperations: hasPendingOperations,
    );
    if (listEquals(executableTaskTypes, next)) return;
    replaceExecutableTaskTypes(next);
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

  bool _isCurrentDevice(String deviceId) => _deviceSessionCubit.state.isConnected && _deviceSessionCubit.state.device?.id.trim() == deviceId;

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
    unawaited(_pendingOperationSubscription?.cancel());
    unawaited(_analysisCompleted.close());
    unawaited(_copyCompleted.close());
    super.dispose();
  }
}
