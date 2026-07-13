import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

class LocalCache {
  LocalCache._(this._box);

  static const _boxName = 'bird_companion_cache';
  final Box<dynamic> _box;

  static Future<LocalCache> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<dynamic>(_boxName);
    return LocalCache._(box);
  }

  T? read<T>(String key) => _box.get(key) as T?;

  Future<void> write(String key, Object? value) => _box.put(key, value);

  Future<void> remove(String key) => _box.delete(key);

  Future<void> clearImageMetadata() async {
    final keys = _box.keys.where((key) => key.toString().startsWith('image:')).toList();
    await _box.deleteAll(keys);
  }

  int estimateBytes() => _box.toMap().entries.fold(0, (sum, entry) => sum + utf8.encode('${entry.key}:${entry.value}').length);

  Future<void> close() => _box.close();
}
