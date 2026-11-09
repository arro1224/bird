import 'dart:async';

import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class JobCenterState {
  const JobCenterState({this.loading = false, this.loadingMore = false, this.jobs = const [], this.hasMore = false, this.nextCursor, this.error, this.actingJobId});
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? nextCursor;
  final List<BirdJobStatus> jobs;
  final Object? error;
  final String? actingJobId;
  JobCenterState copyWith({bool? loading, bool? loadingMore, List<BirdJobStatus>? jobs, bool? hasMore, String? nextCursor, Object? error, String? actingJobId, bool clearError = false, bool clearActing = false, bool clearCursor = false}) =>
      JobCenterState(
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        jobs: jobs ?? this.jobs,
        hasMore: hasMore ?? this.hasMore,
        nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
        error: clearError ? null : error ?? this.error,
        actingJobId: clearActing ? null : actingJobId ?? this.actingJobId,
      );
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
  bool _loadInFlight = false;

  void _mergeEvent(Map<String, dynamic> payload) {
    try {
      final raw = payload['job'];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : payload;
      final updated = BirdJobStatus.fromJson(data);
      if (updated.id.isEmpty) return;
      final jobs = [...state.jobs];
      final index = jobs.indexWhere((job) => job.id == updated.id);
      if (index < 0) {
        jobs.insert(0, updated);
      } else {
        final current = jobs[index];
        // 事件可能乱序/重放；旧版本不得覆盖列表里较新的快照。
        if (current.version != null && updated.version != null && updated.version! < current.version!) return;
        jobs[index] = updated;
      }
      emit(state.copyWith(jobs: jobs, clearError: true));
    } catch (_) {
      // 部分/破损 payload 交给下一次全量刷新，不让单条事件打断订阅。
    }
  }

  Future<void> load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final page = await _repository.page();
      emit(state.copyWith(loading: false, jobs: page.items, hasMore: page.hasMore && page.nextCursor != null, nextCursor: page.nextCursor, clearCursor: page.nextCursor == null));
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          jobs: const [],
          hasMore: false,
          clearCursor: true,
          error: error,
        ),
      );
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (state.loadingMore || !state.hasMore || cursor == null) return;
    emit(state.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await _repository.page(cursor: cursor);
      // 与“加载更多”期间到达的事件合并：用响应时的全集按 id 去重，
      // 不用请求前的旧快照判断，避免重复行。
      final jobs = [...state.jobs];
      final known = jobs.map((job) => job.id).toSet();
      for (final job in page.items) {
        if (known.add(job.id)) jobs.add(job);
      }
      emit(
        state.copyWith(
          loadingMore: false,
          jobs: jobs,
          hasMore: page.hasMore && page.nextCursor != null && page.nextCursor != cursor,
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
        ),
      );
    } catch (error) {
      emit(state.copyWith(loadingMore: false, error: error));
    }
  }

  Future<void> control(String jobId, String action) async {
    if (state.actingJobId != null) return;
    final current = state.jobs.where((job) => job.id == jobId).firstOrNull;
    if (current == null) {
      emit(
        state.copyWith(
          error: ArgumentError.value(jobId, 'jobId', 'Unknown task'),
        ),
      );
      return;
    }
    final wireAction = action == 'retry' ? 'retry_failed' : action;
    if (!jobControlActions.contains(wireAction) || !current.availableActions.contains(wireAction)) {
      emit(
        state.copyWith(
          error: StateError('$wireAction is unavailable for $jobId'),
        ),
      );
      return;
    }
    final version = current.version;
    if (version == null) {
      emit(
        state.copyWith(
          error: StateError('The task version is unavailable'),
        ),
      );
      return;
    }
    emit(state.copyWith(actingJobId: jobId, clearError: true));
    try {
      final updated = await _repository.control(
        jobId,
        wireAction,
        version: version,
      );
      final jobs = state.jobs.map((job) => job.id == jobId ? updated : job).toList();
      _dataChanges?.publish({AppDataResource.jobs, AppDataResource.device}, reason: 'job_$action');
      emit(state.copyWith(jobs: jobs, clearActing: true));
    } catch (error) {
      emit(state.copyWith(error: error, clearActing: true));
    }
  }

  Future<void> delete(String jobId) async {
    if (state.actingJobId != null) return;
    final current = state.jobs.where((job) => job.id == jobId).firstOrNull;
    if (current?.canDelete != true) {
      emit(
        state.copyWith(
          error: StateError('delete is unavailable for $jobId'),
        ),
      );
      return;
    }
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
