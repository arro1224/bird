import 'dart:async';
import 'package:dio/dio.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';

class SessionAuthenticationFailure {
  const SessionAuthenticationFailure(this.statusCode);
  final int statusCode;
}

class SessionAddressChange {
  const SessionAddressChange({
    required this.deviceId,
    required this.baseUri,
  });

  final String deviceId;
  final Uri baseUri;
}

class EventSessionNotReadyException extends TimeoutException {
  EventSessionNotReadyException() : super('Authenticated device event channel is not ready.');
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
  final _addressChanges = StreamController<SessionAddressChange>.broadcast(
    sync: true,
  );

  late final StreamSubscription<int> _apiFailureSubscription;
  late final StreamSubscription<int> _eventFailureSubscription;
  SessionCredential? _activeCredential;
  bool _invalidating = false;
  int _activationGeneration = 0;

  Stream<SessionAuthenticationFailure> get authenticationFailures => _authenticationFailures.stream;
  Stream<SessionAddressChange> get addressChanges => _addressChanges.stream;
  String? get activeDeviceId => _activeCredential?.deviceId;
  Uri? get activeBaseUri => _activeCredential?.baseUri;

  /// A WS socket alone is not identity proof; callers first validate public
  /// identity and a protected REST request for this exact active credential.
  void requireConnectedSession(String deviceId, Uri baseUri) {
    if (_activeCredential?.deviceId != deviceId || _activeCredential?.baseUri != baseUri) throw StateError('Verified session was superseded');
    if (_eventClient.currentState != EventConnectionState.connected) throw EventSessionNotReadyException();
  }

  Future<void> activate(
    SessionCredential credential, {
    bool persist = true,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancellationRequested();
    final generation = ++_activationGeneration;
    void checkCurrent() {
      cancelToken?.throwIfCancellationRequested();
      if (generation != _activationGeneration) throw StateError('Session activation superseded');
    }

    if (!credential.isUsableAt(_clock(), clockSkew: clockSkew)) {
      throw StateError('配对凭据已过期，请重新配对。');
    }
    final current = _activeCredential;
    if (current?.deviceId == credential.deviceId && current?.baseUri == credential.baseUri && current?.accessToken == credential.accessToken && _eventClient.currentState == EventConnectionState.connected) return;
    if (persist) {
      // Persist first. A process death must never leave an active token that
      // cannot be restored securely.
      await _store.write(credential);
      checkCurrent();
    }
    await _eventClient.disconnect();
    checkCurrent();
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
    checkCurrent();
    if (!_addressChanges.isClosed) {
      _addressChanges.add(
        SessionAddressChange(
          deviceId: credential.deviceId,
          baseUri: credential.baseUri,
        ),
      );
    }
  }

  Future<bool> restore({
    required String deviceId,
    required Uri baseUri,
    CancelToken? cancelToken,
  }) async {
    final generation = _activationGeneration;
    final stored = await _store.read(deviceId);
    cancelToken?.throwIfCancellationRequested();
    if (generation != _activationGeneration) throw StateError('Session restore superseded');
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
    await activate(credential, persist: credential != stored, cancelToken: cancelToken);
    return true;
  }

  Future<void> clearMemory() async {
    final generation = ++_activationGeneration;
    _activeCredential = null;
    await _eventClient.disconnect();
    if (generation != _activationGeneration) return;
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
    await _addressChanges.close();
  }
}
