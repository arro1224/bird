import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class PendingOperationStore {
  PendingOperationStore(this._cache);

  static const _key = 'pending_operations';
  final LocalCache _cache;

  List<PendingOperation> readAll() {
    final raw = _cache.read<List<dynamic>>(_key) ?? const [];
    return raw.whereType<Map>().map((value) => PendingOperation.fromJson(Map<String, dynamic>.from(value))).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> save(PendingOperation operation) async {
    final all = readAll().where((item) => item.id != operation.id).toList()..add(operation);
    await _write(all);
  }

  Future<void> remove(String id) => _write(readAll().where((item) => item.id != id).toList());

  Future<void> _write(List<PendingOperation> operations) => _cache.write(_key, operations.map((item) => item.toJson()).toList());
}
