import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GalleryState {
  const GalleryState({this.loading = false, this.items = const [], this.query = const PhotoQuery(), this.hasMore = true, this.fromCache = false, this.cachedAt, this.error});
  final bool loading, hasMore;
  final bool fromCache;
  final List<PhotoSummary> items;
  final PhotoQuery query;
  final DateTime? cachedAt;
  final Object? error;
  GalleryState copyWith({bool? loading, List<PhotoSummary>? items, PhotoQuery? query, bool? hasMore, bool? fromCache, DateTime? cachedAt, Object? error, bool clearError = false}) => GalleryState(
    loading: loading ?? this.loading,
    items: items ?? this.items,
    query: query ?? this.query,
    hasMore: hasMore ?? this.hasMore,
    fromCache: fromCache ?? this.fromCache,
    cachedAt: cachedAt ?? this.cachedAt,
    error: clearError ? null : error ?? this.error,
  );
}

class GalleryCubit extends Cubit<GalleryState> {
  GalleryCubit(this._repo, this.batchId, [SessionRefreshCoordinator? refreshCoordinator, AppDataChangeBus? dataChanges, this._cache]) : super(const GalleryState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => refresh());
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.photos) || change.affects(AppDataResource.cache)).listen((_) => refresh());
  }
  final PhotoRepository _repo;
  final String batchId;
  final LocalCache? _cache;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _searchDebounce;
  int _requestGeneration = 0;

  Future<void> restoreAndRefresh(PhotoQuery fallback) async {
    final raw = _cache?.read<Map>('album:view:$batchId');
    final restored = raw == null ? fallback : PhotoQuery.fromJson(Map<String, dynamic>.from(raw));
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
      emit(state.copyWith(loading: false, items: p.items, query: q.next(p.nextCursor), hasMore: p.hasMore, fromCache: p.fromCache, cachedAt: p.cachedAt));
      await _cache?.write('album:view:$batchId', q.toJson());
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(loading: false, error: e));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final generation = ++_requestGeneration;
    emit(state.copyWith(loading: true));
    try {
      final p = await _repo.page(batchId, state.query);
      if (generation != _requestGeneration) return;
      final ids = state.items.map((item) => item.id).toSet();
      final merged = [...state.items, ...p.items.where((item) => ids.add(item.id))];
      emit(state.copyWith(loading: false, query: state.query.next(p.nextCursor), items: merged, hasMore: p.hasMore, fromCache: p.fromCache, cachedAt: p.cachedAt));
    } catch (e) {
      if (generation != _requestGeneration) return;
      emit(state.copyWith(loading: false, error: e));
    }
  }

  @override
  Future<void> close() async {
    _searchDebounce?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}
