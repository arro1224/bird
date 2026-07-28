import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/domain/review_checkpoint.dart';

typedef _ReadValue = Object? Function(String key);
typedef _WriteValue = Future<void> Function(String key, Object? value);
typedef _RemoveValue = Future<void> Function(String key);

class ReviewCheckpointStore {
  ReviewCheckpointStore(LocalCache cache)
    : this._(
        (key) => cache.read<Object?>(key),
        cache.write,
        cache.remove,
      );

  ReviewCheckpointStore._(this._read, this._write, this._remove);

  factory ReviewCheckpointStore.memory() {
    final values = <String, Object?>{};
    return ReviewCheckpointStore._(
      (key) => values[key],
      (key, value) async => values[key] = value,
      (key) async => values.remove(key),
    );
  }

  static const _prefix = 'review:checkpoint:';

  final _ReadValue _read;
  final _WriteValue _write;
  final _RemoveValue _remove;

  ReviewCheckpoint? read({
    required String deviceId,
    required String batchId,
  }) {
    if (deviceId.trim().isEmpty || batchId.trim().isEmpty) return null;
    final raw = _read(_key(deviceId, batchId));
    if (raw is! Map) return null;
    final checkpoint = ReviewCheckpoint.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (checkpoint.deviceId != deviceId || checkpoint.batchId != batchId) {
      return null;
    }
    return checkpoint;
  }

  Future<void> save(ReviewCheckpoint checkpoint) {
    if (checkpoint.deviceId.trim().isEmpty || checkpoint.batchId.trim().isEmpty) {
      return Future.value();
    }
    return _write(
      _key(checkpoint.deviceId, checkpoint.batchId),
      checkpoint.toJson(),
    );
  }

  Future<void> clear({
    required String deviceId,
    required String batchId,
  }) => _remove(_key(deviceId, batchId));

  Future<void> updateQuery({
    required String deviceId,
    required String batchId,
    required PhotoQuery query,
  }) {
    final current = read(deviceId: deviceId, batchId: batchId);
    return save(
      current?.withQuery(query) ??
          ReviewCheckpoint(
            deviceId: deviceId,
            batchId: batchId,
            query: query,
            updatedAt: DateTime.now(),
          ),
    );
  }

  String _key(String deviceId, String batchId) => '$_prefix${Uri.encodeComponent(deviceId)}:${Uri.encodeComponent(batchId)}';
}
