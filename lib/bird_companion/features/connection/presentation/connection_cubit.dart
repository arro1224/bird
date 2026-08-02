import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ConnectionPhase { initial, loading, connecting, pairing, connected, failure }

enum _ConnectionRequest { load, discover, connect }

class DeviceConnectionState extends Equatable {
  const DeviceConnectionState({
    this.phase = ConnectionPhase.initial,
    this.discoveredDevices = const [],
    this.recentDevices = const [],
    this.status,
    this.error,
    this.connectionAttemptFailed = false,
  });

  final ConnectionPhase phase;
  final List<DeviceConnection> discoveredDevices;
  final List<DeviceConnection> recentDevices;
  final DeviceStatus? status;
  final Object? error;
  final bool connectionAttemptFailed;

  DeviceConnectionState copyWith({
    ConnectionPhase? phase,
    List<DeviceConnection>? discoveredDevices,
    List<DeviceConnection>? recentDevices,
    DeviceStatus? status,
    Object? error,
    bool? connectionAttemptFailed,
    bool clearError = false,
  }) {
    return DeviceConnectionState(
      phase: phase ?? this.phase,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      recentDevices: recentDevices ?? this.recentDevices,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      connectionAttemptFailed: connectionAttemptFailed ?? this.connectionAttemptFailed,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    discoveredDevices,
    recentDevices,
    status,
    error,
    connectionAttemptFailed,
  ];
}

class ConnectionCubit extends Cubit<DeviceConnectionState> {
  ConnectionCubit(
    this._repository,
    this._sessionCubit, {
    this.preserveExistingSession = false,
  }) : super(const DeviceConnectionState());

  final ConnectionRepository _repository;
  final DeviceSessionCubit _sessionCubit;
  final bool preserveExistingSession;
  _ConnectionRequest _lastRequest = _ConnectionRequest.load;
  Uri? _lastUri;
  NetworkMode? _lastMode;
  var _connectionGeneration = 0;
  CancelToken? _activeCancelToken;

  Future<void> load() async {
    if (isClosed) return;
    _lastRequest = _ConnectionRequest.load;
    emit(
      state.copyWith(
        phase: ConnectionPhase.loading,
        discoveredDevices: const [],
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
    try {
      final recent = await _repository.recentDevices();
      if (isClosed) return;
      emit(state.copyWith(recentDevices: recent));
      _lastRequest = _ConnectionRequest.discover;
      final devices = await _repository.discover();
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ConnectionPhase.initial,
          discoveredDevices: _withoutRecent(devices, recent),
          recentDevices: recent,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ConnectionPhase.failure,
          error: error,
          connectionAttemptFailed: false,
        ),
      );
    }
  }

  Future<void> discover() async {
    if (isClosed) return;
    _lastRequest = _ConnectionRequest.discover;
    emit(
      state.copyWith(
        phase: ConnectionPhase.loading,
        discoveredDevices: const [],
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
    try {
      final devices = await _repository.discover();
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ConnectionPhase.initial,
          discoveredDevices: _withoutRecent(devices, state.recentDevices),
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ConnectionPhase.failure,
          error: error,
          connectionAttemptFailed: false,
        ),
      );
    }
  }

  Future<void> connect(Uri uri, NetworkMode mode) async {
    if (isClosed) return;
    _activeCancelToken?.cancel('Replaced by a newer connection request.');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final generation = ++_connectionGeneration;
    _lastRequest = _ConnectionRequest.connect;
    _lastUri = uri;
    _lastMode = mode;
    emit(
      state.copyWith(
        phase: ConnectionPhase.connecting,
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
    if (!preserveExistingSession) _sessionCubit.connecting();
    try {
      final status = await _repository.connect(
        uri,
        networkMode: mode,
        cancelToken: cancelToken,
      );
      if (isClosed || generation != _connectionGeneration) return;
      await _completeConnection(status, generation);
    } on PairingRequiredException catch (error) {
      if (isClosed || generation != _connectionGeneration) return;
      if (!preserveExistingSession) _sessionCubit.disconnected();
      emit(
        state.copyWith(
          phase: ConnectionPhase.pairing,
          status: error.status,
          connectionAttemptFailed: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _connectionGeneration) return;
      if (!preserveExistingSession) {
        _sessionCubit.disconnected('连接盒子失败。');
      }
      emit(
        state.copyWith(
          phase: ConnectionPhase.failure,
          error: error,
          connectionAttemptFailed: true,
        ),
      );
    } finally {
      if (identical(_activeCancelToken, cancelToken)) _activeCancelToken = null;
    }
  }

  Future<void> pair(String pairingCode) async {
    final uri = _lastUri;
    final mode = _lastMode;
    if (isClosed || uri == null || mode == null) return;
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final generation = ++_connectionGeneration;
    emit(
      state.copyWith(
        phase: ConnectionPhase.connecting,
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
    if (!preserveExistingSession) _sessionCubit.connecting();
    try {
      final status = await _repository.pair(
        uri,
        networkMode: mode,
        pairingCode: pairingCode,
        cancelToken: cancelToken,
      );
      if (isClosed || generation != _connectionGeneration) return;
      await _completeConnection(status, generation);
    } catch (error) {
      if (isClosed || generation != _connectionGeneration) return;
      if (!preserveExistingSession) {
        _sessionCubit.disconnected('配对失败。');
      }
      emit(
        state.copyWith(
          phase: ConnectionPhase.failure,
          error: error,
          connectionAttemptFailed: true,
        ),
      );
    } finally {
      if (identical(_activeCancelToken, cancelToken)) _activeCancelToken = null;
    }
  }

  Future<void> _completeConnection(
    DeviceStatus status,
    int generation,
  ) async {
    await _sessionCubit.setConnectedFromStatus(status);
    if (isClosed || generation != _connectionGeneration) return;
    emit(
      state.copyWith(
        phase: ConnectionPhase.connected,
        status: status,
        connectionAttemptFailed: false,
      ),
    );
  }

  void cancelConnection() {
    if (isClosed || state.phase != ConnectionPhase.connecting) return;
    _connectionGeneration++;
    _activeCancelToken?.cancel('Connection cancelled by the user.');
    _activeCancelToken = null;
    if (!preserveExistingSession) _sessionCubit.disconnected();
    emit(
      state.copyWith(
        phase: ConnectionPhase.initial,
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
  }

  void resetAfterFailure() {
    if (isClosed || state.phase != ConnectionPhase.failure) return;
    emit(
      state.copyWith(
        phase: ConnectionPhase.initial,
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
  }

  void resetPairing() {
    if (isClosed || state.phase != ConnectionPhase.pairing) return;
    if (!preserveExistingSession) _sessionCubit.disconnected();
    emit(
      state.copyWith(
        phase: ConnectionPhase.initial,
        connectionAttemptFailed: false,
        clearError: true,
      ),
    );
  }

  Future<void> retry() => switch (_lastRequest) {
    _ConnectionRequest.load => load(),
    _ConnectionRequest.discover => discover(),
    _ConnectionRequest.connect when _lastUri != null && _lastMode != null => connect(_lastUri!, _lastMode!),
    _ => load(),
  };

  List<DeviceConnection> _withoutRecent(List<DeviceConnection> devices, List<DeviceConnection> recent) {
    final recentIds = recent.map(_deviceKey).toSet();
    return devices.where((device) => !recentIds.contains(_deviceKey(device))).toList();
  }

  String _deviceKey(DeviceConnection device) => device.id.isEmpty ? device.baseUri.toString() : device.id;

  @override
  Future<void> close() {
    if (state.phase == ConnectionPhase.connecting) {
      _connectionGeneration++;
      _activeCancelToken?.cancel('Connection screen was closed.');
      _activeCancelToken = null;
      if (!preserveExistingSession) _sessionCubit.disconnected();
    }
    return super.close();
  }
}
