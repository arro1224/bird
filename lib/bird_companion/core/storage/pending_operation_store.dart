import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

typedef _ReadPendingValue = Object? Function(String key);
typedef _WritePendingValue =
    Future<void> Function(
      String key,
      Object? value,
    );

class PendingOperationStore {
  PendingOperationStore(LocalCache cache)
    : this._(
        (key) => cache.read<Object?>(key),
        cache.write,
      );

  PendingOperationStore._(this._read, this._write);

  factory PendingOperationStore.memory() {
    final values = <String, Object?>{};
    return PendingOperationStore._(
      (key) => values[key],
      (key, value) async => values[key] = value,
    );
  }

  static const _key = 'pending_operations';
  final _ReadPendingValue _read;
  final _WritePendingValue _write;
  Future<void> _mutationTail = Future.value();

  List<PendingOperation> readAll() {
    final raw = _read(_key);
    final values = raw is List ? raw : const [];
    return values
        .whereType<Map>()
        .map(
          (value) => PendingOperation.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  PendingOperation? read(String id) => readAll().where((operation) => operation.id == id).firstOrNull;

  Future<void> save(
    PendingOperation operation, {
    bool Function(PendingOperation existing)? supersedes,
  }) => _mutate(() async {
    final all =
        readAll()
            .where(
              (item) => item.id != operation.id && !(supersedes?.call(item) ?? false),
            )
            .toList()
          ..add(operation);
    await _writeAll(all);
  });

  Future<void> remove(String id) => removeWhere((operation) => operation.id == id);

  Future<void> removeWhere(
    bool Function(PendingOperation operation) test,
  ) => _mutate(
    () => _writeAll(readAll().where((item) => !test(item)).toList()),
  );

  Future<void> _writeAll(List<PendingOperation> operations) => _write(_key, operations.map((item) => item.toJson()).toList());

  Future<void> _mutate(Future<void> Function() action) {
    final result = _mutationTail.then((_) => action());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return result;
  }
}
