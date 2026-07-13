import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ConnectionPhase { initial, loading, connecting, connected, failure }

class DeviceConnectionState extends Equatable {
  const DeviceConnectionState({
    this.phase = ConnectionPhase.initial,
    this.discoveredDevices = const [],
    this.recentDevices = const [],
    this.status,
    this.error,
  });

  final ConnectionPhase phase;
  final List<DeviceConnection> discoveredDevices;
  final List<DeviceConnection> recentDevices;
  final DeviceStatus? status;
  final Object? error;

  DeviceConnectionState copyWith({
    ConnectionPhase? phase,
    List<DeviceConnection>? discoveredDevices,
    List<DeviceConnection>? recentDevices,
    DeviceStatus? status,
    Object? error,
    bool clearError = false,
  }) {
    return DeviceConnectionState(
      phase: phase ?? this.phase,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      recentDevices: recentDevices ?? this.recentDevices,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [phase, discoveredDevices, recentDevices, status, error];
}

class ConnectionCubit extends Cubit<DeviceConnectionState> {
  ConnectionCubit(this._repository, this._sessionCubit) : super(const DeviceConnectionState());

  final ConnectionRepository _repository;
  final DeviceSessionCubit _sessionCubit;

  Future<void> load() async {
    emit(state.copyWith(phase: ConnectionPhase.loading, clearError: true));
    try {
      final recent = await _repository.recentDevices();
      emit(state.copyWith(phase: ConnectionPhase.initial, recentDevices: recent));
    } catch (error) {
      emit(state.copyWith(phase: ConnectionPhase.failure, error: error));
    }
  }

  Future<void> discover() async {
    emit(state.copyWith(phase: ConnectionPhase.loading, clearError: true));
    try {
      final devices = await _repository.discover();
      emit(state.copyWith(phase: ConnectionPhase.initial, discoveredDevices: devices));
    } catch (error) {
      emit(state.copyWith(phase: ConnectionPhase.failure, error: error));
    }
  }

  Future<void> connect(Uri uri, NetworkMode mode) async {
    emit(state.copyWith(phase: ConnectionPhase.connecting, clearError: true));
    _sessionCubit.connecting();
    try {
      final status = await _repository.connect(uri, networkMode: mode);
      await _sessionCubit.setConnectedFromStatus(status);
      emit(state.copyWith(phase: ConnectionPhase.connected, status: status));
    } catch (error) {
      _sessionCubit.disconnected('连接盒子失败。');
      emit(state.copyWith(phase: ConnectionPhase.failure, error: error));
    }
  }
}
