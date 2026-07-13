import 'dart:async';

import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobCenterState {
  const JobCenterState({this.loading = false, this.jobs = const [], this.isDemo = false, this.error, this.actingJobId});
  final bool loading, isDemo;
  final List<BirdJobStatus> jobs;
  final Object? error;
  final String? actingJobId;
  JobCenterState copyWith({bool? loading, List<BirdJobStatus>? jobs, bool? isDemo, Object? error, String? actingJobId, bool clearError = false, bool clearActing = false}) =>
      JobCenterState(loading: loading ?? this.loading, jobs: jobs ?? this.jobs, isDemo: isDemo ?? this.isDemo, error: clearError ? null : error ?? this.error, actingJobId: clearActing ? null : actingJobId ?? this.actingJobId);
}

class JobCenterCubit extends Cubit<JobCenterState> {
  JobCenterCubit(this._repository, [SessionRefreshCoordinator? refreshCoordinator, EventClient? eventClient, AppDataChangeBus? dataChanges]) : _dataChanges = dataChanges, super(const JobCenterState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => load());
    _eventSubscription = eventClient?.events.where((event) => event.type == 'job_updated' || event.type == 'job_progress' || event.type == 'job_state_changed').listen((event) => _mergeEvent(event.payload));
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.jobs)).listen((_) => load());
  }
  final JobRepository _repository;
  final AppDataChangeBus? _dataChanges;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<DeviceEvent>? _eventSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;

  void _mergeEvent(Map<String, dynamic> payload) {
    final updated = BirdJobStatus.fromJson(payload);
    if (updated.id.isEmpty) return;
    final jobs = [...state.jobs];
    final index = jobs.indexWhere((job) => job.id == updated.id);
    if (index < 0) {
      jobs.insert(0, updated);
    } else {
      jobs[index] = updated;
    }
    emit(state.copyWith(jobs: jobs, isDemo: false, clearError: true));
  }

  Future<void> load() async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final jobs = await _repository.list();
      emit(state.copyWith(loading: false, jobs: jobs));
    } catch (error) {
      emit(state.copyWith(loading: false, jobs: const [], error: error));
    }
  }

  void showDemo() => emit(
    state.copyWith(
      jobs: const [BirdJobStatus(id: 'demo-analysis-01', type: BirdJobType.analysis, state: BirdJobState.running, progress: .5, totalCount: 1200, finishedCount: 600, currentFile: 'DSC_0120.NEF')],
      isDemo: true,
      clearError: true,
    ),
  );

  Future<void> control(String jobId, String action) async {
    if (state.actingJobId != null || state.isDemo) return;
    emit(state.copyWith(actingJobId: jobId, clearError: true));
    try {
      await _repository.control(jobId, action);
      final updated = await _repository.detail(jobId);
      final jobs = state.jobs.map((job) => job.id == jobId ? updated : job).toList();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_$action');
      emit(state.copyWith(jobs: jobs, clearActing: true));
    } catch (error) {
      emit(state.copyWith(error: error, clearActing: true));
    }
  }

  Future<void> delete(String jobId) async {
    if (state.actingJobId != null || state.isDemo) return;
    emit(state.copyWith(actingJobId: jobId, clearError: true));
    try {
      await _repository.delete(jobId);
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_deleted');
      emit(state.copyWith(jobs: state.jobs.where((job) => job.id != jobId).toList(), clearActing: true));
    } catch (error) {
      emit(state.copyWith(error: error, clearActing: true));
    }
  }

  @override
  Future<void> close() async {
    await _refreshSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}
