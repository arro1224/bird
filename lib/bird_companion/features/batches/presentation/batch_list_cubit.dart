import 'dart:async';

import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BatchListState {
  const BatchListState({this.loading = false, this.loadingMore = false, this.items = const [], this.current, this.filter, this.nextCursor, this.hasMore = false, this.error, this.resumeId});
  final bool loading, loadingMore, hasMore;
  final List<BatchSummary> items;
  final BatchSummary? current;
  final String? filter, nextCursor, resumeId;
  final Object? error;
  BatchListState copyWith({
    bool? loading,
    bool? loadingMore,
    List<BatchSummary>? items,
    BatchSummary? current,
    String? filter,
    String? nextCursor,
    bool? hasMore,
    Object? error,
    String? resumeId,
    bool clearError = false,
    bool clearResume = false,
    bool clearCurrent = false,
    bool clearFilter = false,
  }) => BatchListState(
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    items: items ?? this.items,
    current: clearCurrent ? null : current ?? this.current,
    filter: clearFilter ? null : filter ?? this.filter,
    nextCursor: nextCursor ?? this.nextCursor,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : error ?? this.error,
    resumeId: clearResume ? null : resumeId ?? this.resumeId,
  );
}

class BatchListCubit extends Cubit<BatchListState> {
  BatchListCubit(this._repository, [SessionRefreshCoordinator? refreshCoordinator, AppDataChangeBus? dataChanges]) : super(const BatchListState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => load(filter: state.filter));
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.batches) || change.affects(AppDataResource.photos)).listen((_) => load(filter: state.filter));
  }
  final BatchRepository _repository;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;

  Future<void> load({String? filter}) async {
    emit(state.copyWith(loading: true, filter: filter, clearFilter: filter == null, clearError: true));
    try {
      final results = await Future.wait([_repository.page(state: filter, sort: 'created_at_desc'), _repository.current()]);
      final page = results[0] as dynamic;
      final current = results[1] as BatchSummary?;
      emit(
        state.copyWith(
          loading: false,
          items: page.items,
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
          current: current,
          clearCurrent: current == null,
        ),
      );
    } catch (error) {
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.nextCursor == null) return;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.page(state: state.filter, sort: 'created_at_desc', cursor: state.nextCursor);
      final known = state.items.map((item) => item.id).toSet();
      emit(state.copyWith(loadingMore: false, items: [...state.items, ...page.items.where((item) => known.add(item.id))], hasMore: page.hasMore, nextCursor: page.nextCursor));
    } catch (error) {
      emit(state.copyWith(loadingMore: false, error: error));
    }
  }

  Future<void> resume(String id) async {
    emit(state.copyWith(resumeId: id, clearError: true));
    try {
      await _repository.resume(id);
      await load(filter: state.filter);
    } catch (error) {
      emit(state.copyWith(error: error, clearResume: true));
    }
  }

  @override
  Future<void> close() async {
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}
