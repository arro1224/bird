import 'dart:async';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';

class SessionAuthenticationFailure {
  const SessionAuthenticationFailure(this.statusCode);
  final int statusCode;
}

/// Owns the one active device identity shared by REST and WebSocket.
class SessionCoordinator {
  SessionCoordinator(
    this._apiClient,
    this._eventClient,
    this._store, {
    DateTime Function()? clock,
    this.clockSkew = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now {
    _apiFailureSubscription = _apiClient.authenticationFailures.listen(
      _handleAuthenticationFailure,
    );
    _eventFailureSubscription = _eventClient.authenticationFailures.listen(
      _handleAuthenticationFailure,
    );
  }

  final ApiClient _apiClient;
  final EventClient _eventClient;
  final SecureSessionStore _store;
  final DateTime Function() _clock;
  final Duration clockSkew;
  final _authenticationFailures = StreamController<SessionAuthenticationFailure>.broadcast();

  late final StreamSubscription<int> _apiFailureSubscription;
  late final StreamSubscription<int> _eventFailureSubscription;
  SessionCredential? _activeCredential;
  bool _invalidating = false;

  Stream<SessionAuthenticationFailure> get authenticationFailures => _authenticationFailures.stream;
  String? get activeDeviceId => _activeCredential?.deviceId;

  Future<void> activate(
    SessionCredential credential, {
    bool persist = true,
  }) async {
    if (!credential.isUsableAt(_clock(), clockSkew: clockSkew)) {
      throw StateError('配对凭据已过期，请重新配对。');
    }
    if (persist) {
      // Persist first. A process death must never leave an active token that
      // cannot be restored securely.
      await _store.write(credential);
    }
    await _eventClient.disconnect();
    _apiClient.setSession(
      accessToken: credential.accessToken,
      apiVersion: credential.apiVersion,
    );
    _apiClient.configure(credential.baseUri);
    _activeCredential = credential;
    final eventUri = credential.baseUri.replace(
      scheme: credential.baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: ApiEndpoints.events,
      query: null,
      fragment: null,
    );
    await _eventClient.connect(
      eventUri,
      accessToken: credential.accessToken,
      apiVersion: credential.apiVersion,
    );
  }

  Future<bool> restore({
    required String deviceId,
    required Uri baseUri,
  }) async {
    final stored = await _store.read(deviceId);
    if (stored == null) return false;
    if (!stored.isUsableAt(_clock(), clockSkew: clockSkew)) {
      await _store.delete(deviceId);
      return false;
    }
    final credential = stored.baseUri == baseUri
        ? stored
        : SessionCredential(
            deviceId: stored.deviceId,
            baseUri: baseUri,
            accessToken: stored.accessToken,
            expiresAt: stored.expiresAt,
            apiVersion: stored.apiVersion,
            clientId: stored.clientId,
          );
    await activate(credential, persist: credential != stored);
    return true;
  }

  Future<void> clearMemory() async {
    _activeCredential = null;
    await _eventClient.disconnect();
    _apiClient.clearSession();
  }

  Future<void> forget(String deviceId) async {
    await clearMemory();
    await _store.delete(deviceId);
  }

  void _handleAuthenticationFailure(int statusCode) {
    if (_invalidating) return;
    _invalidating = true;
    final invalidDeviceId = _activeCredential?.deviceId;
    unawaited(
      (() async {
        await clearMemory();
        if (invalidDeviceId != null) {
          await _store.delete(invalidDeviceId);
        }
        if (!_authenticationFailures.isClosed) {
          _authenticationFailures.add(SessionAuthenticationFailure(statusCode));
        }
      })().whenComplete(() => _invalidating = false),
    );
  }

  Future<void> dispose() async {
    await _apiFailureSubscription.cancel();
    await _eventFailureSubscription.cancel();
    await _authenticationFailures.close();
  }
}
