import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_local_query_executor.dart';
import 'package:aves/bird_companion/features/gallery/domain/gallery_timing.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_local_filter_engine.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query_plan.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class PhotoRepositoryImpl implements PhotoRepository, PhotoQueryExecutionRepository {
  PhotoRepositoryImpl(
    this._api,
    this._connectivity,
    this._pending,
    this._cache, [
    String Function()? cacheNamespace,
    String? Function()? deviceId,
  ]) : _cacheNamespace = cacheNamespace ?? (() => 'default'),
       _deviceId = deviceId ?? (() => null);
  final PhotoApi _api;
  final ConnectivityMonitor _connectivity;
  final PendingOperationStore _pending;
  final LocalCache _cache;
  final String Function() _cacheNamespace;
  final String? Function() _deviceId;
  final _reads = <(_PhotoScope, String), _PhotoRead>{};
  final _invalidations = <_PhotoScope, Future<void>>{};
  final _handledChanges = Expando<Set<_PhotoScope>>();
  String? _readingNamespace;
  late final PhotoLocalQueryExecutor _localQueryExecutor = PhotoLocalQueryExecutor(
    _loadAndCacheServerPage,
    searchSpecies,
    const PhotoLocalFilterEngine(),
    _readCandidateSnapshot,
    _writeCandidateSnapshot,
    _loadAndCacheServerPage,
  );

  static const _photoPrefix = 'album:photos:';
  static const _scenePrefix = 'album:scenes:';
  static const _speciesPrefix = 'album:species:';
  static const _candidatePrefix = 'album:query-candidates:';
  static const _candidateTtl = Duration(minutes: 10);

  @override
  Future<PhotoPage> page(String id, PhotoQuery q) => pageWithProgress(id, q);

  @override
  Future<PhotoPage> pageWithProgress(
    String id,
    PhotoQuery q, {
    PhotoQueryProgressCallback? onProgress,
    PhotoQueryCancellationToken? cancellationToken,
  }) async {
    final scope = _captureScope(id);
    bool isCurrent() => scope.$1 == _cacheNamespace();
    var pending = _invalidations[scope];
    while (pending != null) {
      await pending;
      pending = _invalidations[scope];
    }
    cancellationToken?.throwIfCancelled();
    if (!isCurrent()) throw const PhotoQueryCancelled();
    final key = (scope, jsonEncode(q.toJson()));
    final previous = _reads[key];
    if (previous != null && !previous.hasSubscribers) {
      _reads.remove(key);
      previous.cancel();
    }
    final read = _reads[key] ??= _PhotoRead(
      isCurrent: isCurrent,
      load: (report, token) => _readPage(scope, q, report, token),
      onDone: (read) {
        if (identical(_reads[key], read)) _reads.remove(key);
      },
    );
    final subscriber = (progress: onProgress, token: cancellationToken);
    final subscription = read.subscribe(subscriber);
    try {
      final page = await read.resultOrCancellation(cancellationToken);
      cancellationToken?.throwIfCancelled();
      if (!isCurrent()) throw const PhotoQueryCancelled();
      return page;
    } finally {
      read.unsubscribe(subscription);
      if (!read.hasSubscribers && identical(_reads[key], read)) {
        _reads.remove(key);
        read.cancel();
      }
    }
  }

  Future<PhotoPage> _readPage(
    _PhotoScope scope,
    PhotoQuery q,
    PhotoQueryProgressCallback onProgress,
    PhotoQueryCancellationToken cancellationToken,
  ) async {
    final (namespace, id) = scope;
    final key = '$_photoPrefix$namespace:$id:${_queryKey(q)}';
    try {
      final page = await _localQueryExecutor.page(
        id,
        q,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
        cacheNamespace: namespace,
      );
      cancellationToken.throwIfCancelled();
      return page;
    } on ApiException {
      cancellationToken.throwIfCancelled();
      // The exact wire key omits App-local conditions. A raw page cannot
      // stand in for a complete filtered result when the box is unreachable.
      final cached = PhotoQueryPlan(q).requiresLocalScan ? null : _cache.read<Map>(key);
      if (cached != null) return _photoPageFromCache(cached, q);
      final local = _localPageFromSnapshots(scope, q);
      if (local != null) return local;
      rethrow;
    }
  }

  PhotoCandidateSnapshot? _readCandidateSnapshot(
    String batchId,
    PhotoQuery serverQuery,
  ) {
    final raw = _cache.read<Map>(_candidateKey(batchId, serverQuery));
    if (raw == null || raw['complete'] != true) return null;
    final cachedAt = DateTime.tryParse(raw['cached_at']?.toString() ?? '');
    if (cachedAt == null || DateTime.now().difference(cachedAt) > _candidateTtl) {
      unawaited(_cache.remove(_candidateKey(batchId, serverQuery)));
      return null;
    }
    final items = (raw['items'] as List? ?? const []).whereType<Map>().map((item) => PhotoSummary.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
    return PhotoCandidateSnapshot(items: items, cachedAt: cachedAt);
  }

  Future<void> _writeCandidateSnapshot(
    String batchId,
    PhotoQuery serverQuery,
    PhotoCandidateSnapshot snapshot,
    PhotoQueryCancellationToken? cancellationToken,
  ) async {
    cancellationToken?.throwIfCancelled();
    final timing = GalleryTiming.current;
    final started = timing?.elapsedUs ?? 0;
    await _cache.write(_candidateKey(batchId, serverQuery), {
      'complete': true,
      'items': snapshot.items.map((item) => item.toJson()).toList(growable: false),
      'cached_at': snapshot.cachedAt.toIso8601String(),
    });
    if (timing != null) {
      timing.event('candidate_cache_written', {'items': snapshot.items.length, 'duration_us': timing.elapsedUs - started});
    }
  }

  String _candidateKey(String batchId, PhotoQuery serverQuery) => '$_candidatePrefix${_cacheNamespace()}:$batchId:${_queryKey(serverQuery)}';

  @override
  Future<void> invalidateLocalQueries(String batchId, {Iterable<AppDataChange> changes = const []}) async {
    final scope = _captureScope(batchId);
    final unseen = changes.where((change) => !(_handledChanges[change]?.contains(scope) ?? false)).toList();
    if (changes.isNotEmpty && unseen.isEmpty) {
      await _invalidations[scope];
      return;
    }
    for (final change in unseen) {
      (_handledChanges[change] ??= {}).add(scope);
    }
    try {
      await (_invalidations[scope] ??= Future<void>.microtask(() async {
        _localQueryExecutor.invalidateBatch(batchId, cacheNamespace: scope.$1);
        final keys = _reads.keys.where((key) => key.$1 == scope).toList();
        for (final key in keys) {
          _reads.remove(key)?.cancel();
        }
        final prefix = '$_candidatePrefix${scope.$1}:$batchId:';
        for (final key in _cache.keysWithPrefix(prefix)) {
          await _cache.remove(key);
        }
      }).whenComplete(() {
        _invalidations.remove(scope);
      }));
    } catch (_) {
      for (final change in unseen) {
        _handledChanges[change]?.remove(scope);
      }
      rethrow;
    }
  }

  _PhotoScope _captureScope(String batchId) {
    final namespace = _cacheNamespace();
    if (namespace != _readingNamespace) {
      _readingNamespace = namespace;
      for (final read in _reads.values) {
        read.cancel();
      }
      _reads.clear();
    }
    return (namespace, batchId);
  }

  Future<PhotoPage> _loadAndCacheServerPage(
    String batchId,
    PhotoQuery query, [
    void Function(PhotoPage)? onReceived,
    PhotoQueryCancellationToken? cancellationToken,
  ]) async {
    cancellationToken?.throwIfCancelled();
    final key = '$_photoPrefix${_cacheNamespace()}:$batchId:${_queryKey(query)}';
    final page = await _api.page(batchId, query);
    cancellationToken?.throwIfCancelled();
    onReceived?.call(page);
    cancellationToken?.throwIfCancelled();
    final timing = GalleryTiming.current;
    final started = timing?.elapsedUs ?? 0;
    await _cache.write(key, {
      'items': page.items.map((item) => item.toJson()).toList(),
      'has_more': page.hasMore,
      'next_cursor': page.nextCursor,
      'cached_at': DateTime.now().toIso8601String(),
    });
    if (timing != null) {
      timing.event('page_cache_written', {'request': timing.requests, 'duration_us': timing.elapsedUs - started});
    }
    return page;
  }

  @override
  Future<List<SceneSummary>> scenes(String id) async {
    final key = '$_scenePrefix${_cacheNamespace()}:$id';
    try {
      final items = await _api.scenes(id);
      await _cache.write(key, {'items': items.map((item) => item.toJson()).toList(), 'cached_at': DateTime.now().toIso8601String()});
      return items;
    } on ApiException {
      final cached = _cache.read<Map>(key);
      if (cached == null) rethrow;
      return (cached['items'] as List? ?? const []).whereType<Map>().map((item) => SceneSummary.fromJson(Map<String, dynamic>.from(item))).toList();
    }
  }

  @override
  Future<List<SpeciesCandidate>> searchSpecies(String query) async {
    final normalized = query.trim().toLowerCase();
    final key = '$_speciesPrefix${_cacheNamespace()}:$normalized';
    try {
      final items = await _api.searchSpecies(normalized);
      await _cache.write(key, {'items': items.map((item) => item.toJson()).toList(), 'cached_at': DateTime.now().toIso8601String()});
      return items;
    } on ApiException {
      final cached = _cache.read<Map>(key);
      if (cached == null) rethrow;
      return (cached['items'] as List? ?? const []).whereType<Map>().map((item) => SpeciesCandidate.fromJson(Map<String, dynamic>.from(item))).toList();
    }
  }

  @override
  Future<BatchOperationOutcome> batchOperation(
    String id,
    List<String> ids,
    String action, {
    required int version,
    Object? value,
  }) async {
    if (version < 0) {
      throw const ProtocolCompatibilityException('version', '必须是非负整数');
    }
    final targetIds = ids.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet().toList();
    if (targetIds.isEmpty) return const BatchOperationOutcome(succeededIds: []);
    final deviceId = _activeDeviceId;
    if (deviceId == null) {
      throw StateError('没有可用于隔离修改的设备身份');
    }
    final operationId = 'batch-$id-${DateTime.now().microsecondsSinceEpoch}';
    try {
      if (await _connectivity.hasNetwork) {
        final outcome = await _api.batchOperation(
          id,
          targetIds,
          action,
          version: version,
          value: value,
          idempotencyKey: operationId,
        );
        await _updateCachedPhotos(
          id,
          outcome.succeededIds,
          action,
          value,
        );
        await invalidateLocalQueries(id);
        return outcome;
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      if (error.statusCode == 409) {
        return BatchOperationOutcome(
          succeededIds: const [],
          failed: {
            for (final fileId in targetIds) fileId: '照片版本已变化，请刷新后重试',
          },
        );
      }
      if (error.statusCode != null && !error.retryable) rethrow;
      // A failed request is retained below and replayed after a reconnect.
    }
    final queuedIds = <String>[];
    final failed = <String, String>{};
    final alreadyPending = _pending
        .readAll()
        .where(
          (operation) => operation.type == PendingOperationType.batchReview && operation.deviceId == deviceId && operation.projectId == id,
        )
        .expand(
          (operation) => (operation.payload['file_ids'] as List? ?? const <Object>[]).map((fileId) => fileId.toString()),
        )
        .toSet();
    for (final fileId in targetIds) {
      if (alreadyPending.contains(fileId)) {
        failed[fileId] = '该照片已有待同步修改，请先完成同步';
      } else {
        queuedIds.add(fileId);
      }
    }
    if (queuedIds.isEmpty) {
      return BatchOperationOutcome(succeededIds: const [], failed: failed);
    }
    await _pending.save(
      PendingOperation(
        id: operationId,
        type: PendingOperationType.batchReview,
        payload: {
          'file_ids': queuedIds,
          'operation': action,
          'value': value,
          'version': version,
        },
        createdAt: DateTime.now(),
        version: version,
        deviceId: deviceId,
        projectId: id,
      ),
    );
    await _updateCachedPhotos(id, queuedIds, action, value);
    await invalidateLocalQueries(id);
    return BatchOperationOutcome(
      succeededIds: queuedIds,
      failed: failed,
      queued: true,
    );
  }

  Future<void> _updateCachedPhotos(String batchId, List<String> ids, String operation, Object? value) async {
    final selected = ids.toSet();
    final prefix = '$_photoPrefix${_cacheNamespace()}:$batchId:';
    for (final key in _cache.keysWithPrefix(prefix)) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      var changed = false;
      final items = (raw['items'] as List? ?? const []).map((item) {
        if (item is! Map) return item;
        final photo = Map<String, dynamic>.from(item);
        if (!selected.contains(photo['file_id']?.toString())) return photo;
        changed = true;
        if (const {'pending', 'keep', 'discard', 'featured'}.contains(operation)) {
          photo['keep_state'] = operation;
        } else if (operation == 'add_tags' || operation == 'remove_tags') {
          final tags = (photo['user_tags'] as List? ?? const []).map((tag) => tag.toString()).toSet();
          final changedTags = (value as List? ?? const []).map((tag) => tag.toString());
          operation == 'add_tags' ? tags.addAll(changedTags) : tags.removeAll(changedTags);
          photo['user_tags'] = tags.toList();
        }
        return photo;
      }).toList();
      if (changed) await _cache.write(key, {...Map<String, dynamic>.from(raw), 'items': items, 'cached_at': DateTime.now().toIso8601String()});
    }
  }

  String _queryKey(PhotoQuery query) {
    final entries = query.parameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Uri(queryParameters: {for (final entry in entries) entry.key: entry.value.toString()}).query;
  }

  String? get _activeDeviceId {
    final value = _deviceId()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  PhotoPage _photoPageFromCache(Map<dynamic, dynamic> raw, PhotoQuery query) {
    final complete = query.cursor == null && raw['has_more'] != true;
    return PhotoPage(
      items: (raw['items'] as List? ?? const []).whereType<Map>().map((item) => PhotoSummary.fromJson(Map<String, dynamic>.from(item))).toList(),
      hasMore: raw['has_more'] == true,
      nextCursor: raw['next_cursor']?.toString(),
      fromCache: true,
      cachedAt: DateTime.tryParse(raw['cached_at']?.toString() ?? ''),
      resultComplete: complete,
      cacheScope: complete ? PhotoCacheScope.complete : PhotoCacheScope.partial,
    );
  }

  PhotoPage? _localPageFromSnapshots(_PhotoScope scope, PhotoQuery query) {
    final (namespace, batchId) = scope;
    final prefix = '$_photoPrefix$namespace:$batchId:';
    final byId = <String, PhotoSummary>{};
    final savedAtById = <String, DateTime?>{};
    DateTime? cachedAt;
    for (final key in _cache.keysWithPrefix(prefix)) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      final savedAt = DateTime.tryParse(raw['cached_at']?.toString() ?? '');
      if (savedAt != null && (cachedAt == null || savedAt.isAfter(cachedAt))) cachedAt = savedAt;
      for (final item in (raw['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final photo = PhotoSummary.fromJson(Map<String, dynamic>.from(item));
        if (photo.id.isEmpty) continue;
        final previousSavedAt = savedAtById[photo.id];
        if (previousSavedAt != null && (savedAt == null || savedAt.isBefore(previousSavedAt))) continue;
        byId[photo.id] = photo;
        savedAtById[photo.id] = savedAt;
      }
    }
    if (byId.isEmpty) return null;

    final items = const PhotoLocalFilterEngine().filterAndSort(byId.values, query);
    final offset = int.tryParse(query.cursor ?? '') ?? 0;
    final start = offset.clamp(0, items.length);
    final end = (start + query.pageSize).clamp(start, items.length);
    final pageItems = items.sublist(start, end);
    return PhotoPage(
      items: pageItems,
      hasMore: end < items.length,
      nextCursor: end < items.length ? '$end' : null,
      fromCache: true,
      cachedAt: cachedAt,
      resultComplete: false,
      cacheScope: PhotoCacheScope.partial,
      scannedCount: byId.length,
      matchedCount: items.length,
    );
  }
}

typedef _PhotoScope = (String namespace, String batchId);
typedef _PhotoSubscriber = ({PhotoQueryProgressCallback? progress, PhotoQueryCancellationToken? token});

/// A shared request with independently cancellable consumers.
class _PhotoRead {
  _PhotoRead({
    required bool Function() isCurrent,
    required Future<PhotoPage> Function(PhotoQueryProgressCallback, PhotoQueryCancellationToken) load,
    required void Function(_PhotoRead) onDone,
  }) {
    _token = PhotoQueryCancellationToken(isCurrent: () => isCurrent() && hasSubscribers);
    _result = Future.any([
      Future<PhotoPage>.microtask(() => load(_report, _token)),
      _cancelledResult(_token),
    ]).whenComplete(() => onDone(this));
  }

  late final PhotoQueryCancellationToken _token;
  late final Future<PhotoPage> _result;
  final _subscribers = <Object, _PhotoSubscriber>{};
  PhotoQueryProgress? _latest;
  List<PhotoSummary>? _preview;

  bool get hasSubscribers => _subscribers.values.any((subscriber) => subscriber.token?.isCancelled != true);

  Object subscribe(_PhotoSubscriber subscriber) {
    final id = Object();
    _subscribers[id] = subscriber;
    final latest = _latest;
    if (latest != null && !latest.complete) {
      subscriber.progress?.call(
        PhotoQueryProgress(
          scannedCount: latest.scannedCount,
          matchedCount: latest.matchedCount,
          fromCache: latest.fromCache,
          previewItems: _preview,
        ),
      );
    }
    return id;
  }

  void unsubscribe(Object id) => _subscribers.remove(id);
  void cancel() => _token.cancel();

  Future<PhotoPage> resultOrCancellation(PhotoQueryCancellationToken? token) =>
      token == null ? _result : Future.any([_result, _cancelledResult(token)]);

  static Future<PhotoPage> _cancelledResult(PhotoQueryCancellationToken token) =>
      token.whenCancelled.then((_) => throw const PhotoQueryCancelled());

  void _report(PhotoQueryProgress progress) {
    if (_token.isCancelled) return;
    _latest = progress;
    _preview = progress.previewItems ?? _preview;
    for (final subscriber in _subscribers.values.toList()) {
      if (subscriber.token?.isCancelled != true) subscriber.progress?.call(progress);
    }
  }
}
