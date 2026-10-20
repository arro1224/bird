import 'dart:async';

import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceSessionCubit extends Cubit<DeviceSessionState> {
  DeviceSessionCubit(this._repository, this._connectivityMonitor, this._eventClient, this._refreshCoordinator, {this.onConnectionRecovered, SessionCoordinator? sessionCoordinator}) : super(const DeviceSessionState()) {
    _networkSubscription = _connectivityMonitor.onNetworkChanged.listen((available) {
      if (!isClosed && !provisioningHandoffActive && available && state.phase == DeviceSessionPhase.disconnected && state.device != null) reconnect();
    });
    _eventSubscription = _eventClient.connectionStates.listen((eventState) {
      if (isClosed || !state.isConnected) return;
      switch (eventState) {
        case EventConnectionState.disconnected:
          // A WebSocket outage does not prove that the device REST session is
          // unavailable. Keep the device connected and let ordinary refreshes
          // read the latest state until the event channel returns.
          emit(state.copyWith(message: _eventUnavailableMessage));
        case EventConnectionState.connected:
          if (state.message == _eventUnavailableMessage) {
            emit(state.copyWith(clearMessage: true));
          }
        case EventConnectionState.connecting:
        case EventConnectionState.reconnecting:
          break;
      }
    });
    _authenticationSubscription = sessionCoordinator?.authenticationFailures.listen((_) {
      if (!isClosed) {
        _invalidateConnection();
        emit(
          state.copyWith(
            phase: DeviceSessionPhase.disconnected,
            message: '设备授权已失效，请重新配对。',
          ),
        );
      }
    });
    _addressSubscription = sessionCoordinator?.addressChanges.listen((change) {
      final device = state.device;
      if (isClosed || device == null || device.id != change.deviceId) return;
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
  bool _provisioningHandoffActive = false;
  bool get provisioningHandoffActive => _provisioningHandoffActive;
  set provisioningHandoffActive(bool value) {
    if (value && !_provisioningHandoffActive) _invalidateConnection();
    _provisioningHandoffActive = value;
  }

  int _connectionGeneration = 0;
  CancelToken? _connectionCancel;
  Future<bool>? _restoring;
  void _invalidateConnection() {
    ++_connectionGeneration;
    _connectionCancel?.cancel('Connection attempt superseded');
    _connectionCancel = null;
  }

  final Future<void> Function()? onConnectionRecovered;
  static const _eventUnavailableMessage = '实时事件连接暂不可用，页面会在刷新时读取最新状态。';
  late final StreamSubscription<bool> _networkSubscription;
  late final StreamSubscription<EventConnectionState> _eventSubscription;
  StreamSubscription<SessionAuthenticationFailure>? _authenticationSubscription;
  StreamSubscription<SessionAddressChange>? _addressSubscription;

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

  Future<void> setConnectedFromStatus(dynamic status) => connected(
    DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()),
  );

  /// Restores the previously selected device without leaving an unbounded
  /// startup request in flight. A failed restore keeps the device in session
  /// so the connection page can offer a one-tap retry.
  Future<bool> restoreSavedSession({Duration timeout = const Duration(seconds: 5)}) async {
    return _verifySavedSession(timeout: timeout, force: false);
  }

  /// Used on explicit reconnect and foreground restore. Online cache alone is
  /// not proof. All callers coalesce around one cancellable verification.
  Future<bool> verifySavedSession({Duration timeout = const Duration(seconds: 12), String? expectedDeviceId}) async {
    final saved = await _repository.savedDevice();
    if (expectedDeviceId != null && saved?.id != expectedDeviceId) return false;
    return _verifySavedSession(timeout: timeout, force: true);
  }

  Future<bool> _verifySavedSession({required Duration timeout, required bool force}) {
    if (_restoring != null) return _restoring!;
    final future = _restoreSavedSession(timeout: timeout, force: force);
    _restoring = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_restoring, future)) _restoring = null;
      }),
    );
    return future;
  }

  Future<bool> _restoreSavedSession({required Duration timeout, required bool force}) async {
    if (provisioningHandoffActive) return false;
    if (isClosed || (!force && state.isConnected)) return state.isConnected;
    _invalidateConnection();
    final generation = _connectionGeneration;
    final device = await _repository.savedDevice();
    if (device == null || isClosed || generation != _connectionGeneration) return false;
    final wasConnected = state.isConnected && state.device?.id == device.id;
    if (!wasConnected) emit(DeviceSessionState(phase: DeviceSessionPhase.disconnected, device: device));
    final hasNetwork = await _connectivityMonitor.hasNetwork;
    if (isClosed || generation != _connectionGeneration) return false;
    if (!hasNetwork) {
      emit(state.copyWith(phase: DeviceSessionPhase.disconnected));
      return false;
    }

    final cancelToken = CancelToken();
    _connectionCancel = cancelToken;
    if (!wasConnected) emit(state.copyWith(phase: DeviceSessionPhase.reconnecting));
    try {
      final status = await _repository
          .reconnect(cancelToken: cancelToken)
          .timeout(
            timeout,
            onTimeout: () {
              cancelToken.cancel('Startup reconnection timed out.');
              throw TimeoutException('Startup reconnection timed out.');
            },
          );
      if (isClosed || generation != _connectionGeneration || cancelToken.isCancelled) return false;
      await setConnectedFromStatus(status);
      return true;
    } catch (error) {
      if (!isClosed && generation == _connectionGeneration && wasConnected && error is EventSessionNotReadyException) {
        // REST was identity/auth verified by the repository. A transient WS
        // outage may degrade live refresh, but cannot erase an existing session.
        emit(state.copyWith(message: _eventUnavailableMessage));
        return true;
      }
      if (!isClosed && generation == _connectionGeneration) emit(state.copyWith(phase: DeviceSessionPhase.disconnected));
      return false;
    }
  }

  Future<void> _synchronizeAfterConnection() async {
    final generation = _connectionGeneration;
    try {
      await onConnectionRecovered?.call();
      // Retained writes may have changed gallery and review data after the
      // first refresh emitted by connected(). Ask mounted feature cubits for a
      // second, final read once synchronization is complete.
      _refreshCoordinator.requestRefresh();
    } catch (_) {
      // The session is healthy even if retained writes cannot be replayed yet.
      if (!isClosed && generation == _connectionGeneration) emit(state.copyWith(message: '已连接盒子，手机上保存的修改会自动传回盒子。'));
    }
  }

  @Deprecated('Use setConnectedFromStatus so refresh and offline synchronization are also performed.')
  void setConnectedFromStatusWithoutRecovery(dynamic status) {
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
  }

  Future<void> reconnect() async {
    if (isClosed || provisioningHandoffActive || state.phase == DeviceSessionPhase.reconnecting || state.device == null) return;
    await verifySavedSession();
  }

  void disconnected([String? message, bool clearDevice = false]) {
    _invalidateConnection();
    if (!isClosed) {
      emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: message, clearDevice: clearDevice));
    }
  }

  @override
  Future<void> close() async {
    _invalidateConnection();
    await _networkSubscription.cancel();
    await _eventSubscription.cancel();
    await _authenticationSubscription?.cancel();
    await _addressSubscription?.cancel();
    return super.close();
  }
}
