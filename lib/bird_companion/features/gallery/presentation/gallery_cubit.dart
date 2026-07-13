import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GalleryState {
  const GalleryState({this.loading = false, this.items = const [], this.query = const PhotoQuery(), this.hasMore = true, this.error});
  final bool loading, hasMore;
  final List<PhotoSummary> items;
  final PhotoQuery query;
  final Object? error;
  GalleryState copyWith({bool? loading, List<PhotoSummary>? items, PhotoQuery? query, bool? hasMore, Object? error, bool clearError = false}) =>
      GalleryState(loading: loading ?? this.loading, items: items ?? this.items, query: query ?? this.query, hasMore: hasMore ?? this.hasMore, error: clearError ? null : error ?? this.error);
}

class GalleryCubit extends Cubit<GalleryState> {
  GalleryCubit(this._repo, this.batchId, [SessionRefreshCoordinator? refreshCoordinator, AppDataChangeBus? dataChanges]) : super(const GalleryState()) {
    _refreshSubscription = refreshCoordinator?.changes.listen((_) => refresh());
    _dataSubscription = dataChanges?.changes.where((change) => change.affects(AppDataResource.photos) || change.affects(AppDataResource.cache)).listen((_) => refresh());
  }
  final PhotoRepository _repo;
  final String batchId;
  StreamSubscription<int>? _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _searchDebounce;

  void search(String value) {
    _searchDebounce?.cancel();
    final query = state.query.copyWith(search: value.trim(), clearCursor: true);
    emit(state.copyWith(query: query));
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      refresh(query: query);
    });
  }

  Future<void> refresh({PhotoQuery? query}) async {
    final q = (query ?? state.query).copyWith(clearCursor: true);
    emit(state.copyWith(loading: true, query: q, clearError: true));
    try {
      final p = await _repo.page(batchId, q);
      emit(state.copyWith(loading: false, items: p.items, query: q.next(p.nextCursor), hasMore: p.hasMore));
    } catch (e) {
      emit(state.copyWith(loading: false, error: e));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    emit(state.copyWith(loading: true));
    try {
      final p = await _repo.page(batchId, state.query);
      final ids = state.items.map((item) => item.id).toSet();
      final merged = [...state.items, ...p.items.where((item) => ids.add(item.id))];
      emit(state.copyWith(loading: false, query: state.query.next(p.nextCursor), items: merged, hasMore: p.hasMore));
    } catch (e) {
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
