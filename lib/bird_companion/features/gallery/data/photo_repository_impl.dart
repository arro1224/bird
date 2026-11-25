import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_tag_action.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
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
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

class PhotoRepositoryImpl implements PhotoRepository, PhotoQueryExecutionRepository, ProjectBatchReviewRepository {
  PhotoRepositoryImpl(
    this._api,
    this._connectivity,
    this._pending,
    this._cache, [
    String Function()? cacheNamespace,
    String? Function()? deviceId,
    this._invalidateReviewVersions,
  ]) : _cacheNamespace = cacheNamespace ?? (() => 'default'),
       _deviceId = deviceId ?? (() => null);
  final PhotoApi _api;
  final ConnectivityMonitor _connectivity;
  final PendingOperationStore _pending;
  final LocalCache _cache;
  final String Function() _cacheNamespace;
  final String? Function() _deviceId;
  final void Function(Iterable<String>)? _invalidateReviewVersions;
  final _batchWrites = <_PhotoScope, Future<void>>{};
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
      await (_invalidations[scope] ??=
          Future<void>.microtask(() async {
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
    final result = await _api.page(batchId, query);
    cancellationToken?.throwIfCancelled();
    final page = PhotoPage(
      items: result.items.map(_withCachedManualSpecies).toList(),
      hasMore: result.hasMore,
      nextCursor: result.nextCursor,
      fromCache: result.fromCache,
      cachedAt: result.cachedAt,
      resultComplete: result.resultComplete,
      cacheScope: result.cacheScope,
      scannedCount: result.scannedCount,
      matchedCount: result.matchedCount,
    );
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

  PhotoSummary _withCachedManualSpecies(PhotoSummary photo) {
    final raw = _cache.read<Map>('album:detail:${_cacheNamespace()}:${photo.id}');
    final decisionJson = raw?['decision'];
    if (decisionJson is! Map) return photo;
    final decision = UserDecision.fromJson(Map<String, dynamic>.from(decisionJson));
    if (photo.version != null && decision.version != null && photo.version! > decision.version!) {
      final pending = _pending.readAll().any((operation) => operation.type == PendingOperationType.updateReview && operation.deviceId == _deviceId() && (operation.fileId ?? operation.payload['file_id']) == photo.id);
      if (!pending) return photo;
    }
    return PhotoSummary.fromJson({...photo.toJson(), 'user_species_id': decision.userSpeciesId, 'user_species': decision.userSpecies});
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

  void _ensureBatchScope(_PhotoScope scope, String deviceId) {
    if (_cacheNamespace() != scope.$1 || _activeDeviceId != deviceId) throw StateError('批量修改所属盒子已切换');
  }

  Future<T> _serializeBatch<T>(_PhotoScope scope, Future<T> Function() action) async {
    final previous = _batchWrites[scope] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    unawaited(_batchWrites[scope] = tail);
    try {
      return await result;
    } finally {
      if (identical(_batchWrites[scope], tail)) unawaited(_batchWrites.remove(scope));
    }
  }

  String _projectVersionKey(_PhotoScope scope) => 'album:project-version:${scope.$1}:${scope.$2}';

  int? _cachedProjectVersion(_PhotoScope scope) {
    final versions = <int>[];
    void collect(Map? raw) {
      if (raw == null || raw['project_id'] != scope.$2) return;
      final version = raw['version'];
      if (version is int && version >= 0) versions.add(version);
    }

    collect(_cache.read<Map>(_projectVersionKey(scope)));
    collect(_cache.read<Map>('album:batch-summary:${scope.$1}:${scope.$2}'));
    for (final key in _cache.keysWithPrefix('album:batches:${scope.$1}:')) {
      final raw = _cache.read<Map>(key);
      collect(raw);
      for (final item in (raw?['items'] as List? ?? const []).whereType<Map>()) {
        collect(item);
      }
    }
    return versions.isEmpty ? null : versions.reduce((a, b) => a > b ? a : b);
  }

  Future<void> _rememberProjectVersion(_PhotoScope scope, int version) async {
    final previous = _cachedProjectVersion(scope);
    if (previous != null && previous > version) return;
    await _cache.write(_projectVersionKey(scope), {'project_id': scope.$2, 'version': version});
  }

  @override
  Future<int> readProjectVersion(String projectId) async {
    final scope = _captureScope(projectId), deviceId = _activeDeviceId;
    if (deviceId == null) throw StateError('没有可用于隔离修改的设备身份');
    return _readProjectVersion(scope, deviceId);
  }

  Future<int> _readProjectVersion(_PhotoScope scope, String deviceId) async {
    try {
      if (await _connectivity.hasNetwork) {
        _ensureBatchScope(scope, deviceId);
        final version = await _api.projectVersion(scope.$2);
        _ensureBatchScope(scope, deviceId);
        await _rememberProjectVersion(scope, version);
        return version;
      }
    } on ApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
    }
    _ensureBatchScope(scope, deviceId);
    final cached = _cachedProjectVersion(scope);
    if (cached == null) throw const ProtocolCompatibilityException('project.version', '尚无可核实的批次版本，请连接盒子刷新后再修改');
    return cached;
  }

  @override
  Future<BatchOperationOutcome> reviewBatch(String projectId, List<String> ids, String operation, {Object? value}) {
    final scope = _captureScope(projectId), deviceId = _activeDeviceId;
    if (deviceId == null) throw StateError('没有可用于隔离修改的设备身份');
    return _serializeBatch(scope, () async {
      final version = await _readProjectVersion(scope, deviceId);
      return _newBatchOperation(scope, deviceId, ids, operation, version, value);
    });
  }

  @override
  Future<BatchOperationOutcome> batchOperation(String id, List<String> ids, String action, {required int version, Object? value}) {
    final scope = _captureScope(id), deviceId = _activeDeviceId;
    if (deviceId == null) throw StateError('没有可用于隔离修改的设备身份');
    return _serializeBatch(scope, () => _newBatchOperation(scope, deviceId, ids, action, version, value));
  }

  Future<BatchOperationOutcome> _newBatchOperation(_PhotoScope scope, String deviceId, List<String> ids, String action, int projectVersion, Object? value) async {
    _ensureBatchScope(scope, deviceId);
    if (projectVersion < 0) throw const ProtocolCompatibilityException('project.version', '必须是非负整数');
    if (!const {'pending', 'keep', 'discard', 'featured', 'add_tags', 'remove_tags'}.contains(action)) throw const ProtocolCompatibilityException('operation', '不支持的批量操作');
    final targetIds = ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
    final existing = _pending.readAll().where((op) => op.deviceId == deviceId && op.projectId == scope.$2).expand((op) => op.remainingFileIds).toSet();
    final failed = {for (final id in targetIds.where(existing.contains)) id: '该照片已有待同步修改或冲突，请先处理'};
    final selected = targetIds.where((id) => !existing.contains(id)).toList();
    if (selected.isEmpty) return BatchOperationOutcome(succeededIds: const [], failed: failed);
    final operation = PendingOperation(
      id: 'batch-${SecureRequestIdFactory().create()}',
      type: PendingOperationType.batchReview,
      payload: Map<String, dynamic>.from(jsonDecode(jsonEncode({'file_ids': selected, 'operation': action, 'value': value, 'version': projectVersion})) as Map),
      createdAt: DateTime.now(),
      version: projectVersion,
      deviceId: deviceId,
      projectId: scope.$2,
      schemaVersion: 2,
      versionScope: 'project',
    );
    // Persist the exact parameters before any POST, including an online write.
    await _pending.save(operation);
    _ensureBatchScope(scope, deviceId);
    try {
      if (await _connectivity.hasNetwork) {
        final result = await _submitBatch(operation, scope, deviceId);
        return BatchOperationOutcome(succeededIds: result.succeededIds, failed: {...failed, ...result.failed}, projectVersion: result.projectVersion);
      }
    } on ApiException catch (error) {
      final acknowledged = _pending.read(operation.id)?.batchReceipt;
      if (acknowledged != null) {
        final result = BatchOperationOutcome.fromResponse(selected, acknowledged);
        return BatchOperationOutcome(succeededIds: result.succeededIds, failed: {...failed, ...result.failed}, projectVersion: result.projectVersion);
      }
      if (error.statusCode == 409) {
        final retained = _pending.read(operation.id) ?? operation;
        const message = '批次已有其他修改，请刷新并重新确认；本次未覆盖盒子内容';
        await _pending.save(retained.copyWith(status: PendingOperationStatus.conflict, failureReason: message));
        return BatchOperationOutcome(
          succeededIds: const [],
          failed: {...failed, for (final id in selected) id: message},
          conflict: true,
          errorCode: error.code,
          currentProjectVersion: ProtocolValidation.optionalNonNegativeInt(error.details, 'current_version'),
        );
      }
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      if (error.statusCode != null && !error.retryable) {
        await _pending.save((_pending.read(operation.id) ?? operation).copyWith(status: PendingOperationStatus.conflict, failureReason: '盒子拒绝了这次批量修改，请核对后重新确认'));
        rethrow;
      }
    } catch (_) {
      _ensureBatchScope(scope, deviceId);
      final retained = _pending.read(operation.id);
      if (retained?.batchReceipt != null) {
        final result = BatchOperationOutcome.fromResponse(selected, retained!.batchReceipt!);
        return BatchOperationOutcome(succeededIds: result.succeededIds, failed: {...failed, ...result.failed}, projectVersion: result.projectVersion);
      }
      // A malformed or lost response can follow a successful mutation. Keep
      // its sent body and key; replay must not create another user action.
    }
    _ensureBatchScope(scope, deviceId);
    if (!isBatchTagAction(action)) await _updateCachedPhotos(scope.$2, selected, action, value, scope.$1);
    await invalidateLocalQueries(scope.$2);
    return BatchOperationOutcome(succeededIds: selected, failed: failed, queued: true);
  }

  Future<void> replayBatchReview(PendingOperation operation) async {
    if (!operation.isProjectVersionBatch) throw const PendingOperationConflict('旧版批量记录未注明项目版本作用域，已保留修改，请核对盒子状态后重新确认');
    final projectId = operation.projectId;
    final deviceId = operation.deviceId;
    if (projectId == null || deviceId == null) throw const PendingOperationConflict('批量记录缺少盒子或批次身份，未重放');
    final scope = _captureScope(projectId);
    await _serializeBatch(scope, () async {
      _ensureBatchScope(scope, deviceId);
      final retained = _pending.read(operation.id);
      if (retained == null) return; // An in-flight online submission finished.
      if (retained.status == PendingOperationStatus.conflict) throw PendingOperationConflict(retained.failureReason ?? '请重新确认批量修改');
      final outcome = await _submitBatch(retained, scope, deviceId);
      if (outcome.failed.isNotEmpty) throw const PendingOperationConflict('部分照片未修改，已保留失败项，请核对后重新确认');
    });
  }

  Future<BatchOperationOutcome> _submitBatch(PendingOperation operation, _PhotoScope scope, String deviceId) async {
    _ensureBatchScope(scope, deviceId);
    final payload = operation.payload;
    final version = ProtocolValidation.optionalNonNegativeInt(payload, 'version');
    if (!operation.isProjectVersionBatch || version == null || operation.version != version) throw const PendingOperationConflict('批量记录的版本作用域或参数不完整，未重放');
    final ids = (payload['file_ids'] as List? ?? const []).map((id) => id.toString()).toList();
    final repairingReceipt = operation.batchReceipt != null;
    late BatchOperationOutcome outcome;
    if (operation.batchReceipt != null) {
      outcome = BatchOperationOutcome.fromResponse(ids, operation.batchReceipt!);
    } else {
      operation = operation.copyWith(requestSent: true);
      await _pending.save(operation);
      _ensureBatchScope(scope, deviceId);
      outcome = await _api.batchOperation(scope.$2, ids, payload['operation'] as String, version: version, value: payload['value'], idempotencyKey: operation.id);
      if (outcome.projectVersion! < version) throw const ProtocolCompatibilityException('project.version', '批量回包版本早于请求版本');
      operation = operation.copyWith(
        batchReceipt: outcome.toReceipt(),
        status: outcome.failed.isEmpty ? PendingOperationStatus.pending : PendingOperationStatus.conflict,
        failureReason: outcome.failed.isEmpty ? null : '部分照片未修改，已保留失败项，请核对后重新确认',
      );
      await _pending.save(operation);
      await _advanceUnsentBatchVersions(operation, outcome.projectVersion!);
    }
    await _rememberProjectVersion(scope, outcome.projectVersion!);
    _ensureBatchScope(scope, deviceId);
    // A saved receipt may predate another confirmed user action. Cache repair
    // reads current box state; it must not reapply the old action locally.
    await _refreshBatchPhotos(scope, deviceId, outcome.succeededIds, action: repairingReceipt ? null : payload['operation'] as String, value: repairingReceipt ? null : payload['value']);
    if (outcome.failed.isEmpty) await _pending.remove(operation.id);
    return outcome;
  }

  Future<void> _advanceUnsentBatchVersions(PendingOperation confirmed, int nextVersion) async {
    if (nextVersion == confirmed.version) return;
    for (final pending in _pending.readAll()) {
      if (pending.id == confirmed.id ||
          !pending.isProjectVersionBatch ||
          pending.requestSent ||
          pending.batchReceipt != null ||
          pending.status == PendingOperationStatus.conflict ||
          pending.deviceId != confirmed.deviceId ||
          pending.projectId != confirmed.projectId ||
          pending.version != confirmed.version ||
          pending.createdAt.isBefore(confirmed.createdAt)) {
        continue;
      }
      // Only our acknowledged CAS advances an unsent draft. Sent requests,
      // external conflicts and ambiguous legacy versions are never rebased.
      await _pending.save(pending.copyWith(version: nextVersion, payload: {...pending.payload, 'version': nextVersion}));
    }
  }

  Future<void> acceptRemoteBatch(PendingOperation operation) async {
    final projectId = operation.projectId, deviceId = operation.deviceId;
    if (projectId == null || deviceId == null) throw StateError('批量记录缺少设备身份');
    final scope = _captureScope(projectId);
    await _serializeBatch(scope, () async {
      for (final id in operation.remainingFileIds) {
        try {
          await _refreshBatchPhotos(scope, deviceId, [id]);
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
          _ensureBatchScope(scope, deviceId);
          // Explicitly adopting box state also accepts a deleted photo. Only
          // its local cached row is removed; no box file is touched.
          for (final key in _cache.keysWithPrefix('$_photoPrefix${scope.$1}:${scope.$2}:')) {
            final raw = _cache.read<Map>(key);
            if (raw == null) continue;
            final items = (raw['items'] as List? ?? const []).where((item) => item is! Map || item['file_id'] != id).toList();
            await _cache.write(key, {...Map<String, dynamic>.from(raw), 'items': items});
          }
        }
      }
    });
  }

  Future<void> _refreshBatchPhotos(_PhotoScope scope, String deviceId, List<String> ids, {String? action, Object? value}) async {
    _ensureBatchScope(scope, deviceId);
    await invalidateLocalQueries(scope.$2);
    _invalidateReviewVersions?.call(ids);
    for (final id in ids) {
      await _cache.remove('album:detail:${scope.$1}:$id');
    }
    for (final key in _cache.keysWithPrefix('album:groups:${scope.$1}:${scope.$2}:')) {
      await _cache.remove(key);
    }
    await _updateCachedPhotos(scope.$2, ids, action, value, scope.$1, clearVersions: true);
    for (var start = 0; start < ids.length; start += 4) {
      final end = start + 4 < ids.length ? start + 4 : ids.length;
      final snapshots = await Future.wait(
        ids.sublist(start, end).map((id) async {
          _ensureBatchScope(scope, deviceId);
          final snapshot = await _api.photoSnapshot(id);
          _ensureBatchScope(scope, deviceId);
          return snapshot;
        }),
      );
      // Serialize page merges; concurrent GETs must not overwrite one another's
      // authoritative photo versions in a shared cached page.
      for (final snapshot in snapshots) {
        final id = snapshot.photo.id;
        final detailKey = 'album:detail:${scope.$1}:$id';
        final current = _cache.read<Map>(detailKey);
        final currentFile = current?['file'];
        final currentVersion = currentFile is Map ? currentFile['version'] : null;
        if (currentVersion is! int || currentVersion <= snapshot.photo.version!) await _cache.write(detailKey, snapshot.detail);
        for (final key in _cache.keysWithPrefix('$_photoPrefix${scope.$1}:${scope.$2}:')) {
          final raw = _cache.read<Map>(key);
          if (raw == null) continue;
          final items = (raw['items'] as List? ?? const []).map((item) {
            if (item is! Map || item['file_id'] != id) return item;
            final old = item['version'];
            return old is int && old > snapshot.photo.version! ? item : snapshot.photo.toJson();
          }).toList();
          await _cache.write(key, {...Map<String, dynamic>.from(raw), 'items': items});
        }
      }
    }
  }

  Future<void> _updateCachedPhotos(String batchId, List<String> ids, String? action, Object? value, String namespace, {bool clearVersions = false}) async {
    final selected = ids.toSet();
    for (final key in _cache.keysWithPrefix('$_photoPrefix$namespace:$batchId:')) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      final items = (raw['items'] as List? ?? const []).map((item) {
        if (item is! Map || !selected.contains(item['file_id'])) return item;
        final photo = Map<String, dynamic>.from(item);
        if (const {'pending', 'keep', 'discard', 'featured'}.contains(action)) photo['keep_state'] = action;
        if (action != null && isBatchTagAction(action)) {
          final tags = (photo['user_tags'] as List? ?? const []).map((tag) => tag.toString()).toSet();
          final changed = (value as List? ?? const []).map((tag) => tag.toString());
          action == 'add_tags' ? tags.addAll(changed) : tags.removeAll(changed);
          photo['user_tags'] = tags.toList();
        }
        if (clearVersions) photo['version'] = null;
        return photo;
      }).toList();
      await _cache.write(key, {...Map<String, dynamic>.from(raw), 'items': items});
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

  Future<PhotoPage> resultOrCancellation(PhotoQueryCancellationToken? token) => token == null ? _result : Future.any([_result, _cancelledResult(token)]);

  static Future<PhotoPage> _cancelledResult(PhotoQueryCancellationToken token) => token.whenCancelled.then((_) => throw const PhotoQueryCancelled());

  void _report(PhotoQueryProgress progress) {
    if (_token.isCancelled) return;
    _latest = progress;
    _preview = progress.previewItems ?? _preview;
    for (final subscriber in _subscribers.values.toList()) {
      if (subscriber.token?.isCancelled != true) subscriber.progress?.call(progress);
    }
  }
}
