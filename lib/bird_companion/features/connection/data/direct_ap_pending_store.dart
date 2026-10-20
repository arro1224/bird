import 'dart:convert';

import 'package:flutter/services.dart';

abstract interface class DirectApAuthorizationStore {
  Future<Map<String, dynamic>?> load(String deviceId);
  Future<void> write(String deviceId, Map<String, dynamic> value);
  Future<void> remove(String deviceId);
}

/// Short-lived provisioning secrets use a separate Keystore namespace, never Hive.
final class EncryptedDirectApAuthorizationStore implements DirectApAuthorizationStore {
  const EncryptedDirectApAuthorizationStore();
  static const _channel = MethodChannel('bird_companion/secure_session');

  @override
  Future<Map<String, dynamic>?> load(String deviceId) async {
    final raw = await _channel.invokeMethod<String>('read', {'deviceId': 'direct-ap:$deviceId'});
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> write(String key, Map<String, dynamic> value) => _channel.invokeMethod<void>('write', {'deviceId': 'direct-ap:$key', 'payload': jsonEncode(value)});

  @override
  Future<void> remove(String key) => _channel.invokeMethod<void>('delete', {'deviceId': 'direct-ap:$key'});
}

final class MemoryDirectApAuthorizationStore implements DirectApAuthorizationStore {
  final _values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> load(String deviceId) async => _values[deviceId];
  @override
  Future<void> write(String deviceId, Map<String, dynamic> value) async {
    _values[deviceId] = value;
  }

  @override
  Future<void> remove(String deviceId) async {
    _values.remove(deviceId);
  }
}
