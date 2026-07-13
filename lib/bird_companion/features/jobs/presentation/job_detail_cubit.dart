import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobDetailState {
  const JobDetailState({this.loading = false, this.controlling = false, this.job, this.failures = const [], this.error, this.message});
  final bool loading;
  final bool controlling;
  final BirdJobStatus? job;
  final List<JobFailure> failures;
  final Object? error;
  final String? message;

  JobDetailState copyWith({bool? loading, bool? controlling, BirdJobStatus? job, List<JobFailure>? failures, Object? error, String? message, bool clearError = false, bool clearMessage = false}) => JobDetailState(
    loading: loading ?? this.loading,
    controlling: controlling ?? this.controlling,
    job: job ?? this.job,
    failures: failures ?? this.failures,
    error: clearError ? null : error ?? this.error,
    message: clearMessage ? null : message ?? this.message,
  );
}

class JobDetailCubit extends Cubit<JobDetailState> {
  JobDetailCubit(this._repository, this._events, this.jobId, [this._refreshCoordinator, this._dataChanges]) : super(const JobDetailState()) {
    _eventSubscription = _events.events.where((event) => event.type == 'job_updated' || event.type == 'job_progress' || event.type == 'job_state_changed').listen(_onEvent);
  }

  final JobRepository _repository;
  final EventClient _events;
  final String? jobId;
  final SessionRefreshCoordinator? _refreshCoordinator;
  final AppDataChangeBus? _dataChanges;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  Timer? _pollTimer;

  Future<void> load() async {
    final id = jobId;
    if (id == null) {
      emit(
        const JobDetailState(
          job: BirdJobStatus(id: 'demo-analysis-01', type: BirdJobType.analysis, state: BirdJobState.running, progress: .5, totalCount: 1200, finishedCount: 600, currentFile: 'DSC_0120.NEF'),
        ),
      );
      return;
    }
    emit(state.copyWith(loading: true, clearError: true, clearMessage: true));
    try {
      final job = await _repository.detail(id);
      List<JobFailure> failures = const [];
      if (job.failedCount > 0) {
        try {
          failures = await _repository.failures(id);
        } catch (_) {
          // A task can still be controlled when the optional failure-detail
          // endpoint is temporarily unavailable.
        }
      }
      emit(state.copyWith(loading: false, job: job, failures: failures));
      _configurePolling(job);
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<void> control(String action) async {
    if (jobId == null || state.controlling) return;
    emit(state.copyWith(controlling: true, clearError: true, clearMessage: true));
    try {
      await _repository.control(jobId!, action);
      await load();
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_$action');
      emit(state.copyWith(controlling: false, message: '任务已${_actionLabel(action)}。'));
    } catch (error) {
      emit(state.copyWith(controlling: false, error: error, message: '任务操作失败：$error'));
    }
  }

  Future<bool> delete() async {
    if (jobId == null || state.controlling || state.job?.canDelete != true) return false;
    emit(state.copyWith(controlling: true, clearError: true, clearMessage: true));
    try {
      await _repository.delete(jobId!);
      _refreshCoordinator?.requestRefresh();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_deleted');
      emit(state.copyWith(controlling: false, message: '任务已从盒子任务列表移除'));
      return true;
    } catch (error) {
      emit(state.copyWith(controlling: false, error: error, message: '删除任务失败：$error'));
      return false;
    }
  }

  void _onEvent(DeviceEvent event) {
    final update = BirdJobStatus.fromJson(event.payload);
    if (update.id.isEmpty || update.id != jobId) return;
    emit(state.copyWith(job: update, clearError: true));
    _configurePolling(update);
  }

  void _configurePolling(BirdJobStatus job) {
    _pollTimer?.cancel();
    if (job.state == BirdJobState.running) {
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
    return super.close();
  }
}
