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
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

PhotoQuery resolveInitialPhotoQuery({
  required PhotoQuery fallback,
  required Map<dynamic, dynamic>? savedView,
  required bool restoreSavedView,
}) {
  if (!restoreSavedView || savedView == null) return fallback;
  return PhotoQuery.fromJson(Map<String, dynamic>.from(savedView));
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
    this.error,
    this.gridColumns = 3,
    this.showRatingOverlay = true,
  });
  final bool loading, hasMore;
  final bool fromCache;
  final List<PhotoSummary> items;
  final PhotoQuery query;
  final DateTime? cachedAt;
  final int pendingOperationCount;
  final int conflictOperationCount;
  final List<String> conflictFileIds;
  final Object? error;
  final int gridColumns;
  final bool showRatingOverlay;
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
    Object? error,
    bool clearError = false,
    int? gridColumns,
    bool? showRatingOverlay,
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
    error: clearError ? null : error ?? this.error,
    gridColumns: gridColumns ?? this.gridColumns,
    showRatingOverlay: showRatingOverlay ?? this.showRatingOverlay,
  );

  String? get firstConflictFileId => conflictFileIds.isEmpty ? null : conflictFileIds.first;
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
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => refresh());
    _dataSubscription = dataChanges?.changes
        .where(
          (change) => change.affects(AppDataResource.photos) || change.affects(AppDataResource.cache) || change.affects(AppDataResource.photoPreferences),
        )
        .listen((change) {
          if (change.affects(AppDataResource.photoPreferences)) {
            _applyPhotoPreferences();
          } else {
            refresh();
          }
        });
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
  int _requestGeneration = 0;

  Future<void> restoreAndRefresh(
    PhotoQuery fallback, {
    bool restoreSavedView = true,
  }) async {
    final raw = restoreSavedView ? _cache?.read<Map>(_viewCacheKey()) : null;
    final preferences = _settingsStore?.read();
    final preferredFallback = preferences == null
        ? fallback
        : _applyPhotoDefaults(
            fallback.copyWith(
              sort: _settingsSort(preferences.sortOrder),
              clearCursor: true,
            ),
            preferences,
          );
    final restored = resolveInitialPhotoQuery(
      fallback: preferredFallback,
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
          conflictFileIds: operationCounts.conflictFileIds,
        ),
      );
      await _cache?.write(_viewCacheKey(), q.toJson());
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

  String _viewCacheKey() {
    return albumViewCacheKey(
      deviceNamespace: _activeDeviceId?.call(),
      projectId: batchId,
    );
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
          conflictFileIds: operationCounts.conflictFileIds,
          clearError: true,
        ),
      );
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(loading: false, error: e));
    }
  }

  void _applyPhotoPreferences() {
    final settings = _settingsStore?.read();
    if (settings == null) return;
    final sort = _settingsSort(settings.sortOrder);
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
    _requestGeneration++;
    _searchDebounce?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}

int _settingsGridColumns(SettingsStore? store) => store?.read().gridColumns.clamp(2, 6) ?? 3;

bool _settingsShowRatingOverlay(SettingsStore? store) => store?.read().showRatingOverlay ?? true;

String _settingsSort(String value) => switch (value) {
  'oldest' => 'captured_at_asc',
  'fileNameAscending' => 'filename_asc',
  'fileNameDescending' => 'filename_desc',
  'sizeDescending' => 'size_desc',
  'sizeAscending' => 'size_asc',
  _ => 'captured_at_desc',
};

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
