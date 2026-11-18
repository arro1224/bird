import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';

class BatchRepositoryImpl implements BatchRepository, BatchSummaryReader {
  BatchRepositoryImpl(this._api, [this._cache, String Function()? cacheNamespace]) : _cacheNamespace = cacheNamespace ?? (() => 'default');
  final BatchApi _api;
  final LocalCache? _cache;
  final String Function() _cacheNamespace;

  @override
  Future<BatchSummary> create(ProjectCreateRequest request) => _api.create(request);

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    final namespace = _cacheNamespace();
    final key = 'album:batches:$namespace:${state ?? ''}:${sort ?? ''}:${cursor ?? ''}';
    try {
      final result = await _api.page(state: state, sort: sort, cursor: cursor);
      final page = BatchPage(
        items: result.items.map((item) => item.copyWith(countsUpdatedAt: DateTime.now(), countsFromCache: false, countsDeviceId: namespace)).toList(),
        hasMore: result.hasMore,
        nextCursor: result.nextCursor,
      );
      await _cache?.write(key, {
        'items': page.items.map((item) => item.toJson()).toList(),
        'has_more': page.hasMore,
        'next_cursor': page.nextCursor,
      });
      return page;
    } on ApiException {
      final raw = _cache?.read<Map>(key);
      if (raw == null) rethrow;
      return BatchPage(
        items: (raw['items'] as List? ?? const []).whereType<Map>().map((item) => BatchSummary.fromJson(Map<String, dynamic>.from(item)).copyWith(countsFromCache: true)).toList(),
        hasMore: raw['has_more'] == true,
        nextCursor: raw['next_cursor']?.toString(),
      );
    }
  }

  @override
  Future<BatchSummary?> current() async {
    final namespace = _cacheNamespace();
    final key = 'album:batches:$namespace:current';
    try {
      final item = (await _api.current())?.copyWith(countsUpdatedAt: DateTime.now(), countsFromCache: false, countsDeviceId: namespace);
      if (item != null) {
        await _cache?.write(key, item.toJson());
      } else {
        await _cache?.remove(key);
      }
      return item;
    } on ApiException {
      final raw = _cache?.read<Map>(key);
      return raw == null ? null : BatchSummary.fromJson(Map<String, dynamic>.from(raw)).copyWith(countsFromCache: true);
    }
  }

  @override
  Future<BatchOverview> overview() async {
    BatchSummary? active;
    Object? activeError;
    try {
      active = await _api.current();
    } catch (error) {
      activeError = error;
    }

    try {
      final recent = await _api.page(sort: 'created_at_desc');
      return BatchOverview(active: active, latest: recent.items.isEmpty ? null : recent.items.first);
    } catch (_) {
      if (active != null) return BatchOverview(active: active);
      if (activeError != null) Error.throwWithStackTrace(activeError, StackTrace.current);
      rethrow;
    }
  }

  @override
  Future<void> resume(String batchId) => _api.resume(batchId);

  @override
  Future<BatchSummary?> summary(String projectId) async {
    final namespace = _cacheNamespace();
    final key = 'album:batch-summary:$namespace:$projectId';
    try {
      BatchSummary? found = await _api.current();
      if (_cacheNamespace() != namespace) return null;
      if (found?.id != projectId) {
        found = null;
        String? cursor;
        final visited = <String>{};
        // No new box endpoint: boundedly locate historical projects using the
        // existing paginated list. A miss never manufactures a zero summary.
        for (var pageIndex = 0; pageIndex < 30; pageIndex++) {
          final page = await _api.page(sort: 'created_at_desc', cursor: cursor);
          if (_cacheNamespace() != namespace) return null;
          found = page.items.where((item) => item.id == projectId).firstOrNull;
          if (found != null || !page.hasMore || page.nextCursor == null || !visited.add(page.nextCursor!)) break;
          cursor = page.nextCursor;
        }
      }
      if (_cacheNamespace() != namespace) return null;
      if (found == null) throw StateError('Requested project summary is unavailable');
      final snapshot = found.copyWith(countsUpdatedAt: DateTime.now(), countsFromCache: false, countsDeviceId: namespace);
      await _cache?.write(key, snapshot.toJson());
      return snapshot;
    } catch (_) {
      if (_cacheNamespace() != namespace) return null;
      final raw = _cache?.read<Map>(key);
      if (raw == null) rethrow;
      return BatchSummary.fromJson(Map<String, dynamic>.from(raw)).copyWith(countsFromCache: true);
    }
  }
}
