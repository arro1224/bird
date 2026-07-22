import 'dart:async';

import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceSessionCubit extends Cubit<DeviceSessionState> {
  DeviceSessionCubit(this._repository, this._connectivityMonitor, this._eventClient, this._refreshCoordinator, {this.onConnectionRecovered}) : super(const DeviceSessionState()) {
    _networkSubscription = _connectivityMonitor.onNetworkChanged.listen((available) {
      if (!isClosed && available && state.phase == DeviceSessionPhase.disconnected && state.device != null) reconnect();
    });
    _eventSubscription = _eventClient.connectionStates.listen((eventState) {
      if (!isClosed && eventState == EventConnectionState.disconnected && state.device != null) {
        // HTTP 状态查询仍可正常工作；模拟盒子或旧版真实盒子未提供 WebSocket 时，
        // 不应把整台设备误判为断线。
        emit(state.copyWith(message: '实时事件连接暂不可用，页面会在刷新时读取最新状态。'));
      }
    });
  }

  final ConnectionRepository _repository;
  final ConnectivityMonitor _connectivityMonitor;
  final EventClient _eventClient;
  final SessionRefreshCoordinator _refreshCoordinator;
  final Future<void> Function()? onConnectionRecovered;
  late final StreamSubscription<bool> _networkSubscription;
  late final StreamSubscription<EventConnectionState> _eventSubscription;

  void connecting() {
    if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.connecting, clearMessage: true));
  }

  Future<void> connected(DeviceSessionState next) async {
    if (isClosed) return;
    emit(next);
    _refreshCoordinator.requestRefresh();
    await _synchronizeAfterConnection();
  }

  Future<void> setConnectedFromStatus(dynamic status) => connected(
    DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()),
  );

  /// Restores the previously selected device without leaving an unbounded
  /// startup request in flight. A failed restore keeps the device in session
  /// so the connection page can offer a one-tap retry.
  Future<bool> restoreSavedSession({Duration timeout = const Duration(seconds: 5)}) async {
    if (isClosed || state.isConnected) return state.isConnected;
    final device = await _repository.savedDevice();
    if (device == null || isClosed) return false;
    emit(DeviceSessionState(phase: DeviceSessionPhase.disconnected, device: device));
    if (!await _connectivityMonitor.hasNetwork || isClosed) return false;

    final cancelToken = CancelToken();
    emit(state.copyWith(phase: DeviceSessionPhase.reconnecting));
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
      if (isClosed) return false;
      await setConnectedFromStatus(status);
      return true;
    } catch (_) {
      if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.disconnected));
      return false;
    }
  }

  Future<void> _synchronizeAfterConnection() async {
    try {
      await onConnectionRecovered?.call();
      // Retained writes may have changed gallery and review data after the
      // first refresh emitted by connected(). Ask mounted feature cubits for a
      // second, final read once synchronization is complete.
      _refreshCoordinator.requestRefresh();
    } catch (_) {
      // The session is healthy even if retained writes cannot be replayed yet.
      if (!isClosed) emit(state.copyWith(message: '已连接盒子，手机上保存的修改会自动传回盒子。'));
    }
  }

  @Deprecated('Use setConnectedFromStatus so refresh and offline synchronization are also performed.')
  void setConnectedFromStatusWithoutRecovery(dynamic status) {
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
  }

  Future<void> reconnect() async {
    if (isClosed || state.phase == DeviceSessionPhase.reconnecting || state.device == null) return;
    emit(state.copyWith(phase: DeviceSessionPhase.reconnecting, message: '正在重新连接盒子…'));
    try {
      final status = await _repository.reconnect();
      if (isClosed) return;
      await setConnectedFromStatus(status);
    } catch (_) {
      if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: '自动重连失败，可手动重新连接。'));
    }
  }

  void disconnected([String? message, bool clearDevice = false]) {
    if (!isClosed) {
      emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: message, clearDevice: clearDevice));
    }
  }

  @override
  Future<void> close() async {
    await _networkSubscription.cancel();
    await _eventSubscription.cancel();
    return super.close();
  }
}
