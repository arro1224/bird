import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
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
  });
  final bool loading;
  final bool controlling;
  final BirdJobStatus? job;
  final JobReport? report;
  final List<JobFailure> failures;
  final Object? error;
  final String? message;

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
  }) => JobDetailState(
    loading: loading ?? this.loading,
    controlling: controlling ?? this.controlling,
    job: job ?? this.job,
    report: clearReport ? null : report ?? this.report,
    failures: failures ?? this.failures,
    error: clearError ? null : error ?? this.error,
    message: clearMessage ? null : message ?? this.message,
  );
}

class JobDetailCubit extends Cubit<JobDetailState> {
  JobDetailCubit(this._repository, this._events, this.jobId, [this._refreshCoordinator, this._dataChanges]) : super(const JobDetailState()) {
    _eventSubscription = _events.events.where((event) => event.type == 'job_updated' || event.type == 'job_progress' || event.type == 'job_state_changed').listen(_onEvent);
    _connectionSubscription = _events.connectionStates.listen((_) {
      final job = state.job;
      if (job != null) _configurePolling(job);
    });
  }

  final JobRepository _repository;
  final EventClient _events;
  final String jobId;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<EventConnectionState>? _connectionSubscription;
  Timer? _pollTimer;
  bool _loadInFlight = false;

  Future<void> load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(state.copyWith(loading: true, clearError: true, clearMessage: true));
    try {
      final job = await _repository.detail(jobId);
      final outcome = await _readOutcome(job);
      emit(
        state.copyWith(
          loading: false,
          job: job,
          report: outcome.report,
          clearReport: outcome.report == null,
          failures: outcome.failures,
        ),
      );
      _configurePolling(job);
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> control(String action) async {
    if (state.controlling) return;
    final current = state.job;
    if (current == null) return;
    emit(state.copyWith(controlling: true, clearError: true, clearMessage: true));
    try {
      final updated = await _repository.control(
        jobId,
        action == 'retry' ? 'retry_failed' : action,
        version: current.version,
      );
      final outcome = await _readOutcome(updated);
      emit(
        state.copyWith(
          job: updated,
          report: outcome.report,
          clearReport: outcome.report == null,
          failures: outcome.failures,
        ),
      );
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_$action');
      emit(
        state.copyWith(
          controlling: false,
          message: '任务已${_actionLabel(action)}。',
        ),
      );
    } catch (error) {
      emit(state.copyWith(controlling: false, error: error));
    }
  }

  Future<bool> delete() async {
    if (state.controlling || state.job?.canDelete != true) return false;
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
    final update = BirdJobStatus.fromJson(event.payload);
    if (update.id.isEmpty || update.id != jobId) return;
    emit(state.copyWith(job: update, clearError: true));
    _configurePolling(update);
    if (_isTerminal(update)) {
      unawaited(_refreshOutcome(update));
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
    if (isClosed || state.job?.id != job.id) return;
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
    if (job.state == BirdJobState.running && _events.currentState != EventConnectionState.connected) {
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
    return super.close();
  }
}

class _JobOutcome {
  const _JobOutcome({required this.failures, this.report});

  final List<JobFailure> failures;
  final JobReport? report;
}
