import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobDetailState {
  const JobDetailState({
    this.loading = false,
    this.controlling = false,
    this.job,
    this.report,
    this.failures = const [],
    this.error,
    this.message,
    this.connectionPhase = DeviceSessionPhase.connected,
    this.authorityReady = true,
  });
  final bool loading;
  final bool controlling;
  final BirdJobStatus? job;
  final JobReport? report;
  final List<JobFailure> failures;
  final Object? error;
  final String? message;
  final DeviceSessionPhase connectionPhase;
  final bool authorityReady;

  bool get canSubmitWrites => connectionPhase == DeviceSessionPhase.connected && authorityReady && !loading && !controlling;

  JobDetailState copyWith({
    bool? loading,
    bool? controlling,
    BirdJobStatus? job,
    JobReport? report,
    List<JobFailure>? failures,
    Object? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    bool clearReport = false,
    DeviceSessionPhase? connectionPhase,
    bool? authorityReady,
  }) => JobDetailState(
    loading: loading ?? this.loading,
    controlling: controlling ?? this.controlling,
    job: job ?? this.job,
    report: clearReport ? null : report ?? this.report,
    failures: failures ?? this.failures,
    error: clearError ? null : error ?? this.error,
    message: clearMessage ? null : message ?? this.message,
    connectionPhase: connectionPhase ?? this.connectionPhase,
    authorityReady: authorityReady ?? this.authorityReady,
  );
}

class JobDetailCubit extends Cubit<JobDetailState> {
  JobDetailCubit(
    this._repository,
    this._events,
    this.jobId, [
    this._refreshCoordinator,
    this._dataChanges,
    this._deviceSessionCubit,
  ]) : super(
         JobDetailState(
           connectionPhase: _deviceSessionCubit?.state.phase ?? DeviceSessionPhase.connected,
           authorityReady: _deviceSessionCubit == null,
         ),
       ) {
    _eventSubscription = _events.events.where((event) => event.type == 'job_updated' || event.type == 'job_progress' || event.type == 'job_state_changed').listen(_onEvent);
    _connectionSubscription = _events.connectionStates.listen((_) {
      final job = state.job;
      if (job != null) _configurePolling(job);
      if (_events.currentState == EventConnectionState.connected && job != null) unawaited(load());
    });
    _deviceSessionSubscription = _deviceSessionCubit?.stream.listen((session) {
      if (!isClosed) {
        final recovered = session.isConnected && state.connectionPhase != DeviceSessionPhase.connected;
        if (session.phase != state.connectionPhase) _readEpoch++;
        if (!session.isConnected) _awaitingRecovery = true;
        emit(
          state.copyWith(
            connectionPhase: session.phase,
            authorityReady: session.isConnected && !recovered ? state.authorityReady : false,
          ),
        );
        if (recovered) unawaited(load());
      }
    });
  }

  final JobRepository _repository;
  final EventClient _events;
  final String jobId;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;
  final DeviceSessionCubit? _deviceSessionCubit;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<EventConnectionState>? _connectionSubscription;
  StreamSubscription<DeviceSessionState>? _deviceSessionSubscription;
  Timer? _pollTimer;
  bool _loadInFlight = false;
  bool _awaitingRecovery = false;
  bool _reloadRequested = false;
  int _readEpoch = 0;

  Future<void> load() async {
    if (_loadInFlight) {
      _reloadRequested = true;
      return;
    }
    _loadInFlight = true;
    final epoch = _readEpoch;
    emit(
      state.copyWith(
        loading: true,
        authorityReady: false,
        clearError: true,
        clearMessage: true,
      ),
    );
    try {
      final incoming = await _repository.detail(jobId);
      if (isClosed) return;
      if (epoch != _readEpoch || _deviceSessionCubit?.state.isConnected == false) return;
      if (incoming.id != jobId) throw StateError('返回任务与当前请求不一致');
      final current = state.job;
      final job = current != null && !incoming.canReplace(current) ? current : incoming;
      final outcome = await _readOutcome(job);
      if (isClosed) return;
      if (epoch != _readEpoch || _deviceSessionCubit?.state.isConnected == false) return;
      if (state.job != null && !job.canReplace(state.job!)) {
        emit(state.copyWith(loading: false, authorityReady: true));
        return;
      }
      emit(
        state.copyWith(
          loading: false,
          job: job,
          report: outcome.report,
          clearReport: outcome.report == null,
          failures: outcome.failures,
          authorityReady: true,
        ),
      );
      _configurePolling(job);
      _awaitingRecovery = false;
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          loading: false,
          authorityReady: false,
          error: error,
        ),
      );
    } finally {
      _loadInFlight = false;
      if (_reloadRequested && !isClosed && _deviceSessionCubit?.state.isConnected != false) {
        _reloadRequested = false;
        unawaited(load());
      }
    }
  }

  Future<void> control(String action) async {
    if (state.controlling) return;
    if (state.loading || _loadInFlight) {
      emit(
        state.copyWith(
          error: StateError('The task state is refreshing'),
          clearMessage: true,
        ),
      );
      return;
    }
    if (!state.authorityReady) {
      emit(
        state.copyWith(
          error: StateError('The task state is not authoritative'),
          clearMessage: true,
        ),
      );
      return;
    }
    final current = state.job;
    if (current == null) return;
    if (_deviceSessionCubit?.state.isConnected == false) {
      emit(
        state.copyWith(
          error: StateError('The box is not connected'),
          clearMessage: true,
        ),
      );
      return;
    }
    final wireAction = action == 'retry' ? 'retry_failed' : action;
    if (!jobControlActions.contains(wireAction) || !current.allowsControl(wireAction)) {
      emit(
        state.copyWith(
          error: StateError('$wireAction is unavailable for $jobId'),
          clearMessage: true,
        ),
      );
      return;
    }
    final version = current.version;
    if (version == null) {
      emit(
        state.copyWith(
          error: StateError('The task version is unavailable'),
          clearMessage: true,
        ),
      );
      return;
    }
    emit(state.copyWith(controlling: true, clearError: true, clearMessage: true));
    try {
      final updated = await _repository.control(
        jobId,
        wireAction,
        version: version,
      );
      if (isClosed) return;
      final latest = state.job;
      final accepted = latest != null && !updated.canReplace(latest) ? latest : updated;
      final outcome = await _readOutcome(accepted);
      if (isClosed) return;
      if (state.job == null || accepted.canReplace(state.job!)) {
        emit(state.copyWith(job: accepted, report: outcome.report, clearReport: outcome.report == null, failures: outcome.failures));
      }
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_$action');
      emit(
        state.copyWith(
          controlling: false,
          message: '任务已${_actionLabel(action)}。',
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(controlling: false, error: error));
    }
  }

  Future<bool> delete() async {
    if (state.controlling || state.job?.canDelete != true) return false;
    if (state.loading || _loadInFlight) {
      emit(
        state.copyWith(
          error: StateError('The task state is refreshing'),
          clearMessage: true,
        ),
      );
      return false;
    }
    if (!state.authorityReady) {
      emit(
        state.copyWith(
          error: StateError('The task state is not authoritative'),
          clearMessage: true,
        ),
      );
      return false;
    }
    if (_deviceSessionCubit?.state.isConnected == false) {
      emit(
        state.copyWith(
          error: StateError('The box is not connected'),
          clearMessage: true,
        ),
      );
      return false;
    }
    emit(state.copyWith(controlling: true, clearError: true, clearMessage: true));
    try {
      await _repository.delete(jobId);
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_deleted');
      emit(state.copyWith(controlling: false, message: '任务已从盒子任务列表移除'));
      return true;
    } catch (error) {
      emit(state.copyWith(controlling: false, error: error));
      return false;
    }
  }

  void _onEvent(DeviceEvent event) {
    if (isClosed || _deviceSessionCubit?.state.isConnected == false) return;
    if (_awaitingRecovery) {
      unawaited(load());
      return;
    }
    try {
      final raw = event.payload['job'];
      final payload = raw is Map ? Map<String, dynamic>.from(raw) : event.payload;
      final update = BirdJobStatus.fromJson(payload);
      if (update.id.isEmpty || update.id != jobId) return;
      final current = state.job;
      // 事件可能乱序/重放；旧版本不得覆盖已经读到的新快照。
      if (current != null && !update.canReplace(current)) return;
      emit(state.copyWith(job: update, clearError: true));
      _configurePolling(update);
      if (_isTerminal(update)) {
        unawaited(_refreshOutcome(update));
      }
    } catch (_) {
      // 部分/破损 payload 交给下一次 REST 全量刷新，绝不让单条事件打断订阅。
    }
  }

  Future<_JobOutcome> _readOutcome(BirdJobStatus job) async {
    var failures = const <JobFailure>[];
    JobReport? report;
    if (job.failedCount > 0) {
      try {
        failures = await _repository.failures(job.id);
      } catch (_) {
        // The authoritative status and controls remain usable if the optional
        // failure list cannot be loaded.
      }
    }
    if (_isTerminal(job)) {
      try {
        report = await _repository.report(job.id);
      } catch (_) {
        // A report may be generated shortly after the terminal job update.
      }
    }
    return _JobOutcome(failures: failures, report: report);
  }

  Future<void> _refreshOutcome(BirdJobStatus job) async {
    final outcome = await _readOutcome(job);
    if (isClosed || state.job?.id != job.id || !job.canReplace(state.job!)) return;
    emit(
      state.copyWith(
        report: outcome.report,
        failures: outcome.failures,
      ),
    );
  }

  bool _isTerminal(BirdJobStatus job) => job.state == BirdJobState.completed || job.state == BirdJobState.failed || job.state == BirdJobState.cancelled;

  void _configurePolling(BirdJobStatus job) {
    _pollTimer?.cancel();
    // 排队任务也会离开 queued；WS 不可用时必须继续轮询，不能只盯 running。
    if ((job.state == BirdJobState.running || job.state == BirdJobState.queued) && _events.currentState != EventConnectionState.connected) {
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => load());
    }
  }

  String _actionLabel(String action) => switch (action) {
    'pause' => '暂停',
    'resume' => '继续',
    'cancel' => '取消',
    'retry' => '重试',
    _ => '更新',
  };

  @override
  Future<void> close() async {
    _pollTimer?.cancel();
    await _eventSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _deviceSessionSubscription?.cancel();
    return super.close();
  }
}

class _JobOutcome {
  const _JobOutcome({required this.failures, this.report});

  final List<JobFailure> failures;
  final JobReport? report;
}
