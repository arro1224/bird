import 'dart:convert';

import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:flutter/services.dart';

abstract interface class SecureSessionStore {
  Future<SessionCredential?> read(String deviceId);
  Future<void> write(SessionCredential credential);
  Future<void> delete(String deviceId);
}

/// Stores the encrypted credential payload through the Android Keystore
/// channel implemented by MainActivity. No plaintext token is written to Hive.
class AndroidKeystoreSessionStore implements SecureSessionStore {
  AndroidKeystoreSessionStore({
    this._channel = const MethodChannel(
      'bird_companion/secure_session',
    ),
  });

  final MethodChannel _channel;

  @override
  Future<SessionCredential?> read(String deviceId) async {
    final payload = await _channel.invokeMethod<String>(
      'read',
      {'deviceId': deviceId},
    );
    if (payload == null || payload.isEmpty) return null;
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('Invalid secure session payload.');
    }
    return SessionCredential.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> write(SessionCredential credential) => _channel.invokeMethod<void>(
    'write',
    {
      'deviceId': credential.deviceId,
      'payload': jsonEncode(credential.toJson()),
    },
  );

  @override
  Future<void> delete(String deviceId) => _channel.invokeMethod<void>(
    'delete',
    {'deviceId': deviceId},
  );
}

class MemorySecureSessionStore implements SecureSessionStore {
  final Map<String, SessionCredential> _sessions = {};

  @override
  Future<SessionCredential?> read(String deviceId) async => _sessions[deviceId];

  @override
  Future<void> write(SessionCredential credential) async {
    _sessions[credential.deviceId] = credential;
  }

  @override
  Future<void> delete(String deviceId) async {
    _sessions.remove(deviceId);
  }
}
