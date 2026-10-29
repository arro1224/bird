import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_attempt.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceSessionCubit extends Cubit<DeviceSessionState> {
  DeviceSessionCubit(
    this._repository,
    this._connectivityMonitor,
    this._eventClient,
    this._refreshCoordinator, {
    this.onConnectionRecovered,
    SessionCoordinator? sessionCoordinator,
    this.diagnostic,
    this.retryDelay = const Duration(seconds: 1),
    Stream<void>? transportChanges,
  }) : super(const DeviceSessionState()) {
    _networkSubscription = _connectivityMonitor.onNetworkChanged.listen((available) {
      if (!isClosed && !provisioningHandoffActive && available && state.phase == DeviceSessionPhase.disconnected && state.device != null) unawaited(reconnect());
    });
    _transportSubscription = transportChanges?.listen((_) {
      if (!isClosed && !provisioningHandoffActive && state.device != null && state.phase != DeviceSessionPhase.connecting) unawaited(verifySavedSession(intent: 'transport_changed'));
    });
    _eventSubscription = _eventClient.connectionStates.listen((eventState) {
      if (isClosed || !state.isConnected) return;
      switch (eventState) {
        case EventConnectionState.disconnected:
          emit(state.copyWith(message: _eventUnavailableMessage));
        case EventConnectionState.connected:
          if (state.message == _eventUnavailableMessage) emit(state.copyWith(clearMessage: true));
        case EventConnectionState.connecting:
        case EventConnectionState.reconnecting:
          break;
      }
    });
    _authenticationSubscription = sessionCoordinator?.authenticationFailures.listen((failure) {
      if (isClosed || sessionCoordinator.isCurrentAuthenticationFailure(failure) == false) return;
      _activeAttempt?.record('connection_authentication_invalidated', {'final_trigger': 'authentication_failure'});
      _invalidateConnection();
      emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: '设备授权已失效，请重新配对。'));
    });
    _addressSubscription = sessionCoordinator?.addressChanges.listen((change) {
      final device = state.device;
      // Session activation is not yet protected-HTTP verification. Its address
      // may be used only when this intent finally commits.
      if (isClosed || !state.isConnected || device == null || device.id != change.deviceId || (_activeAttempt != null && !_activeAttempt!.committed)) return;
      emit(
        state.copyWith(
          device: device.copyWith(baseUri: change.baseUri),
          lastUpdatedAt: DateTime.now(),
        ),
      );
      _refreshCoordinator.requestRefresh();
    });
  }

  final ConnectionRepository _repository;
  final ConnectivityMonitor _connectivityMonitor;
  final EventClient _eventClient;
  final SessionRefreshCoordinator _refreshCoordinator;
  final Future<void> Function()? onConnectionRecovered;
  final void Function(Map<String, dynamic>)? diagnostic;
  final Duration retryDelay;
  static const _eventUnavailableMessage = '实时事件连接暂不可用，页面会在刷新时读取最新状态。';
  late final StreamSubscription<bool> _networkSubscription;
  late final StreamSubscription<EventConnectionState> _eventSubscription;
  StreamSubscription<void>? _transportSubscription;
  StreamSubscription<SessionAuthenticationFailure>? _authenticationSubscription;
  StreamSubscription<SessionAddressChange>? _addressSubscription;
  bool _legacyHandoffActive = false;
  final _handoffOwners = <Object>{};
  bool _networkIntentPending = false;
  String? _intentId;
  int _connectionGeneration = 0;
  ConnectionAttempt? _activeAttempt;
  Future<bool>? _restoring;
  String? get activeAttemptId => _activeAttempt?.id ?? _intentId;
  bool get provisioningHandoffActive => _legacyHandoffActive || _handoffOwners.isNotEmpty || _networkIntentPending;
  set provisioningHandoffActive(bool value) {
    if (value && !_legacyHandoffActive) _invalidateConnection();
    _legacyHandoffActive = value;
  }

  void setHandoffActive(Object owner, bool value) {
    if (value) {
      if (_handoffOwners.add(owner)) _invalidateConnection(preserveIntent: true);
    } else {
      _handoffOwners.remove(owner);
    }
  }

  void beginNetworkIntent(String id) {
    if (isClosed || (_intentId == id && _networkIntentPending)) return;
    _invalidateConnection();
    _intentId = id;
    _networkIntentPending = true;
  }

  void endNetworkIntent(String id) {
    if (_intentId != id) return;
    _networkIntentPending = false;
    if (!state.isConnected && _handoffOwners.isEmpty) {
      _invalidateConnection();
      if (state.isVerifying) emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: '连接验证已结束。当前内容为手机缓存。'));
    }
  }

  bool acceptsNetworkIntent(String id) => !isClosed && _intentId == id;

  void _invalidateConnection({bool preserveIntent = false}) {
    _activeAttempt?.record('connection_superseded', {'final_trigger': 'new_intent_or_cancel'});
    ++_connectionGeneration;
    _activeAttempt?.token.cancel('Connection intent superseded');
    _activeAttempt = null;
    _restoring = null;
    if (!preserveIntent) {
      _intentId = null;
      _networkIntentPending = false;
    }
  }

  ConnectionAttempt _beginAttempt(String intent, {String? attemptId, String? deviceId, String? operationId, CancelToken? token}) {
    token?.throwIfCancellationRequested();
    _invalidateConnection(preserveIntent: attemptId != null);
    final generation = _connectionGeneration;
    final id = attemptId ?? SecureRequestIdFactory().create();
    _intentId = id;
    final attempt = ConnectionAttempt(
      id: id,
      generation: generation,
      token: token ?? CancelToken(),
      deviceId: deviceId,
      operationId: operationId,
      isCurrent: () => !isClosed && generation == _connectionGeneration,
      diagnostic: diagnostic,
      onStage: (stage) {
        if (isClosed || generation != _connectionGeneration) return;
        final message = switch (stage) {
          'events' => '盒子已联网，正在验证实时连接。',
          'protected_http' => '盒子已联网，正在验证授权连接。',
          _ => '正在恢复并验证盒子连接，当前相册可能来自手机缓存。',
        };
        emit(state.copyWith(attemptId: id, operationId: operationId, verificationStage: stage, message: message));
      },
    );
    _activeAttempt = attempt;
    attempt.record('connection_intent_started', {'intent': intent});
    return attempt;
  }

  ConnectionAttempt beginEndpointVerification({required String attemptId, required String deviceId, required String operationId, required CancelToken token}) {
    token.throwIfCancellationRequested();
    if (!acceptsNetworkIntent(attemptId)) throw StateError('Network intent superseded');
    final active = _activeAttempt;
    if (active != null && identical(active.token, token) && active.id == attemptId) {
      active.check();
      return active;
    }
    final attempt = _beginAttempt('network_handoff', attemptId: attemptId, deviceId: deviceId, operationId: operationId, token: token);
    emit(state.copyWith(phase: DeviceSessionPhase.connecting, attemptId: attemptId, operationId: operationId, message: '盒子已联网，正在验证连接。'));
    return attempt;
  }

  void connecting() {
    if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.connecting, clearMessage: true));
  }

  Future<void> connected(DeviceSessionState next) async {
    if (isClosed) return;
    _invalidateConnection();
    emit(next);
    _refreshCoordinator.requestRefresh();
    unawaited(_synchronizeAfterConnection());
  }

  Future<void> setConnectedFromStatus(dynamic status, {ConnectionAttempt? attempt}) async {
    if (attempt == null) {
      await connected(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
      return;
    }
    attempt.check();
    if (attempt.deviceId != null && status.connection.id != attempt.deviceId) throw StateError('Verified device identity mismatch');
    attempt.committed = true;
    _restoring = null;
    _networkIntentPending = false;
    attempt.record('connection_committed', {'http_result': 'protected_read_ok', 'ws_state': _eventClient.currentState.name, 'final_trigger': 'verified_session'});
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now(), attemptId: attempt.id, operationId: attempt.operationId, verificationStage: 'connected'));
    _refreshCoordinator.requestRefresh();
    unawaited(_synchronizeAfterConnection());
  }

  /// One total budget includes cached-device lookup, connectivity, identity,
  /// secure credential restore, protected REST and the authenticated event gate.
  Future<bool> restoreSavedSession({Duration timeout = const Duration(seconds: 20)}) => _verifySavedSession(timeout: timeout, force: false, intent: 'cold_restore');

  /// Seed only public metadata before choosing the first page. Network work
  /// then runs while the saved album shell can display its recovery state.
  void seedSavedDevice(DeviceConnection device) {
    if (!isClosed && state.device == null) emit(DeviceSessionState(phase: DeviceSessionPhase.reconnecting, device: device, message: '正在恢复盒子连接，当前相册为手机缓存。'));
  }

  Future<bool> verifySavedSession({Duration timeout = const Duration(seconds: 20), String? expectedDeviceId, String intent = 'explicit_reconnect'}) =>
      _verifySavedSession(timeout: timeout, force: true, expectedDeviceId: expectedDeviceId, intent: intent);

  Future<bool> _verifySavedSession({required Duration timeout, required bool force, required String intent, String? expectedDeviceId}) {
    if (isClosed || provisioningHandoffActive) return Future<bool>.value(false);
    if (!force && state.isConnected) return Future<bool>.value(true);
    if (_restoring != null && (expectedDeviceId == null || _activeAttempt?.deviceId == expectedDeviceId)) return _restoring!;
    final attempt = _beginAttempt(intent, deviceId: expectedDeviceId);
    final future = _restoreSavedSession(attempt, timeout: timeout, expectedDeviceId: expectedDeviceId);
    _restoring = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_restoring, future)) _restoring = null;
      }),
    );
    return future;
  }

  Future<bool> _restoreSavedSession(ConnectionAttempt attempt, {required Duration timeout, String? expectedDeviceId}) async {
    final timer = Timer(timeout, () {
      if (attempt.isCurrent() && !attempt.committed) {
        attempt.record('connection_deadline', {'timeout_ms': timeout.inMilliseconds, 'final_trigger': 'deadline'});
        attempt.token.cancel(TimeoutException('Connection verification deadline'));
      }
    });
    try {
      return await Future.any<bool>([
        _runSavedVerification(attempt, expectedDeviceId: expectedDeviceId),
        attempt.token.whenCancel.then<bool>((error) => throw error),
      ]);
    } catch (error) {
      if (!isClosed && attempt.isCurrent() && !attempt.committed) {
        attempt.record('connection_failed', {'final_trigger': 'verification_failed', ...ConnectionAttempt.errorFields(error)});
        final message = error is PairingRequiredException || error is ApiException && {401, 403}.contains(error.statusCode)
            ? '盒子可达，但手机授权已失效。请重新安全授权，无需重复配网。'
            : error is ProvisioningException && error.code == ProvisioningErrorCode.deviceIdMismatch
            ? '设备身份不一致，已停止恢复。当前内容为手机缓存。'
            : attempt.stage == 'events'
            ? '盒子已联网，但实时连接尚未验证完成。可继续验证，无需重复配网。'
            : '暂时无法验证盒子连接，可重试原设备。当前相册为手机缓存。';
        emit(state.copyWith(phase: DeviceSessionPhase.disconnected, attemptId: attempt.id, verificationStage: attempt.stage, message: message));
      }
      return false;
    } finally {
      timer.cancel();
    }
  }

  Future<bool> _runSavedVerification(ConnectionAttempt attempt, {String? expectedDeviceId}) async {
    final device = await attempt.run('saved_device', _repository.savedDevice);
    attempt.record('saved_device_loaded', {'saved_device_present': device != null, if (device != null) 'base_uri': device.baseUri.toString(), 'endpoint_source': 'saved'});
    if (device == null || (expectedDeviceId != null && device.id != expectedDeviceId)) {
      attempt.record('connection_not_restored', {'final_trigger': device == null ? 'no_saved_device' : 'saved_identity_mismatch'});
      return false;
    }
    attempt.deviceId = device.id;
    final wasConnected = state.isConnected && state.device?.id == device.id;
    if (!wasConnected) emit(DeviceSessionState(phase: DeviceSessionPhase.reconnecting, device: device, attemptId: attempt.id, verificationStage: 'connectivity', message: '正在恢复上次的盒子连接，当前相册为手机缓存。'));
    var hasNetwork = await attempt.run('connectivity', () => _connectivityMonitor.hasNetwork);
    attempt.record('network_checked', {'has_network': hasNetwork});
    if (!hasNetwork) {
      // The OS may briefly report none while Wi-Fi is settling after startup.
      await Future<void>.delayed(retryDelay);
      attempt.check();
      hasNetwork = await attempt.run('connectivity', () => _connectivityMonitor.hasNetwork);
      if (!hasNetwork) {
        if (!wasConnected) emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: '等待手机网络恢复。当前相册为手机缓存。'));
        attempt.record('connection_deferred', {'has_network': false, 'final_trigger': 'network_unavailable'});
        return false;
      }
    }
    while (true) {
      attempt.check();
      try {
        final status = await _repository.reconnect(cancelToken: attempt.token);
        attempt.check();
        await setConnectedFromStatus(status, attempt: attempt);
        return true;
      } catch (error) {
        attempt.check();
        if (wasConnected && error is EventSessionNotReadyException) {
          attempt.committed = true;
          emit(state.copyWith(message: _eventUnavailableMessage));
          attempt.record('connection_kept', {'http_result': 'protected_read_ok', 'ws_state': _eventClient.currentState.name, 'final_trigger': 'events_degraded'});
          return true;
        }
        final retryable =
            error is EventSessionNotReadyException ||
            error is TimeoutException ||
            (error is ApiException && error.retryable && !{401, 403}.contains(error.statusCode)) ||
            (error is DioException && error.type != DioExceptionType.badResponse);
        if (!retryable) rethrow;
        if (error is EventSessionNotReadyException) {
          attempt.stage = 'events';
          emit(state.copyWith(message: '盒子已联网，正在验证实时连接。', verificationStage: 'events'));
        }
        attempt.record('connection_retry_wait', ConnectionAttempt.errorFields(error));
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<void> _synchronizeAfterConnection() async {
    final generation = _connectionGeneration;
    try {
      await onConnectionRecovered?.call();
      if (!isClosed && generation == _connectionGeneration && state.isConnected) _refreshCoordinator.requestRefresh();
    } catch (_) {
      if (!isClosed && generation == _connectionGeneration) emit(state.copyWith(message: '已连接盒子，手机上保存的修改会自动传回盒子。'));
    }
  }

  @Deprecated('Use setConnectedFromStatus so refresh and offline synchronization are also performed.')
  void setConnectedFromStatusWithoutRecovery(dynamic status) {
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
  }

  Future<void> reconnect() async {
    if (isClosed || provisioningHandoffActive || state.device == null) return;
    await verifySavedSession();
  }

  void disconnected([String? message, bool clearDevice = false]) {
    _invalidateConnection(preserveIntent: provisioningHandoffActive);
    if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: message, clearDevice: clearDevice));
  }

  @override
  Future<void> close() async {
    _invalidateConnection();
    await _networkSubscription.cancel();
    await _transportSubscription?.cancel();
    await _eventSubscription.cancel();
    await _authenticationSubscription?.cancel();
    await _addressSubscription?.cancel();
    return super.close();
  }
}
