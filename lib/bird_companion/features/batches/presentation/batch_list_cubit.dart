import 'dart:async';

import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
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
  BatchListCubit(
    this._repository, [
    SessionRefreshCoordinator? refreshCoordinator,
    AppDataChangeBus? dataChanges,
    this._authoritativeRefreshDelay = const Duration(milliseconds: 120),
  ]) : super(const BatchListState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => load(filter: state.filter));
    _dataSubscription = dataChanges?.changes
        .where(
          (change) => change.affects(AppDataResource.batches) || change.affects(AppDataResource.photos),
        )
        .listen(_onDataChange);
  }
  final BatchRepository _repository;
  final Duration _authoritativeRefreshDelay;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _authoritativeRefreshTimer;
  int _loadGeneration = 0;

  Future<void> load({String? filter}) async {
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        loading: true,
        loadingMore: false,
        filter: filter,
        clearFilter: filter == null,
        clearError: true,
      ),
    );
    try {
      final results = await Future.wait([
        _repository.page(state: filter, sort: 'created_at_desc'),
        _repository.current(),
      ]);
      if (isClosed || generation != _loadGeneration) return;
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
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(loading: false, error: error));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.nextCursor == null) return;
    final generation = _loadGeneration;
    final cursor = state.nextCursor;
    final filter = state.filter;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repository.page(
        state: filter,
        sort: 'created_at_desc',
        cursor: cursor,
      );
      if (isClosed || generation != _loadGeneration) return;
      final known = state.items.map((item) => item.id).toSet();
      emit(
        state.copyWith(
          loadingMore: false,
          items: [
            ...state.items,
            ...page.items.where((item) => known.add(item.id)),
          ],
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(loadingMore: false, error: error));
    }
  }

  void _onDataChange(AppDataChange change) {
    ++_loadGeneration;
    if (change is ReviewDecisionChanged) {
      _applyReviewDelta(change);
      // A queued decision exists only on the phone. Reloading here would
      // return the last cached/box summary and overwrite the optimistic
      // counter delta. The sync acceptance event performs the authoritative
      // refresh after the box confirms the decision.
      if (change.queued) {
        _authoritativeRefreshTimer?.cancel();
        return;
      }
    }
    _scheduleAuthoritativeRefresh();
  }

  void _applyReviewDelta(ReviewDecisionChanged change) {
    final projectId = change.projectId;
    if (projectId == null || projectId.isEmpty) return;
    final current = state.current?.id == projectId ? _withReviewDelta(state.current!, change) : state.current;
    final items = state.items
        .map(
          (item) => item.id == projectId ? _withReviewDelta(item, change) : item,
        )
        .toList(growable: false);
    emit(state.copyWith(current: current, items: items));
  }

  /// Replays the exact review changes made while the nested detail route was
  /// covering the album. Recomputing from the route-entry summary makes this
  /// idempotent when the live listener already applied the same events, while
  /// still restoring optimistic counts if that listener was inactive.
  void reconcileReviewChanges(
    BatchSummary baseline,
    Iterable<ReviewDecisionChanged> changes,
  ) {
    if (isClosed) return;
    final matching = changes.where((change) => change.projectId == baseline.id).toList(growable: false);
    if (matching.isEmpty) return;
    var reconciled = baseline;
    for (final change in matching) {
      reconciled = _withReviewDelta(reconciled, change);
    }
    final items = state.items.map((item) => item.id == baseline.id ? reconciled : item).toList(growable: false);
    emit(
      state.copyWith(
        current: state.current?.id == baseline.id ? reconciled : state.current,
        items: items,
      ),
    );
    if (matching.any((change) => !change.queued)) {
      _scheduleAuthoritativeRefresh();
    } else {
      _authoritativeRefreshTimer?.cancel();
    }
  }

  BatchSummary _withReviewDelta(
    BatchSummary batch,
    ReviewDecisionChanged change,
  ) {
    final before = _reviewBucket(change.beforeKeepState);
    final after = _reviewBucket(change.afterKeepState);
    if (before == after) return batch;
    var pending = batch.reviewCount;
    var keep = batch.keepCount;
    var discard = batch.discardCount;

    switch (before) {
      case _ReviewBucket.pending:
        pending = (pending - 1).clamp(0, pending).toInt();
        break;
      case _ReviewBucket.keep:
        keep = (keep - 1).clamp(0, keep).toInt();
        break;
      case _ReviewBucket.discard:
        discard = (discard - 1).clamp(0, discard).toInt();
        break;
    }
    switch (after) {
      case _ReviewBucket.pending:
        pending += 1;
        break;
      case _ReviewBucket.keep:
        keep += 1;
        break;
      case _ReviewBucket.discard:
        discard += 1;
        break;
    }
    return batch.copyWith(
      reviewCount: pending,
      keepCount: keep,
      discardCount: discard,
    );
  }

  void _scheduleAuthoritativeRefresh() {
    _authoritativeRefreshTimer?.cancel();
    _authoritativeRefreshTimer = Timer(_authoritativeRefreshDelay, () {
      if (!isClosed) load(filter: state.filter);
    });
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
    ++_loadGeneration;
    _authoritativeRefreshTimer?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}

enum _ReviewBucket { pending, keep, discard }

_ReviewBucket _reviewBucket(KeepState state) => switch (state) {
  KeepState.pending => _ReviewBucket.pending,
  KeepState.keep || KeepState.featured => _ReviewBucket.keep,
  KeepState.discard => _ReviewBucket.discard,
};
