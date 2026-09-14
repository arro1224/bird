import 'dart:async';

import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_history_filter.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/review_count_reducer.dart';
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
    bool clearNextCursor = false,
  }) => BatchListState(
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    items: items ?? this.items,
    current: clearCurrent ? null : current ?? this.current,
    filter: clearFilter ? null : filter ?? this.filter,
    nextCursor: clearNextCursor ? null : nextCursor ?? this.nextCursor,
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
  final Map<String, _OptimisticReviewCounts> _optimisticReviewCounts = {};
  int _loadGeneration = 0;

  Future<void> load({String? filter}) async {
    final filterChanged = filter != state.filter;
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        loading: true,
        loadingMore: false,
        items: filterChanged ? const [] : null,
        filter: filter,
        hasMore: filterChanged ? false : null,
        clearFilter: filter == null,
        clearNextCursor: filterChanged,
        clearError: true,
      ),
    );
    try {
      final results = await Future.wait<Object?>([
        _filteredPage(
          filter: filter,
          isCurrent: () => generation == _loadGeneration,
        ),
        _repository.current(),
      ]);
      if (isClosed || generation != _loadGeneration) return;
      final page = results[0] as BatchPage;
      final authoritativeItems = page.items;
      final authoritativeCurrent = results[1] as BatchSummary?;
      final reconciliation = _reconcileAuthoritativeCounts(
        authoritativeItems,
        authoritativeCurrent,
      );
      emit(
        state.copyWith(
          loading: false,
          items: reconciliation.items,
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          current: reconciliation.current,
          clearCurrent: reconciliation.current == null,
        ),
      );
      if (reconciliation.retry) _scheduleAuthoritativeRefresh();
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
      final page = await _filteredPage(
        filter: filter,
        cursor: cursor,
        isCurrent: () => generation == _loadGeneration,
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
          clearNextCursor: page.nextCursor == null,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(loadingMore: false, error: error));
    }
  }

  Future<BatchPage> _filteredPage({
    required String? filter,
    String? cursor,
    required bool Function() isCurrent,
  }) async {
    final localFilter = batchHistoryFilterFromValue(filter);
    final serverState = batchHistoryFilterValue(localFilter);
    final firstPage = await _repository.page(
      state: serverState,
      sort: 'created_at_desc',
      cursor: cursor,
    );
    if (localFilter == BatchHistoryFilter.all) return firstPage;

    final targetCount = firstPage.items.isEmpty ? 1 : firstPage.items.length;
    final matches = <BatchSummary>[];
    final knownIds = <String>{};
    void collect(Iterable<BatchSummary> items) {
      for (final item in items) {
        final filterCandidate = _withOptimisticCountsForFilter(item);
        if (knownIds.add(item.id) && matchesBatchHistoryFilter(filterCandidate, localFilter)) {
          matches.add(item);
        }
      }
    }

    collect(firstPage.items);
    var hasMore = firstPage.hasMore;
    var nextCursor = firstPage.nextCursor;
    final visitedCursors = <String>{?cursor};
    if (nextCursor == null || !visitedCursors.add(nextCursor)) {
      hasMore = false;
    }

    while (isCurrent() && hasMore && matches.length < targetCount) {
      final page = await _repository.page(
        state: serverState,
        sort: 'created_at_desc',
        cursor: nextCursor,
      );
      collect(page.items);
      final returnedCursor = page.nextCursor;
      hasMore = page.hasMore && returnedCursor != null && visitedCursors.add(returnedCursor);
      nextCursor = returnedCursor;
    }

    return BatchPage(
      items: matches,
      hasMore: hasMore,
      nextCursor: hasMore ? nextCursor : null,
    );
  }

  void _onDataChange(AppDataChange change) {
    ++_loadGeneration;
    if (change is ReviewDecisionChanged) {
      _applyReviewTransitions(
        change.projectId,
        [
          ReviewStateTransition(
            fileId: change.fileId,
            before: change.beforeKeepState,
            after: change.afterKeepState,
          ),
        ],
        queued: change.queued,
      );
      // A queued decision exists only on the phone. Reloading here would
      // return the last cached/box summary and overwrite the optimistic
      // counter delta. The sync acceptance event performs the authoritative
      // refresh after the box confirms the decision.
      if (change.queued) {
        _authoritativeRefreshTimer?.cancel();
        return;
      }
    } else if (change is BatchReviewDecisionChanged) {
      _applyReviewTransitions(
        change.projectId,
        change.transitions,
        queued: change.queued,
      );
      if (change.queued) {
        _authoritativeRefreshTimer?.cancel();
        return;
      }
    } else if (change.reason == 'offline_changes_synced') {
      for (final entry in _optimisticReviewCounts.entries.toList()) {
        _optimisticReviewCounts[entry.key] = entry.value.copyWith(
          queued: false,
          staleResponses: 0,
        );
      }
    }
    _scheduleAuthoritativeRefresh();
  }

  void _applyReviewTransitions(
    String? projectId,
    Iterable<ReviewStateTransition> transitions, {
    required bool queued,
  }) {
    if (projectId == null || projectId.isEmpty) return;
    final confirmed = transitions.toList(growable: false);
    if (confirmed.isEmpty) return;
    final source = state.current?.id == projectId ? state.current : state.items.where((item) => item.id == projectId).firstOrNull;
    final current = state.current?.id == projectId ? _withReviewTransitions(state.current!, confirmed) : state.current;
    final updatedItems = state.items
        .map(
          (item) => item.id == projectId ? _withReviewTransitions(item, confirmed) : item,
        )
        .toList(growable: false);
    final updated = current?.id == projectId ? current : updatedItems.where((item) => item.id == projectId).firstOrNull;
    if (source != null && updated != null) {
      _rememberOptimisticCounts(
        projectId,
        before: _countsOf(source),
        after: _countsOf(updated),
        queued: queued,
      );
    }
    final activeFilter = batchHistoryFilterFromValue(state.filter);
    final items = updatedItems.where((item) => matchesBatchHistoryFilter(item, activeFilter)).toList(growable: false);
    emit(state.copyWith(current: current, items: items));
  }

  BatchSummary _withOptimisticCountsForFilter(BatchSummary batch) {
    final marker = _optimisticReviewCounts[batch.id];
    if (marker == null) return batch;
    final counts = _countsOf(batch);
    if (counts == marker.expected || marker.staleValues.contains(counts)) {
      return _withReviewCounts(batch, marker.expected);
    }
    return batch;
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
    final reconciled = _withReviewTransitions(
      baseline,
      [
        for (final change in matching)
          ReviewStateTransition(
            fileId: change.fileId,
            before: change.beforeKeepState,
            after: change.afterKeepState,
          ),
      ],
    );
    final activeFilter = batchHistoryFilterFromValue(state.filter);
    final items = state.items.map((item) => item.id == baseline.id ? reconciled : item).where((item) => matchesBatchHistoryFilter(item, activeFilter)).toList(growable: false);
    _rememberOptimisticCounts(
      baseline.id,
      before: _countsOf(baseline),
      after: _countsOf(reconciled),
      queued: matching.any((change) => change.queued),
    );
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

  BatchSummary _withReviewTransitions(
    BatchSummary batch,
    Iterable<ReviewStateTransition> transitions,
  ) {
    final updated = applyReviewStateTransitions(
      GalleryReviewCounts(
        pending: batch.reviewCount,
        kept: batch.keepCount,
        discarded: batch.discardCount,
      ),
      transitions,
    );
    return batch.copyWith(
      reviewCount: updated.pending,
      keepCount: updated.kept,
      discardCount: updated.discarded,
    );
  }

  void _rememberOptimisticCounts(
    String projectId, {
    required GalleryReviewCounts before,
    required GalleryReviewCounts after,
    required bool queued,
  }) {
    if (before == after) return;
    final existing = _optimisticReviewCounts[projectId];
    _optimisticReviewCounts[projectId] = _OptimisticReviewCounts(
      staleValues: {
        ...?existing?.staleValues,
        before,
      },
      expected: after,
      queued: existing?.queued == true || queued,
    );
  }

  _AuthoritativeReviewReconciliation _reconcileAuthoritativeCounts(
    List<BatchSummary> items,
    BatchSummary? current,
  ) {
    var reconciledItems = items;
    var reconciledCurrent = current;
    var retry = false;

    for (final entry in _optimisticReviewCounts.entries.toList()) {
      final projectId = entry.key;
      final marker = entry.value;
      final authoritative = current?.id == projectId ? current : items.where((item) => item.id == projectId).firstOrNull;
      if (authoritative == null) continue;
      final counts = _countsOf(authoritative);

      if (counts == marker.expected) {
        reconciledItems = _replaceReviewCounts(
          reconciledItems,
          projectId,
          marker.expected,
        );
        if (reconciledCurrent?.id == projectId) {
          reconciledCurrent = _withReviewCounts(
            reconciledCurrent!,
            marker.expected,
          );
        }
        _optimisticReviewCounts.remove(projectId);
        continue;
      }
      if (!marker.staleValues.contains(counts)) {
        // A different authoritative value means the box has advanced for
        // another reason. Accept it rather than layering a stale local delta.
        _optimisticReviewCounts.remove(projectId);
        continue;
      }

      reconciledItems = _replaceReviewCounts(
        reconciledItems,
        projectId,
        marker.expected,
      );
      if (reconciledCurrent?.id == projectId) {
        reconciledCurrent = _withReviewCounts(
          reconciledCurrent!,
          marker.expected,
        );
      }
      if (!marker.queued && marker.staleResponses < 2) {
        retry = true;
        _optimisticReviewCounts[projectId] = marker.copyWith(
          staleResponses: marker.staleResponses + 1,
        );
      }
    }

    return _AuthoritativeReviewReconciliation(
      items: reconciledItems,
      current: reconciledCurrent,
      retry: retry,
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

GalleryReviewCounts _countsOf(BatchSummary batch) => GalleryReviewCounts(
  pending: batch.reviewCount,
  kept: batch.keepCount,
  discarded: batch.discardCount,
);

BatchSummary _withReviewCounts(
  BatchSummary batch,
  GalleryReviewCounts counts,
) => batch.copyWith(
  reviewCount: counts.pending,
  keepCount: counts.kept,
  discardCount: counts.discarded,
);

List<BatchSummary> _replaceReviewCounts(
  List<BatchSummary> items,
  String projectId,
  GalleryReviewCounts counts,
) => items
    .map(
      (item) => item.id == projectId ? _withReviewCounts(item, counts) : item,
    )
    .toList(growable: false);

class _OptimisticReviewCounts {
  const _OptimisticReviewCounts({
    required this.staleValues,
    required this.expected,
    required this.queued,
    this.staleResponses = 0,
  });

  final Set<GalleryReviewCounts> staleValues;
  final GalleryReviewCounts expected;
  final bool queued;
  final int staleResponses;

  _OptimisticReviewCounts copyWith({
    bool? queued,
    int? staleResponses,
  }) => _OptimisticReviewCounts(
    staleValues: staleValues,
    expected: expected,
    queued: queued ?? this.queued,
    staleResponses: staleResponses ?? this.staleResponses,
  );
}

class _AuthoritativeReviewReconciliation {
  const _AuthoritativeReviewReconciliation({
    required this.items,
    required this.current,
    required this.retry,
  });

  final List<BatchSummary> items;
  final BatchSummary? current;
  final bool retry;
}
