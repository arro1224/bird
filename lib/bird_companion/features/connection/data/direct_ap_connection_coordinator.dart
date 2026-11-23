import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:dio/dio.dart';

enum DirectApConnectionPhase { idle, preparing, joining, networkAvailable, validating, online, failed, cancelled }

/// Application-lifetime owner of the local Wi-Fi request. BLE and page owners
/// never release this lease. Only a matching intent or explicit network change can.
final class DirectApConnectionCoordinator {
  DirectApConnectionCoordinator(this._wifi, {this.diagnostic}) {
    _losses = _wifi.networkLosses.listen((loss) {
      if (_network?.handle != loss.handle) return;
      _network = null;
      _lost = true;
      _generation++;
      _phase = DirectApConnectionPhase.failed;
      _record('native_join_lost');
    }, onError: (Object error, StackTrace stack) => _record('native_network_event_invalid'));
  }

  final BirdBoxWifiPlatform _wifi;
  final void Function(Map<String, dynamic>)? diagnostic;
  late final StreamSubscription<WifiNetworkLoss> _losses;
  DirectApConnectionPhase _phase = DirectApConnectionPhase.idle;
  DirectApConnectionPhase get phase => _phase;
  String? _deviceId, _operationId, _intentId, _ssid, _passphrase;
  WifiSecurity? _security;
  int _networkGeneration = 0;
  int get networkGeneration => _networkGeneration;
  String? get intentId => _intentId;
  BirdBoxWifiNetwork? _network;
  Future<void>? _joining;
  Future<void> _releaseBarrier = Future<void>.value();
  int _generation = 0;
  bool _requested = false, _disposed = false, _lost = false;
  CancelToken? _verificationToken;

  void _record(String event, {String? reason}) {
    diagnostic?.call({
      'event': event,
      'device_id': _deviceId,
      'operation_id': _operationId,
      'attempt_id': _intentId,
      'generation': _generation,
      'phase': _phase.name,
      'release_reason': ?reason,
    });
  }

  bool owns(String intentId) => !_disposed && _intentId == intentId;

  Future<void> selectDevice(String? deviceId) {
    final previous = _deviceId;
    return previous != null && previous != deviceId ? release(reason: 'device_changed', deviceId: previous) : Future<void>.value();
  }

  Future<void> connect({
    required String deviceId,
    required String operationId,
    required String intentId,
    required String ssid,
    required String passphrase,
    required CancelToken cancelToken,
    WifiSecurity security = WifiSecurity.wpa2Personal,
  }) {
    cancelToken.throwIfCancellationRequested();
    if (_disposed) throw StateError('Direct AP owner disposed');
    if (_deviceId == deviceId && _operationId == operationId && _intentId == intentId && _ssid == ssid && _passphrase == passphrase && _security == security && _joining != null) {
      if (_lost) return Future<void>.error(const ProvisioningException(code: ProvisioningErrorCode.networkSwitchFailed, retryable: false));
      _watchCancellation(cancelToken, _generation, intentId);
      return _joining!;
    }

    final reusable = _deviceId == deviceId && _ssid == ssid && _passphrase == passphrase && _security == security && _network != null && _wifi.boundNetwork?.handle == _network!.handle;
    if (!reusable) unawaited(release(reason: 'replaced').catchError((Object _) {}));
    final generation = ++_generation;
    _deviceId = deviceId;
    _operationId = operationId;
    _intentId = intentId;
    _ssid = ssid;
    _passphrase = passphrase;
    _security = security;
    _lost = false;
    _phase = reusable ? DirectApConnectionPhase.validating : DirectApConnectionPhase.preparing;
    final barrier = _releaseBarrier;
    // Cancellation invalidates the lease synchronously, even if the platform
    // has not yet delivered onAvailable. A completed business session survives
    // cancellation of its former page's verification token.
    _watchCancellation(cancelToken, generation, intentId);
    final future = _connect(generation, barrier, reusable, ssid, passphrase, security, cancelToken);
    _joining = future;
    return future;
  }

  void _watchCancellation(CancelToken token, int generation, String intentId) {
    _verificationToken = token;
    unawaited(
      token.whenCancel.then((_) async {
        if (_generation != generation || !identical(_verificationToken, token) || _phase == DirectApConnectionPhase.online) return;
        try {
          await release(reason: 'cancelled', intentId: intentId);
        } catch (_) {
          _record('native_release_failed');
        }
      }),
    );
  }

  Future<void> _connect(int generation, Future<void> barrier, bool reusable, String ssid, String passphrase, WifiSecurity security, CancelToken token) async {
    void check() {
      if (_disposed || generation != _generation) {
        token.throwIfCancellationRequested();
        throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: false);
      }
      _verificationToken?.throwIfCancellationRequested();
    }

    try {
      await barrier;
      check();
      if (reusable) {
        _record('native_join_reused');
        return;
      }
      if (!await _wifi.ensurePermissions()) throw const ProvisioningException(code: ProvisioningErrorCode.localNetworkPermissionDenied, retryable: false);
      check();
      _phase = DirectApConnectionPhase.joining;
      _requested = true;
      _record('native_join_started');
      final result = await _wifi.joinDirectAp(ssid: ssid, passphrase: passphrase, security: security);
      check();
      if (!result.joined) {
        throw ProvisioningException(
          code: switch (result.outcome) {
            WifiJoinOutcome.userCancelled => ProvisioningErrorCode.userCancelledWifiDialog,
            WifiJoinOutcome.deniedNoInternet => ProvisioningErrorCode.phoneRejectedNoInternetNetwork,
            WifiJoinOutcome.systemDenied => ProvisioningErrorCode.systemWifiJoinDenied,
            _ => ProvisioningErrorCode.networkSwitchFailed,
          },
          retryable: false,
        );
      }
      if (result.network!.ssid != ssid) throw const ProvisioningProtocolException('wifi_join.ssid', 'does not match the requested AP');
      _phase = DirectApConnectionPhase.networkAvailable;
      _record('native_join_available');
      await _wifi.bindProcessToNetwork(result.network!);
      check();
      _network = result.network;
      _networkGeneration++;
      _phase = DirectApConnectionPhase.validating;
      _record('native_network_bound');
    } catch (error, stack) {
      if (generation == _generation) {
        _phase = DirectApConnectionPhase.failed;
        _record('native_join_failed');
        try {
          await _queueRelease('join_failed');
        } catch (_) {
          _record('native_release_failed');
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  void markOnline(String intentId) {
    if (!owns(intentId) || _network == null) return;
    _phase = DirectApConnectionPhase.online;
    _record('direct_ap_business_online');
  }

  Future<void> release({required String reason, String? intentId, String? deviceId, bool force = false}) {
    if (intentId != null && intentId != _intentId || deviceId != null && deviceId != _deviceId) return Future<void>.value();
    ++_generation;
    _phase = reason == 'cancelled' ? DirectApConnectionPhase.cancelled : DirectApConnectionPhase.idle;
    _record('direct_ap_lease_released', reason: reason);
    _joining = null;
    _intentId = null;
    _ssid = _passphrase = null;
    return _queueRelease(reason, force: force);
  }

  Future<void> _queueRelease(String reason, {bool force = false}) {
    final release = _releaseBarrier.then(
      (_) => _releaseNative(reason, force: force),
      onError: (Object error, StackTrace stack) => _releaseNative(reason, force: force),
    );
    _releaseBarrier = release;
    return release;
  }

  Future<void> _releaseNative(String reason, {bool force = false}) async {
    if (!force && !_requested && _network == null && _wifi.boundNetwork == null) return;
    await _wifi.releaseNetwork(reason: reason == 'cancelled' ? 'user_cancelled' : reason);
    _requested = false;
    _network = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await release(reason: 'disposed');
    await _losses.cancel();
  }
}
