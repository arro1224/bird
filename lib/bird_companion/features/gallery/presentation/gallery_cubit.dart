import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/features/review/data/review_checkpoint_store.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

PhotoQuery resolveInitialPhotoQuery({
  required PhotoQuery fallback,
  required Map<dynamic, dynamic>? savedView,
  required bool restoreSavedView,
}) {
  if (!restoreSavedView || savedView == null) return fallback;
  return PhotoQuery.fromJson(Map<String, dynamic>.from(savedView));
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
    this.error,
  });
  final bool loading, hasMore;
  final bool fromCache;
  final List<PhotoSummary> items;
  final PhotoQuery query;
  final DateTime? cachedAt;
  final int pendingOperationCount;
  final int conflictOperationCount;
  final Object? error;
  GalleryState copyWith({
    bool? loading,
    List<PhotoSummary>? items,
    PhotoQuery? query,
    bool? hasMore,
    bool? fromCache,
    DateTime? cachedAt,
    int? pendingOperationCount,
    int? conflictOperationCount,
    Object? error,
    bool clearError = false,
  }) => GalleryState(
    loading: loading ?? this.loading,
    items: items ?? this.items,
    query: query ?? this.query,
    hasMore: hasMore ?? this.hasMore,
    fromCache: fromCache ?? this.fromCache,
    cachedAt: cachedAt ?? this.cachedAt,
    pendingOperationCount: pendingOperationCount ?? this.pendingOperationCount,
    conflictOperationCount: conflictOperationCount ?? this.conflictOperationCount,
    error: clearError ? null : error ?? this.error,
  );
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
  ]) : super(const GalleryState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => refresh());
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.photos) || change.affects(AppDataResource.cache)).listen((_) => refresh());
  }
  final PhotoRepository _repo;
  final String batchId;
  final LocalCache? _cache;
  final PendingOperationStore? _pendingOperations;
  final String? Function()? _activeDeviceId;
  final ReviewCheckpointStore? _checkpointStore;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _searchDebounce;
  int _requestGeneration = 0;

  Future<void> restoreAndRefresh(
    PhotoQuery fallback, {
    bool restoreSavedView = true,
  }) async {
    final raw = restoreSavedView ? _cache?.read<Map>('album:view:$batchId') : null;
    final restored = resolveInitialPhotoQuery(
      fallback: fallback,
      savedView: raw,
      restoreSavedView: restoreSavedView,
    );
    await refresh(query: restored);
  }

  void search(String value) {
    _searchDebounce?.cancel();
    final query = state.query.copyWith(search: value.trim(), clearCursor: true);
    emit(state.copyWith(query: query));
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      refresh(query: query);
    });
  }

  Future<void> refresh({PhotoQuery? query}) async {
    final generation = ++_requestGeneration;
    final q = (query ?? state.query).copyWith(clearCursor: true);
    emit(state.copyWith(loading: true, query: q, clearError: true));
    try {
      final p = await _repo.page(batchId, q);
      if (generation != _requestGeneration) return;
      final operationCounts = _operationCounts();
      emit(
        state.copyWith(
          loading: false,
          items: p.items,
          query: q.next(p.nextCursor),
          hasMore: p.hasMore && p.nextCursor != null,
          fromCache: p.fromCache,
          cachedAt: p.cachedAt,
          pendingOperationCount: operationCounts.pending,
          conflictOperationCount: operationCounts.conflict,
        ),
      );
      await _cache?.write('album:view:$batchId', q.toJson());
      final deviceId = _activeDeviceId?.call()?.trim();
      if (deviceId != null && deviceId.isNotEmpty) {
        try {
          await _checkpointStore?.updateQuery(
            deviceId: deviceId,
            batchId: batchId,
            query: q,
          );
        } catch (_) {
          // Query persistence is a resume aid and must not turn a successful
          // gallery request into a visible load failure.
        }
      }
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(loading: false, error: e));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final generation = ++_requestGeneration;
    final requestedCursor = state.query.cursor;
    emit(state.copyWith(loading: true));
    try {
      final p = await _repo.page(batchId, state.query);
      if (generation != _requestGeneration) return;
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
          pendingOperationCount: operationCounts.pending,
          conflictOperationCount: operationCounts.conflict,
          clearError: true,
        ),
      );
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(loading: false, error: e));
    }
  }

  _OperationCounts _operationCounts() {
    final deviceId = _activeDeviceId?.call()?.trim();
    final pendingOperations = _pendingOperations;
    if (deviceId == null || deviceId.isEmpty || pendingOperations == null) return const _OperationCounts();
    final operations = pendingOperations.readAll().where((operation) => operation.deviceId == deviceId).where((operation) => operation.type == PendingOperationType.updateReview || operation.type == PendingOperationType.batchReview);
    return _OperationCounts(
      pending: operations.where((operation) => operation.status != PendingOperationStatus.conflict).length,
      conflict: operations.where((operation) => operation.status == PendingOperationStatus.conflict).length,
    );
  }

  @override
  Future<void> close() async {
    _searchDebounce?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}

class _OperationCounts {
  const _OperationCounts({this.pending = 0, this.conflict = 0});

  final int pending;
  final int conflict;
}
