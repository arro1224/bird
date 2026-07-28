import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  ReviewRepositoryImpl(
    this._api,
    this._connectivity,
    this._pending,
    this._cache, [
    String Function()? cacheNamespace,
    String? Function()? deviceId,
  ]) : _cacheNamespace = cacheNamespace ?? (() => 'default'),
       _deviceId = deviceId ?? (() => null);
  final ReviewApi _api;
  final ConnectivityMonitor _connectivity;
  final PendingOperationStore _pending;
  final LocalCache _cache;
  final String Function() _cacheNamespace;
  final String? Function() _deviceId;
  final Map<String, UserDecision> _optimisticDecisions = {};

  @override
  Future<List<BirdGroup>> groups(String id, {String? sceneId}) async {
    final key = 'album:groups:${_cacheNamespace()}:$id:${sceneId ?? ''}';
    try {
      final items = (await _api.groups(
        id,
        sceneId: sceneId,
      )).map(_withOptimisticGroup).toList(growable: false);
      await _cache.write(key, items.map((item) => item.toJson()).toList());
      return items;
    } on ApiException {
      final raw = _cache.read<List<dynamic>>(key);
      if (raw == null) rethrow;
      return raw.whereType<Map>().map((item) => BirdGroup.fromJson(Map<String, dynamic>.from(item))).map(_withOptimisticGroup).toList();
    }
  }

  @override
  Future<ReviewDetail> detail(String id) async {
    final key = 'album:detail:${_cacheNamespace()}:$id';
    try {
      final detail = _withOptimisticDetail(await _api.detail(id));
      await _cache.write(key, _detailToJson(detail));
      return detail;
    } on ApiException {
      final raw = _cache.read<Map>(key);
      if (raw != null) {
        return _withOptimisticDetail(
          _detailFromJson(Map<String, dynamic>.from(raw)),
        );
      }
      final summary = _photoSummaryFromSnapshots(id);
      if (summary == null) rethrow;
      return _withOptimisticDetail(
        ReviewDetail(
          photo: PhotoDetail(summary: _withDetailPreview(summary)),
        ),
      );
    }
  }

  @override
  Future<ReviewSaveResult> save(UserDecision v) async {
    try {
      if (!await _connectivity.hasNetwork) return _queue(v, '设备离线，修改将在重新连接后同步');
      await _api.save(v);
      await _removeQueuedReviewOperationsSafely(v.fileId);
      _optimisticDecisions[_optimisticKey(v.fileId)] = v;
      await _updateCachedDecisionSafely(v);
      return const ReviewSaveResult();
    } on ApiException catch (error) {
      if (error.statusCode == 409) return ReviewSaveResult(conflict: true, message: error.message);
      return _queue(v, '暂时无法连接盒子，修改已保存在本机');
    }
  }

  Future<ReviewSaveResult> _queue(UserDecision value, String message) async {
    final operation = PendingOperation(
      id: 'review-${value.fileId}-${DateTime.now().microsecondsSinceEpoch}',
      type: PendingOperationType.updateReview,
      payload: value.toJson(),
      createdAt: DateTime.now(),
      version: value.version,
      deviceId: _activeDeviceId,
    );
    await _pending.save(
      operation,
      supersedes: (existing) => existing.type == PendingOperationType.updateReview && existing.deviceId == operation.deviceId && existing.payload['file_id']?.toString() == value.fileId,
    );
    _optimisticDecisions[_optimisticKey(value.fileId)] = value;
    await _updateCachedDecisionSafely(value);
    return ReviewSaveResult(queued: true, message: message);
  }

  Future<void> _updateCachedDecisionSafely(UserDecision value) async {
    try {
      await _updateCachedDecision(value);
    } catch (_) {
      // The save/queue has already succeeded. Cache repair is best-effort and
      // must not turn a valid review action into a visible failure.
    }
  }

  Future<void> _updateCachedDecision(UserDecision value) async {
    final namespace = _cacheNamespace();
    final detailKey = 'album:detail:$namespace:${value.fileId}';
    final cachedDetail = _cache.read<Map>(detailKey);
    if (cachedDetail != null) {
      final detail = Map<String, dynamic>.from(cachedDetail);
      final rawFile = detail['file'];
      if (rawFile is Map) {
        detail['file'] = mergeReviewDecisionIntoPhotoJson(
          rawFile,
          value,
        );
      }
      detail['decision'] = value.toJson();
      await _cache.write(detailKey, detail);
    }

    final photoPrefix = 'album:photos:$namespace:';
    for (final key in _cache.keysWithPrefix(photoPrefix)) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      var changed = false;
      final items = (raw['items'] as List? ?? const [])
          .map((item) {
            if (item is! Map || item['file_id']?.toString() != value.fileId) {
              return item;
            }
            changed = true;
            return mergeReviewDecisionIntoPhotoJson(item, value);
          })
          .toList(growable: false);
      if (changed) {
        await _cache.write(key, {
          ...Map<String, dynamic>.from(raw),
          'items': items,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }

    final groupPrefix = 'album:groups:$namespace:';
    for (final key in _cache.keysWithPrefix(groupPrefix)) {
      final raw = _cache.read<Object?>(key);
      if (raw is! List) continue;
      var changed = false;
      final groups = raw
          .map((groupValue) {
            if (groupValue is! Map) return groupValue;
            final group = Map<String, dynamic>.from(groupValue);
            final members = (group['members'] as List? ?? const [])
                .map((item) {
                  if (item is! Map || item['file_id']?.toString() != value.fileId) {
                    return item;
                  }
                  changed = true;
                  return mergeReviewDecisionIntoPhotoJson(item, value);
                })
                .toList(growable: false);
            return {...group, 'members': members};
          })
          .toList(growable: false);
      if (changed) await _cache.write(key, groups);
    }
  }

  Future<void> acceptRemoteDecision(String fileId) async {
    final remote = await _api.detail(fileId);
    _optimisticDecisions.remove(_optimisticKey(fileId));
    await _cache.write(
      'album:detail:${_cacheNamespace()}:$fileId',
      _detailToJson(remote),
    );
    await _replaceCachedPhotoWithRemote(remote);
  }

  Future<void> _replaceCachedPhotoWithRemote(ReviewDetail detail) async {
    final namespace = _cacheNamespace();
    final summary = detail.decision == null
        ? detail.photo.summary.toJson()
        : mergeReviewDecisionIntoPhotoJson(
            detail.photo.summary.toJson(),
            detail.decision!,
          );
    final fileId = detail.photo.summary.id;

    for (final key in _cache.keysWithPrefix('album:photos:$namespace:')) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      var changed = false;
      final items = (raw['items'] as List? ?? const [])
          .map((item) {
            if (item is! Map || item['file_id']?.toString() != fileId) {
              return item;
            }
            changed = true;
            return summary;
          })
          .toList(growable: false);
      if (changed) {
        await _cache.write(key, {
          ...Map<String, dynamic>.from(raw),
          'items': items,
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }

    for (final key in _cache.keysWithPrefix(
      'album:groups:$namespace:',
    )) {
      final raw = _cache.read<Object?>(key);
      if (raw is! List) continue;
      var changed = false;
      final groups = raw
          .map((groupValue) {
            if (groupValue is! Map) return groupValue;
            final group = Map<String, dynamic>.from(groupValue);
            final members = (group['members'] as List? ?? const [])
                .map((item) {
                  if (item is! Map || item['file_id']?.toString() != fileId) {
                    return item;
                  }
                  changed = true;
                  return summary;
                })
                .toList(growable: false);
            return {...group, 'members': members};
          })
          .toList(growable: false);
      if (changed) await _cache.write(key, groups);
    }
  }

  String? get _activeDeviceId {
    final value = _deviceId()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _removeQueuedReviewOperations(String fileId) {
    final deviceId = _activeDeviceId;
    return _pending.removeWhere(
      (operation) => operation.type == PendingOperationType.updateReview && operation.deviceId == deviceId && operation.payload['file_id']?.toString() == fileId,
    );
  }

  Future<void> _removeQueuedReviewOperationsSafely(String fileId) async {
    try {
      await _removeQueuedReviewOperations(fileId);
    } catch (_) {
      // The box has already accepted the latest decision. A stale local queue
      // entry can be surfaced in diagnostics instead of failing the save.
    }
  }

  String _optimisticKey(String fileId) => '${_cacheNamespace()}:$fileId';

  BirdGroup _withOptimisticGroup(BirdGroup group) => group.copyWith(
    members: group.members
        .map(
          (photo) => _optimisticDecisions[_optimisticKey(photo.id)] == null
              ? photo
              : PhotoSummary.fromJson(
                  mergeReviewDecisionIntoPhotoJson(
                    photo.toJson(),
                    _optimisticDecisions[_optimisticKey(photo.id)]!,
                  ),
                ),
        )
        .toList(growable: false),
  );

  ReviewDetail _withOptimisticDetail(ReviewDetail detail) {
    final decision = _optimisticDecisions[_optimisticKey(detail.photo.summary.id)];
    if (decision == null) return detail;
    final photo = detail.photo;
    return ReviewDetail(
      photo: PhotoDetail(
        summary: PhotoSummary.fromJson(
          mergeReviewDecisionIntoPhotoJson(
            photo.summary.toJson(),
            decision,
          ),
        ),
        subjects: photo.subjects,
        tags: photo.tags,
        exif: photo.exif,
      ),
      decision: decision,
      history: detail.history,
    );
  }

  Map<String, dynamic> _detailToJson(ReviewDetail detail) => {
    ...detail.photo.toJson(),
    if (detail.decision != null) 'decision': detail.decision!.toJson(),
    'history': detail.history.map((item) => item.toJson()).toList(),
  };

  ReviewDetail _detailFromJson(Map<String, dynamic> json) {
    final file = json['file'] is Map ? Map<String, dynamic>.from(json['file'] as Map) : json;
    return ReviewDetail(
      photo: PhotoDetail(
        summary: PhotoSummary.fromJson(file),
        subjects: (json['subjects'] as List? ?? const []).whereType<Map>().map((item) => SubjectBox.fromJson(Map<String, dynamic>.from(item))).toList(),
        tags: (json['tags'] as List? ?? const []).whereType<Map>().map((item) => BirdTag.fromJson(Map<String, dynamic>.from(item))).toList(),
        exif: json['exif'] is Map ? Map<String, dynamic>.from(json['exif'] as Map) : const {},
      ),
      decision: json['decision'] is Map ? UserDecision.fromJson(Map<String, dynamic>.from(json['decision'] as Map)) : null,
      history: (json['history'] as List? ?? const []).whereType<Map>().map((item) => VersionHistory.fromJson(Map<String, dynamic>.from(item))).toList(),
    );
  }

  PhotoSummary? _photoSummaryFromSnapshots(String fileId) {
    final prefix = 'album:photos:${_cacheNamespace()}:';
    for (final key in _cache.keysWithPrefix(prefix)) {
      final raw = _cache.read<Map>(key);
      if (raw == null) continue;
      for (final item in raw['items'] as List? ?? const []) {
        if (item is! Map || item['file_id']?.toString() != fileId) continue;
        return PhotoSummary.fromJson(Map<String, dynamic>.from(item));
      }
    }
    return null;
  }

  PhotoSummary _withDetailPreview(PhotoSummary summary) {
    final preview = summary.preview;
    if (preview.previewUri != null || preview.thumbnailUri == null) return summary;
    return PhotoSummary(
      id: summary.id,
      filename: summary.filename,
      format: summary.format,
      preview: PreviewRef(
        thumbnailUri: preview.thumbnailUri,
        previewUri: preview.thumbnailUri,
        width: preview.width,
        height: preview.height,
      ),
      analysisState: summary.analysisState,
      recognition: summary.recognition,
      rating: summary.rating,
      groupId: summary.groupId,
      sceneId: summary.sceneId,
      keepState: summary.keepState,
      clarityState: summary.clarityState,
      isRecommended: summary.isRecommended,
      userTags: summary.userTags,
      capturedAt: summary.capturedAt,
    );
  }
}

Map<String, dynamic> mergeReviewDecisionIntoPhotoJson(
  Map<dynamic, dynamic> source,
  UserDecision decision,
) {
  final photo = Map<String, dynamic>.from(source);
  photo['keep_state'] = decision.keepState.wireValue;
  photo['user_tags'] = decision.userTags;

  if (decision.userScore != null) {
    final rating = photo['rating'] is Map ? Map<String, dynamic>.from(photo['rating'] as Map) : <String, dynamic>{};
    rating['total_score'] = decision.userScore;
    photo['rating'] = rating;
  }

  final species = decision.userSpecies?.trim();
  if (species?.isNotEmpty == true) {
    final recognition = photo['recognition'] is Map ? Map<String, dynamic>.from(photo['recognition'] as Map) : <String, dynamic>{};
    final candidates = recognition['species_topn'] as List? ?? const [];
    final first = candidates.firstOrNull;
    final candidate = first is Map ? Map<String, dynamic>.from(first) : <String, dynamic>{};
    candidate
      ..['species_id'] = decision.userSpeciesId
      ..['name'] = species
      ..['confidence'] = (candidate['confidence'] as num?)?.toDouble() ?? 1.0;
    recognition
      ..['species_topn'] = [candidate]
      ..['low_confidence'] = false;
    photo['recognition'] = recognition;
  }

  return photo;
}
