import 'package:hive_flutter/hive_flutter.dart';
import 'package:aves/bird_companion/core/storage/cache_schema_migrator.dart';
import 'dart:convert';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';

class LocalCache implements DiagnosticStorage {
  LocalCache._(this._box);

  static const _boxName = 'bird_companion_cache';
  final Box<dynamic> _box;

  static Future<LocalCache> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<dynamic>(_boxName);
    final migrationWrites = CacheSchemaMigrator.writesFor(box.toMap());
    if (migrationWrites.isNotEmpty) {
      await box.putAll(migrationWrites);
    }
    return LocalCache._(box);
  }

  @override
  T? read<T>(String key) => _box.get(key) as T?;

  List<String> keysWithPrefix(String prefix) => _box.keys.map((key) => key.toString()).where((key) => key.startsWith(prefix)).toList(growable: false);

  @override
  Future<void> write(String key, Object? value) => _box.put(key, value);

  @override
  Future<void> remove(String key) => _box.delete(key);

  Future<void> clearImageMetadata() async {
    final keys = _box.keys.where((key) => key.toString().startsWith('image:')).toList();
    await _box.deleteAll(keys);
  }

  Future<void> clearAlbumSnapshots() async {
    final keys = _box.keys.where((key) => key.toString().startsWith('album:')).toList();
    await _box.deleteAll(keys);
  }

  int estimateBytes() => _box.toMap().entries.fold(0, (sum, entry) => sum + utf8.encode('${entry.key}:${entry.value}').length);

  int estimateBytesWithPrefix(String prefix) => _box
      .toMap()
      .entries
      .where((entry) => entry.key.toString().startsWith(prefix))
      .fold(
        0,
        (sum, entry) => sum + utf8.encode('${entry.key}:${entry.value}').length,
      );

  Future<void> close() => _box.close();
}
