import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';

class BatchRepositoryImpl implements BatchRepository {
  BatchRepositoryImpl(this._api, [this._cache, String Function()? cacheNamespace]) : _cacheNamespace = cacheNamespace ?? (() => 'default');
  final BatchApi _api;
  final LocalCache? _cache;
  final String Function() _cacheNamespace;

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    final key = 'album:batches:${_cacheNamespace()}:${state ?? ''}:${sort ?? ''}:${cursor ?? ''}';
    try {
      final page = await _api.page(state: state, sort: sort, cursor: cursor);
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
        items: (raw['items'] as List? ?? const []).whereType<Map>().map((item) => BatchSummary.fromJson(Map<String, dynamic>.from(item))).toList(),
        hasMore: raw['has_more'] == true,
        nextCursor: raw['next_cursor']?.toString(),
      );
    }
  }

  @override
  Future<BatchSummary?> current() async {
    final key = 'album:batches:${_cacheNamespace()}:current';
    try {
      final item = await _api.current();
      if (item != null) {
        await _cache?.write(key, item.toJson());
      } else {
        await _cache?.remove(key);
      }
      return item;
    } on ApiException {
      final raw = _cache?.read<Map>(key);
      return raw == null ? null : BatchSummary.fromJson(Map<String, dynamic>.from(raw));
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
}
