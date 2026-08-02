import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceManagementState {
  const DeviceManagementState({
    this.searching = false,
    this.available = const [],
    this.recent = const [],
    this.connectingDeviceId,
    this.error,
  });

  final bool searching;
  final List<DeviceConnection> available;
  final List<DeviceConnection> recent;
  final String? connectingDeviceId;
  final Object? error;

  DeviceManagementState copyWith({
    bool? searching,
    List<DeviceConnection>? available,
    List<DeviceConnection>? recent,
    String? connectingDeviceId,
    bool clearConnecting = false,
    Object? error,
    bool clearError = false,
  }) => DeviceManagementState(
    searching: searching ?? this.searching,
    available: available ?? this.available,
    recent: recent ?? this.recent,
    connectingDeviceId: clearConnecting ? null : connectingDeviceId ?? this.connectingDeviceId,
    error: clearError ? null : error ?? this.error,
  );
}

class DeviceManagementCubit extends Cubit<DeviceManagementState> {
  DeviceManagementCubit(
    this._repository,
    this._session, {
    this.searchTimeout = const Duration(seconds: 8),
  }) : super(const DeviceManagementState());

  final ConnectionRepository _repository;
  final DeviceSessionCubit _session;
  final Duration searchTimeout;
  CancelToken? _connectToken;
  int _searchGeneration = 0;

  Future<void> initialize() async {
    try {
      final recent = await _repository.recentDevices();
      if (!isClosed) emit(state.copyWith(recent: recent));
    } catch (_) {
      // Discovery remains available when the local history cannot be read.
    }
    await search();
  }

  Future<void> search() async {
    final generation = ++_searchGeneration;
    emit(state.copyWith(searching: true, clearError: true));
    try {
      final devices = await _repository.discover().timeout(searchTimeout);
      if (!isClosed && generation == _searchGeneration) {
        emit(state.copyWith(available: devices));
      }
    } on TimeoutException catch (error) {
      if (!isClosed && generation == _searchGeneration) {
        emit(state.copyWith(error: error));
      }
    } catch (error) {
      if (!isClosed && generation == _searchGeneration) {
        emit(state.copyWith(error: error));
      }
    } finally {
      if (!isClosed && generation == _searchGeneration) {
        emit(state.copyWith(searching: false));
      }
    }
  }

  void cancelSearch() {
    _searchGeneration++;
    if (!isClosed) emit(state.copyWith(searching: false));
  }

  Future<bool> connect(DeviceConnection device) async {
    if (state.connectingDeviceId != null) return false;
    _connectToken?.cancel();
    final token = CancelToken();
    _connectToken = token;
    emit(
      state.copyWith(
        connectingDeviceId: device.id,
        clearError: true,
      ),
    );
    try {
      final status = await _repository.connect(
        device.baseUri,
        networkMode: device.networkMode,
        cancelToken: token,
      );
      await _session.setConnectedFromStatus(status);
      return true;
    } catch (error) {
      if (!isClosed) emit(state.copyWith(error: error));
      return false;
    } finally {
      if (!isClosed) emit(state.copyWith(clearConnecting: true));
      if (identical(_connectToken, token)) _connectToken = null;
    }
  }

  @override
  Future<void> close() async {
    _searchGeneration++;
    _connectToken?.cancel();
    return super.close();
  }
}
