import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/gallery/domain/gallery_timing.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query_plan.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:aves/bird_companion/features/gallery/domain/review_count_reducer.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

PhotoQuery resolveInitialPhotoQuery({
  required PhotoQuery fallback,
  required Map<dynamic, dynamic>? savedView,
  required bool restoreSavedView,
  String? preferredSort,
}) {
  final restored = !restoreSavedView || savedView == null ? fallback : PhotoQuery.fromJson(Map<String, dynamic>.from(savedView));
  return preferredSort == null ? restored : restored.copyWith(sort: preferredSort, clearCursor: true);
}

String albumViewCacheKey({
  required String? deviceNamespace,
  required String projectId,
}) {
  final normalized = deviceNamespace?.trim();
  final namespace = normalized == null || normalized.isEmpty ? 'unbound' : normalized;
  return 'album:view:$namespace:$projectId';
}

class GalleryState {
  const GalleryState({
    this.loading = false,
    this.items = const [],
    this.query = const PhotoQuery(),
    this.hasMore = true,
    this.fromCache = false,
    this.cachedAt,
    this.pendingOperationCount = 0,
    this.conflictOperationCount = 0,
    this.conflictFileIds = const [],
    this.pendingCount,
    this.keepCount,
    this.discardCount,
    this.error,
    this.gridColumns = 3,
    this.showRatingOverlay = true,
    this.filtering = false,
    this.scannedCount = 0,
    this.matchedCount = 0,
    this.resultComplete = true,
    this.cacheScope = PhotoCacheScope.none,
  });
  final bool loading, hasMore;
  final bool fromCache;
  final List<PhotoSummary> items;
  final PhotoQuery query;
  final DateTime? cachedAt;
  final int pendingOperationCount;
  final int conflictOperationCount;
  final List<String> conflictFileIds;
  final int? pendingCount;
  final int? keepCount;
  final int? discardCount;
  final Object? error;
  final int gridColumns;
  final bool showRatingOverlay;
  final bool filtering;
  final int scannedCount;
  final int matchedCount;
  final bool resultComplete;
  final PhotoCacheScope cacheScope;
  GalleryState copyWith({
    bool? loading,
    List<PhotoSummary>? items,
    PhotoQuery? query,
    bool? hasMore,
    bool? fromCache,
    DateTime? cachedAt,
    int? pendingOperationCount,
    int? conflictOperationCount,
    List<String>? conflictFileIds,
    int? pendingCount,
    int? keepCount,
    int? discardCount,
    Object? error,
    bool clearError = false,
    int? gridColumns,
    bool? showRatingOverlay,
    bool? filtering,
    int? scannedCount,
    int? matchedCount,
    bool? resultComplete,
    PhotoCacheScope? cacheScope,
  }) => GalleryState(
    loading: loading ?? this.loading,
    items: items ?? this.items,
    query: query ?? this.query,
    hasMore: hasMore ?? this.hasMore,
    fromCache: fromCache ?? this.fromCache,
    cachedAt: cachedAt ?? this.cachedAt,
    pendingOperationCount: pendingOperationCount ?? this.pendingOperationCount,
    conflictOperationCount: conflictOperationCount ?? this.conflictOperationCount,
    conflictFileIds: conflictFileIds ?? this.conflictFileIds,
    pendingCount: pendingCount ?? this.pendingCount,
    keepCount: keepCount ?? this.keepCount,
    discardCount: discardCount ?? this.discardCount,
    error: clearError ? null : error ?? this.error,
    gridColumns: gridColumns ?? this.gridColumns,
    showRatingOverlay: showRatingOverlay ?? this.showRatingOverlay,
    filtering: filtering ?? this.filtering,
    scannedCount: scannedCount ?? this.scannedCount,
    matchedCount: matchedCount ?? this.matchedCount,
    resultComplete: resultComplete ?? this.resultComplete,
    cacheScope: cacheScope ?? this.cacheScope,
  );

  String? get firstConflictFileId => conflictFileIds.isEmpty ? null : conflictFileIds.first;

  GalleryReviewCounts? get reviewCounts {
    final pending = pendingCount;
    final kept = keepCount;
    final discarded = discardCount;
    if (pending == null || kept == null || discarded == null) return null;
    return GalleryReviewCounts(
      pending: pending,
      kept: kept,
      discarded: discarded,
    );
  }
}

class GalleryCubit extends Cubit<GalleryState> {
  GalleryCubit(
    this._repo,
    this.batchId, [
    SessionRefreshCoordinator? refreshCoordinator,
    AppDataChangeBus? dataChanges,
    this._cache,
    this._pendingOperations,
    this._activeDeviceId,
    this._checkpointStore,
    this._settingsStore,
  ]) : super(
         GalleryState(
           gridColumns: _settingsGridColumns(_settingsStore),
           showRatingOverlay: _settingsShowRatingOverlay(_settingsStore),
         ),
       ) {
    _boundDevice = _currentDevice;
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => _queueBackgroundRefresh());
    _dataSubscription = dataChanges?.changes
        .where(
          (change) => change.affects(AppDataResource.photos) || change.affects(AppDataResource.cache) || change.affects(AppDataResource.photoPreferences),
        )
        .listen(_handleDataChange);
  }
  final PhotoRepository _repo;
  final String batchId;
  final LocalCache? _cache;
  final PendingOperationStore? _pendingOperations;
  final String? Function()? _activeDeviceId;
  final ReviewCheckpointStore? _checkpointStore;
  final SettingsStore? _settingsStore;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _searchDebounce;
  Timer? _backgroundRefresh;
  final _pendingChanges = <AppDataChange>{};
  var _reconnectQueued = false;
  var _drainingChanges = false;
  var _closing = false;
  String? _boundDevice;
  String? _runningQueryKey;
  Future<void>? _runningRefresh;
  DateTime? _lastCompleteRefresh;
  int _requestGeneration = 0;
  PhotoQueryCancellationToken? _activeCancellation;
  GalleryTiming? _visibleTiming;

  GalleryTiming? get visibleTiming => _visibleTiming;
  String? get _currentDevice => _activeDeviceId?.call()?.trim();

  Future<void> restoreAndRefresh(
    PhotoQuery fallback, {
    bool restoreSavedView = true,
    GalleryTiming? timing,
  }) async {
    final raw = restoreSavedView ? _cache?.read<Map>(_viewCacheKey()) : null;
    final preferences = _settingsStore?.read();
    final preferredFallback = preferences == null
        ? fallback
        : _applyPhotoDefaults(
            fallback.copyWith(
              sort: photoQuerySortFromPreference(preferences.sortOrder),
              clearCursor: true,
            ),
            preferences,
          );
    final restored = resolveInitialPhotoQuery(
      fallback: preferredFallback,
      savedView: raw,
      restoreSavedView: restoreSavedView,
      preferredSort: preferences == null ? null : photoQuerySortFromPreference(preferences.sortOrder),
    );
    await refresh(query: restored, timing: timing);
  }

  /// Seeds the batch summary counters carried by the route into retained
  /// gallery state. Subsequent photo refreshes deliberately preserve them.
  void seedReviewCounts({
    int? pendingCount,
    int? keepCount,
    int? discardCount,
  }) {
    if (isClosed || (pendingCount == null && keepCount == null && discardCount == null)) {
      return;
    }
    emit(
      state.copyWith(
        pendingCount: pendingCount == null ? null : _nonNegative(pendingCount),
        keepCount: keepCount == null ? null : _nonNegative(keepCount),
        discardCount: discardCount == null ? null : _nonNegative(discardCount),
      ),
    );
  }

  void search(String value) {
    _bindCurrentDevice();
    _searchDebounce?.cancel();
    _cancelActiveQuery(invalidateGeneration: true);
    final query = state.query.copyWith(search: value.trim(), clearCursor: true);
    emit(state.copyWith(query: query, filtering: false, loading: false));
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchDebounce = null;
      unawaited(refresh(query: query));
    });
  }

  Future<void> refresh({PhotoQuery? query, GalleryTiming? timing}) {
    if (_closing || isClosed) return Future.value();
    _bindCurrentDevice();
    final q = (query ?? state.query).copyWith(clearCursor: true);
    final key = jsonEncode(q.toJson());
    final running = _runningRefresh;
    if (running != null && _runningQueryKey == key) {
      timing?.event('query_joined');
      return running;
    }
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _cancelActiveQuery();
    final device = _boundDevice;
    final task = _executeRefresh(q, device, timing);
    _runningQueryKey = key;
    _runningRefresh = task;
    unawaited(task.whenComplete(() {
      if (!identical(_runningRefresh, task)) return;
      _runningRefresh = null;
      _runningQueryKey = null;
      _scheduleBackgroundRefresh();
    }));
    return task;
  }

  Future<void> _executeRefresh(PhotoQuery q, String? device, GalleryTiming? timing) async {
    final generation = ++_requestGeneration;
    final filtering = PhotoQueryPlan(q).requiresLocalScan;
    final trace = timing ?? GalleryTiming.start();
    trace?.event('query_start', {
      'local_scan': filtering,
      'recognized_only': q.recognitionState == 'recognized',
    });
    final cancellationToken = PhotoQueryCancellationToken(isCurrent: () => _isCurrent(generation, device));
    _activeCancellation = cancellationToken;
    emit(
      state.copyWith(
        loading: true,
        filtering: filtering,
        scannedCount: 0,
        matchedCount: 0,
        resultComplete: !filtering,
        cacheScope: PhotoCacheScope.none,
        query: q,
        clearError: true,
      ),
    );
    try {
      Future<PhotoPage> load() => _repo is PhotoQueryExecutionRepository
          ? (_repo as PhotoQueryExecutionRepository).pageWithProgress(
              batchId,
              q,
              cancellationToken: cancellationToken,
              onProgress: (progress) => _onQueryProgress(
                generation,
                device,
                progress,
                trace,
              ),
            )
          : _repo.page(batchId, q);
      final p = await (trace == null ? load() : trace.run(load));
      if (!_isCurrent(generation, device)) {
        trace?.event('superseded');
        return;
      }
      _activeCancellation = null;
      if (p.resultComplete) {
        _reconnectQueued = false;
        _lastCompleteRefresh = DateTime.now();
      }
      final operationCounts = _operationCounts();
      _visibleTiming = trace;
      if (trace != null) {
        trace.event('result_ready', {
          'visible': p.items.length,
          'scanned': p.scannedCount,
          'matched': p.matchedCount ?? p.items.length,
          'requests': trace.requests,
          'from_cache': p.fromCache,
          'cache_scope': p.cacheScope.name,
          'complete': p.resultComplete,
        });
      }
      emit(
        state.copyWith(
          loading: false,
          filtering: false,
          items: p.items,
          query: q.next(p.nextCursor),
          hasMore: p.hasMore && p.nextCursor != null,
          fromCache: p.fromCache,
          cachedAt: p.cachedAt,
          scannedCount: p.scannedCount,
          matchedCount: p.matchedCount ?? p.items.length,
          resultComplete: p.resultComplete && _pendingChanges.isEmpty,
          cacheScope: p.cacheScope,
          pendingOperationCount: operationCounts.pending,
          conflictOperationCount: operationCounts.conflict,
          conflictFileIds: operationCounts.conflictFileIds,
        ),
      );
      await _cache?.write(albumViewCacheKey(deviceNamespace: device, projectId: batchId), q.toJson());
      if (_isCurrent(generation, device) && device != null && device.isNotEmpty) {
        try {
          await _checkpointStore?.updateQuery(
            deviceId: device,
            batchId: batchId,
            query: q,
          );
        } catch (_) {
          // Query persistence is a resume aid and must not turn a successful
          // gallery request into a visible load failure.
        }
      }
    } on PhotoQueryCancelled {
      trace?.event('cancelled');
      if (!_isCurrent(generation, device)) return;
      _activeCancellation = null;
      emit(state.copyWith(loading: false, filtering: false));
    } catch (e) {
      trace?.event('query_failed', {'error_type': e.runtimeType.toString()});
      if (!_isCurrent(generation, device)) return;
      _activeCancellation = null;
      emit(state.copyWith(loading: false, filtering: false, error: e));
    }
  }

  void cancelFiltering() {
    if (_closing || isClosed || _bindCurrentDevice()) return;
    if (!state.filtering) return;
    _cancelActiveQuery(invalidateGeneration: true);
    _backgroundRefresh?.cancel();
    _backgroundRefresh = null;
    _reconnectQueued = false;
    final changes = _pendingChanges.toList();
    _pendingChanges.clear();
    if (changes.isNotEmpty) unawaited(_invalidate(changes));
    emit(state.copyWith(loading: false, filtering: false, hasMore: false));
  }

  /// Applies only confirmed batch-operation successes to the visible gallery.
  ///
  /// The following refresh remains authoritative, but retaining this local
  /// view prevents a refresh failure from reverting a successful decision on
  /// screen. Photos that no longer match an active keep-state filter are
  /// removed immediately.
  void applyKeepState(Iterable<String> succeededIds, KeepState keepState) {
    if (isClosed) return;
    final ids = succeededIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    final previousById = {
      for (final photo in state.items)
        if (ids.contains(photo.id)) photo.id: KeepStateWireValue.fromWire(photo.keepState),
    };
    applyReviewTransitions([
      for (final id in ids)
        if (previousById[id] case final before?)
          ReviewStateTransition(
            fileId: id,
            before: before,
            after: keepState,
          ),
    ]);
  }

  /// Applies one confirmed transition set to both photos and header counters.
  void applyReviewTransitions(
    Iterable<ReviewStateTransition> transitions,
  ) {
    if (isClosed) return;
    final byId = <String, ReviewStateTransition>{};
    for (final transition in transitions) {
      final id = transition.fileId.trim();
      if (id.isEmpty) continue;
      byId[id] = ReviewStateTransition(
        fileId: id,
        before: transition.before,
        after: transition.after,
      );
    }
    if (byId.isEmpty) return;

    var changed = false;
    final patched = state.items
        .map((photo) {
          final transition = byId[photo.id];
          if (transition == null) return photo;
          final wireValue = transition.after.wireValue;
          if (photo.keepState == wireValue) return photo;
          changed = true;
          return photo.copyWith(keepState: wireValue);
        })
        .toList(growable: false);

    final activeKeepState = state.query.keepState;
    final visible = activeKeepState == null
        ? patched
        : patched
              .where(
                (photo) => KeepStateWireValue.fromWire(photo.keepState).wireValue == activeKeepState,
              )
              .toList(growable: false);
    final removedCount = patched.length - visible.length;
    final matchedCount = removedCount == 0 ? state.matchedCount : (state.matchedCount - removedCount).clamp(0, state.matchedCount).toInt();
    final currentCounts = state.reviewCounts;
    final updatedCounts = currentCounts == null ? null : applyReviewStateTransitions(currentCounts, byId.values);
    if (!changed && updatedCounts == currentCounts) return;
    emit(
      state.copyWith(
        items: visible,
        matchedCount: matchedCount,
        pendingCount: updatedCounts?.pending,
        keepCount: updatedCounts?.kept,
        discardCount: updatedCounts?.discarded,
      ),
    );
  }

  void _onQueryProgress(int generation, String? device, PhotoQueryProgress progress, GalleryTiming? trace) {
    if (!_isCurrent(generation, device) || progress.complete) return;
    final preview = progress.previewItems;
    if (preview != null) {
      _visibleTiming = trace;
      trace?.event('preview_ready', {'visible': preview.length, 'scanned': progress.scannedCount});
    }
    emit(
      state.copyWith(
        items: preview,
        hasMore: preview == null ? null : false,
        fromCache: preview == null ? null : progress.fromCache,
        scannedCount: progress.scannedCount,
        matchedCount: progress.matchedCount,
      ),
    );
  }

  void _cancelActiveQuery({bool invalidateGeneration = false}) {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    _runningRefresh = null;
    _runningQueryKey = null;
    if (invalidateGeneration) _requestGeneration++;
  }

  bool _isCurrent(int generation, String? device) =>
      !_closing && !isClosed && generation == _requestGeneration && device == _currentDevice;

  bool _bindCurrentDevice() {
    final device = _currentDevice;
    if (device == _boundDevice) return false;
    _boundDevice = device;
    _cancelActiveQuery(invalidateGeneration: true);
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _backgroundRefresh?.cancel();
    _backgroundRefresh = null;
    _pendingChanges.clear();
    _reconnectQueued = false;
    _lastCompleteRefresh = null;
    _visibleTiming = null;
    emit(GalleryState(
      query: state.query.copyWith(clearCursor: true),
      hasMore: false,
      gridColumns: state.gridColumns,
      showRatingOverlay: state.showRatingOverlay,
    ));
    return true;
  }

  void _handleDataChange(AppDataChange change) {
    if (_closing || isClosed) return;
    if (change is RecognitionFactsChanged && (change.projectId != batchId || change.deviceId != _currentDevice)) return;
    if (change is AnalysisCompleted && (change.projectId != batchId || change.deviceId != _currentDevice)) return;
    if (change is ReviewDecisionChanged &&
        ((_currentDevice != null && change.deviceId != _currentDevice) || (change.projectId != null && change.projectId != batchId))) {
      return;
    }
    if (change.affects(AppDataResource.photoPreferences)) {
      _applyPhotoPreferences();
      return;
    }
    if (change is BatchReviewDecisionChanged) {
      // The originating gallery already applied this aggregate atomically.
      // The event exists to update retained batch summaries without causing a
      // second photo reload on every batch action.
      return;
    }
    if (change is ReviewDecisionChanged && change.projectId == batchId) {
      applyReviewTransitions([
        ReviewStateTransition(
          fileId: change.fileId,
          before: change.beforeKeepState,
          after: change.afterKeepState,
        ),
      ]);
      if (change.queued) return;
    }
    _queueBackgroundRefresh(change);
  }

  void _queueBackgroundRefresh([AppDataChange? change]) {
    if (_closing || isClosed) return;
    final switched = _bindCurrentDevice();
    if (change != null) {
      _pendingChanges.add(change);
    } else {
      if (switched) {
        unawaited(refresh());
        return;
      }
      final last = _lastCompleteRefresh;
      if (last != null && DateTime.now().difference(last) < const Duration(milliseconds: 500) && state.resultComplete && state.error == null) {
        return;
      }
      _reconnectQueued = true;
    }
    _scheduleBackgroundRefresh();
  }

  void _scheduleBackgroundRefresh() {
    if (_closing || _drainingChanges || _activeCancellation != null || _runningRefresh != null || _searchDebounce?.isActive == true) return;
    if (!_reconnectQueued && _pendingChanges.isEmpty) return;
    _backgroundRefresh ??= Timer(const Duration(milliseconds: 200), () {
      _backgroundRefresh = null;
      unawaited(_drainBackgroundRefresh());
    });
  }

  Future<bool> _invalidate(List<AppDataChange> changes) async {
    final repository = _repo;
    if (repository is! PhotoQueryExecutionRepository) return true;
    final device = _boundDevice;
    try {
      await (repository as PhotoQueryExecutionRepository).invalidateLocalQueries(batchId, changes: changes);
      return true;
    } catch (error) {
      if (!_closing && !isClosed && device == _currentDevice) {
        emit(state.copyWith(error: error, resultComplete: false));
      }
      return false;
    }
  }

  Future<void> _drainBackgroundRefresh() async {
    if (_closing || _activeCancellation != null || _runningRefresh != null || _searchDebounce?.isActive == true) return;
    if (!_reconnectQueued && _pendingChanges.isEmpty) return;
    final changes = _pendingChanges.toList();
    _pendingChanges.clear();
    _reconnectQueued = false;
    final device = _boundDevice;
    final generation = _requestGeneration;
    _drainingChanges = true;
    try {
      if (!_isCurrent(generation, device)) return;
      if (changes.isNotEmpty && !await _invalidate(changes)) return;
      if (_isCurrent(generation, device)) await refresh();
    } finally {
      _drainingChanges = false;
      _scheduleBackgroundRefresh();
    }
  }

  String _viewCacheKey() {
    return albumViewCacheKey(
      deviceNamespace: _activeDeviceId?.call(),
      projectId: batchId,
    );
  }

  Future<void> loadMore() async {
    if (_closing || isClosed) return;
    if (_bindCurrentDevice()) {
      await refresh();
      return;
    }
    if (state.loading || !state.hasMore) return;
    final generation = ++_requestGeneration;
    final device = _boundDevice;
    final token = PhotoQueryCancellationToken(isCurrent: () => _isCurrent(generation, device));
    _activeCancellation = token;
    final requestedCursor = state.query.cursor;
    emit(state.copyWith(loading: true));
    try {
      final repository = _repo;
      final p = repository is PhotoQueryExecutionRepository
          ? await (repository as PhotoQueryExecutionRepository).pageWithProgress(batchId, state.query, cancellationToken: token)
          : await repository.page(batchId, state.query);
      if (!_isCurrent(generation, device)) return;
      final ids = state.items.map((item) => item.id).toSet();
      final merged = [...state.items, ...p.items.where((item) => ids.add(item.id))];
      final cursorAdvanced = p.nextCursor != null && p.nextCursor != requestedCursor;
      final hasMore = p.hasMore && cursorAdvanced;
      final operationCounts = _operationCounts();
      emit(
        state.copyWith(
          loading: false,
          query: state.query.next(p.nextCursor),
          items: merged,
          hasMore: hasMore,
          fromCache: p.fromCache,
          cachedAt: p.cachedAt,
          scannedCount: p.scannedCount,
          matchedCount: p.matchedCount ?? merged.length,
          resultComplete: p.resultComplete && _pendingChanges.isEmpty,
          cacheScope: p.cacheScope,
          pendingOperationCount: operationCounts.pending,
          conflictOperationCount: operationCounts.conflict,
          conflictFileIds: operationCounts.conflictFileIds,
          clearError: true,
        ),
      );
    } on PhotoQueryCancelled {
      if (_isCurrent(generation, device)) emit(state.copyWith(loading: false));
    } catch (e) {
      if (!_isCurrent(generation, device)) return;
      emit(state.copyWith(loading: false, error: e));
    } finally {
      if (identical(_activeCancellation, token)) {
        _activeCancellation = null;
        _scheduleBackgroundRefresh();
      }
    }
  }

  void _applyPhotoPreferences() {
    final settings = _settingsStore?.read();
    if (settings == null) return;
    final sort = photoQuerySortFromPreference(settings.sortOrder);
    emit(
      state.copyWith(
        gridColumns: settings.gridColumns.clamp(2, 6),
        showRatingOverlay: settings.showRatingOverlay,
      ),
    );
    if (state.query.sort != sort) {
      unawaited(
        refresh(
          query: state.query.copyWith(sort: sort, clearCursor: true),
        ),
      );
    }
  }

  _OperationCounts _operationCounts() {
    final deviceId = _activeDeviceId?.call()?.trim();
    final pendingOperations = _pendingOperations;
    if (deviceId == null || deviceId.isEmpty || pendingOperations == null) return const _OperationCounts();
    final operations = pendingOperations
        .readAll()
        .where((operation) => operation.deviceId == deviceId)
        .where(
          (operation) => operation.projectId == batchId || operation.payload['project_id']?.toString() == batchId || operation.payload['batch_id']?.toString() == batchId,
        )
        .where(
          (operation) => operation.type == PendingOperationType.updateReview || operation.type == PendingOperationType.batchReview,
        )
        .toList(growable: false);
    final conflicts = operations.where((operation) => operation.status == PendingOperationStatus.conflict).toList(growable: false);
    return _OperationCounts(
      pending: operations.where((operation) => operation.status != PendingOperationStatus.conflict).length,
      conflict: conflicts.length,
      conflictFileIds: _conflictFileIds(conflicts),
    );
  }

  List<String> _conflictFileIds(List<PendingOperation> operations) {
    final ids = <String>{};
    for (final operation in operations) {
      final fileId = operation.fileId ?? operation.payload['file_id']?.toString();
      if (fileId != null && fileId.trim().isNotEmpty) ids.add(fileId.trim());
      final rawIds = operation.payload['file_ids'];
      if (rawIds is Iterable) {
        for (final value in rawIds) {
          final id = value.toString().trim();
          if (id.isNotEmpty) ids.add(id);
        }
      }
    }
    return ids.toList(growable: false);
  }

  @override
  Future<void> close() async {
    _closing = true;
    _requestGeneration++;
    _cancelActiveQuery();
    _searchDebounce?.cancel();
    _backgroundRefresh?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}

int _settingsGridColumns(SettingsStore? store) => store?.read().gridColumns.clamp(2, 6) ?? 3;

bool _settingsShowRatingOverlay(SettingsStore? store) => store?.read().showRatingOverlay ?? true;

int _nonNegative(int value) => value < 0 ? 0 : value;

PhotoQuery _applyDefaultFilter(PhotoQuery query, String preference) => switch (preference) {
  'pendingReview' when query.keepState == null => query.copyWith(keepState: 'pending'),
  'recommended' when !query.recommendedOnly => query.copyWith(recommendedOnly: true),
  'highScore' when query.minScore == null => query.copyWith(minScore: 4),
  _ => query,
};

PhotoQuery _applyPhotoDefaults(
  PhotoQuery query,
  BirdSettingsSnapshot settings,
) {
  final filtered = _applyDefaultFilter(
    query,
    settings.defaultPhotoFilter,
  );
  if (!settings.birdPhotosOnly || filtered.recognitionState != null) {
    return filtered;
  }
  return filtered.copyWith(recognitionState: 'recognized');
}

class _OperationCounts {
  const _OperationCounts({
    this.pending = 0,
    this.conflict = 0,
    this.conflictFileIds = const [],
  });

  final int pending;
  final int conflict;
  final List<String> conflictFileIds;
}
