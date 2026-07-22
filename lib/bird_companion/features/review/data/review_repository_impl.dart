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

  @override
  Future<List<BirdGroup>> groups(String id, {String? sceneId}) async {
    final key = 'album:groups:${_cacheNamespace()}:$id:${sceneId ?? ''}';
    try {
      final items = await _api.groups(id, sceneId: sceneId);
      await _cache.write(key, items.map((item) => item.toJson()).toList());
      return items;
    } on ApiException {
      final raw = _cache.read<List<dynamic>>(key);
      if (raw == null) rethrow;
      return raw.whereType<Map>().map((item) => BirdGroup.fromJson(Map<String, dynamic>.from(item))).toList();
    }
  }

  @override
  Future<ReviewDetail> detail(String id) async {
    final key = 'album:detail:${_cacheNamespace()}:$id';
    try {
      final detail = await _api.detail(id);
      await _cache.write(key, _detailToJson(detail));
      return detail;
    } on ApiException {
      final raw = _cache.read<Map>(key);
      if (raw == null) rethrow;
      return _detailFromJson(Map<String, dynamic>.from(raw));
    }
  }

  @override
  Future<ReviewSaveResult> save(UserDecision v) async {
    try {
      if (!await _connectivity.hasNetwork) return _queue(v, '设备离线，修改将在重新连接后同步');
      await _api.save(v);
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
    await _pending.save(operation);
    final cacheKey = 'album:detail:${_cacheNamespace()}:${value.fileId}';
    final cached = _cache.read<Map>(cacheKey);
    if (cached != null) await _cache.write(cacheKey, {...Map<String, dynamic>.from(cached), 'decision': value.toJson()});
    return ReviewSaveResult(queued: true, message: message);
  }

  String? get _activeDeviceId {
    final value = _deviceId()?.trim();
    return value == null || value.isEmpty ? null : value;
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
}
