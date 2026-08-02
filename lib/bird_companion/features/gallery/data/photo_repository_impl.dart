import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_repository.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class PhotoRepositoryImpl implements PhotoRepository {
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

  static const _photoPrefix = 'album:photos:';
  static const _scenePrefix = 'album:scenes:';
  static const _speciesPrefix = 'album:species:';

  @override
  Future<PhotoPage> page(String id, PhotoQuery q) async {
    final key = '$_photoPrefix${_cacheNamespace()}:$id:${_queryKey(q)}';
    try {
      final page = await _api.page(id, q);
      await _cache.write(key, {
        'items': page.items.map((item) => item.toJson()).toList(),
        'has_more': page.hasMore,
        'next_cursor': page.nextCursor,
        'cached_at': DateTime.now().toIso8601String(),
      });
      return page;
    } on ApiException {
      final cached = _cache.read<Map>(key);
      if (cached != null) return _photoPageFromCache(cached);
      final local = _localPageFromSnapshots(id, q);
      if (local != null) return local;
      rethrow;
    }
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
  Future<BatchOperationOutcome> batchOperation(String id, List<String> ids, String action, {Object? value}) async {
    final targetIds = ids.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet().toList();
    if (targetIds.isEmpty) return const BatchOperationOutcome(succeededIds: []);
    try {
      if (await _connectivity.hasNetwork) return await _api.batchOperation(id, targetIds, action, value: value);
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      // A failed request is retained below and replayed after a reconnect.
    }
    await _pending.save(
      PendingOperation(
        id: 'batch-$id-${DateTime.now().microsecondsSinceEpoch}',
        type: PendingOperationType.batchReview,
        payload: {
          'project_id': id,
          'file_ids': targetIds,
          'operation': action,
          'value': value,
        },
        createdAt: DateTime.now(),
        deviceId: _activeDeviceId,
        projectId: id,
      ),
    );
    await _updateCachedPhotos(id, targetIds, action, value);
    return BatchOperationOutcome(succeededIds: targetIds, queued: true);
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

  PhotoPage _photoPageFromCache(Map<dynamic, dynamic> raw) => PhotoPage(
    items: (raw['items'] as List? ?? const []).whereType<Map>().map((item) => PhotoSummary.fromJson(Map<String, dynamic>.from(item))).toList(),
    hasMore: raw['has_more'] == true,
    nextCursor: raw['next_cursor']?.toString(),
    fromCache: true,
    cachedAt: DateTime.tryParse(raw['cached_at']?.toString() ?? ''),
  );

  PhotoPage? _localPageFromSnapshots(String batchId, PhotoQuery query) {
    final prefix = '$_photoPrefix${_cacheNamespace()}:$batchId:';
    final byId = <String, PhotoSummary>{};
    DateTime? cachedAt;
    for (final key in _cache.keysWithPrefix(prefix)) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      final savedAt = DateTime.tryParse(raw['cached_at']?.toString() ?? '');
      if (savedAt != null && (cachedAt == null || savedAt.isAfter(cachedAt))) cachedAt = savedAt;
      for (final item in (raw['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final photo = PhotoSummary.fromJson(Map<String, dynamic>.from(item));
        if (photo.id.isNotEmpty) byId[photo.id] = photo;
      }
    }
    if (byId.isEmpty) return null;

    var items = byId.values.where((photo) => _matches(photo, query)).toList();
    items.sort((left, right) => _compare(left, right, query.sort));
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
    );
  }

  bool _matches(PhotoSummary photo, PhotoQuery query) {
    final search = query.search?.trim().toLowerCase();
    final candidates = photo.recognition?.candidates ?? const [];
    if (search?.isNotEmpty == true) {
      final searchable = [
        photo.filename,
        ...photo.userTags,
        ...candidates.expand((candidate) => [candidate.name, candidate.englishName ?? '', candidate.latinName ?? '']),
      ].join(' ').toLowerCase();
      if (!searchable.contains(search!)) return false;
    }
    final species = query.species?.trim().toLowerCase();
    if (species?.isNotEmpty == true && !candidates.any((candidate) => candidate.speciesId?.toLowerCase() == species || candidate.name.toLowerCase().contains(species!))) {
      return false;
    }
    if (query.minScore != null && (photo.rating?.totalScore ?? -1) < query.minScore!) return false;
    if (query.minConfidence != null && (candidates.isEmpty || candidates.first.confidence < query.minConfidence!)) return false;
    if (query.tags.isNotEmpty && !query.tags.every(photo.userTags.contains)) return false;
    if (query.keepState?.isNotEmpty == true && photo.keepState != query.keepState) return false;
    if (query.analysisState?.isNotEmpty == true && photo.analysisState.wireValue != query.analysisState) return false;
    if (query.clarityState?.isNotEmpty == true && photo.clarityState.wireValue != query.clarityState) return false;
    if (query.recommendedOnly && !photo.isRecommended) return false;
    if (query.groupId?.isNotEmpty == true && photo.groupId != query.groupId) return false;
    if (query.sceneId?.isNotEmpty == true && photo.sceneId != query.sceneId) return false;
    switch (query.recognitionState) {
      case 'recognized':
        if (candidates.isEmpty || photo.recognition?.isLowConfidence == true) return false;
        break;
      case 'needs_review':
        if (photo.recognition?.isLowConfidence != true) return false;
        break;
      case 'unknown':
        if (candidates.isNotEmpty) return false;
        break;
    }
    return true;
  }

  int _compare(PhotoSummary left, PhotoSummary right, String sort) {
    switch (sort) {
      case 'score_desc':
        return (right.rating?.totalScore ?? -1).compareTo(left.rating?.totalScore ?? -1);
      case 'confidence_desc':
        final rightConfidence = right.recognition?.candidates.firstOrNull?.confidence ?? -1;
        final leftConfidence = left.recognition?.candidates.firstOrNull?.confidence ?? -1;
        return rightConfidence.compareTo(leftConfidence);
      case 'recommended_desc':
        final recommendation = (right.isRecommended ? 1 : 0).compareTo(left.isRecommended ? 1 : 0);
        if (recommendation != 0) return recommendation;
        return (right.rating?.totalScore ?? -1).compareTo(left.rating?.totalScore ?? -1);
      default:
        final rightTime = right.capturedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final leftTime = left.capturedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
    }
  }
}
