import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ProvisioningPhase {
  idle,
  discovering,
  discovered,
  connecting,
  trusted,
  pairingCode,
  authorizing,
  methodSelection,
  failure,
}

final class ProvisioningState {
  const ProvisioningState({
    this.phase = ProvisioningPhase.idle,
    this.devices = const [],
    this.selectedDevice,
    this.deviceInfo,
    this.pairingWindow,
    this.error,
  });

  final ProvisioningPhase phase;
  final List<ProvisioningDevice> devices;
  final ProvisioningDevice? selectedDevice;
  final ProvisioningDeviceInfo? deviceInfo;
  final PairingWindow? pairingWindow;
  final Object? error;

  ProvisioningState copyWith({
    ProvisioningPhase? phase,
    List<ProvisioningDevice>? devices,
    ProvisioningDevice? selectedDevice,
    ProvisioningDeviceInfo? deviceInfo,
    PairingWindow? pairingWindow,
    Object? error,
    bool clearSelection = false,
    bool clearDeviceInfo = false,
    bool clearPairingWindow = false,
    bool clearError = false,
  }) => ProvisioningState(
    phase: phase ?? this.phase,
    devices: devices ?? this.devices,
    selectedDevice: clearSelection ? null : selectedDevice ?? this.selectedDevice,
    deviceInfo: clearDeviceInfo ? null : deviceInfo ?? this.deviceInfo,
    pairingWindow: clearPairingWindow ? null : pairingWindow ?? this.pairingWindow,
    error: clearError ? null : error ?? this.error,
  );
}

/// Presentation-only BLE onboarding state.
///
/// Trusted setup deliberately begins after [ProvisioningRepository.connect]
/// returns Device Info. Advertisement names and scan IDs are shown only as
/// discovery hints and never become a device identity.
final class ProvisioningCubit extends Cubit<ProvisioningState> {
  ProvisioningCubit(this._repository) : super(const ProvisioningState());

  final ProvisioningRepository _repository;
  StreamSubscription<ProvisioningDevice>? _discoverySubscription;
  var _lastAction = _ProvisioningAction.discover;

  Future<void> discover() async {
    _lastAction = _ProvisioningAction.discover;
    await _discoverySubscription?.cancel();
    await _repository.stopDiscovery();
    if (isClosed) return;
    emit(const ProvisioningState(phase: ProvisioningPhase.discovering));

    _discoverySubscription = _repository.discoverDevices().listen(
      _onDiscoveredDevice,
      onError: _onFailure,
      onDone: () {
        if (!isClosed && state.phase == ProvisioningPhase.discovering) {
          emit(state.copyWith(phase: ProvisioningPhase.discovered));
        }
      },
    );
  }

  Future<void> selectDevice(ProvisioningDevice device) async {
    _lastAction = _ProvisioningAction.connect;
    await _discoverySubscription?.cancel();
    await _repository.stopDiscovery();
    if (isClosed) return;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.connecting,
        selectedDevice: device,
        clearDeviceInfo: true,
        clearPairingWindow: true,
        clearError: true,
      ),
    );
    try {
      final info = await _repository.connect(device);
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.trusted,
          deviceInfo: info,
          clearError: true,
        ),
      );
    } catch (error) {
      _onFailure(error);
    }
  }

  Future<void> openPairing() async {
    if (isClosed || state.phase != ProvisioningPhase.trusted || state.deviceInfo == null) return;
    _lastAction = _ProvisioningAction.openPairing;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.authorizing,
        clearPairingWindow: true,
        clearError: true,
      ),
    );
    try {
      final window = await _repository.openPairing();
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.pairingCode,
          pairingWindow: window,
          clearError: true,
        ),
      );
    } catch (error) {
      _onFailure(error);
    }
  }

  Future<void> authorizePairing(String pairingCode) async {
    if (isClosed || state.phase != ProvisioningPhase.pairingCode || pairingCode.trim().isEmpty) return;
    _lastAction = _ProvisioningAction.authorizePairing;
    emit(
      state.copyWith(phase: ProvisioningPhase.authorizing, clearError: true),
    );
    try {
      await _repository.authorizePairing(pairingCode.trim());
      if (isClosed) return;
      // The authorization value intentionally never enters presentation state.
      emit(
        state.copyWith(
          phase: ProvisioningPhase.methodSelection,
          clearError: true,
        ),
      );
    } catch (error) {
      _onFailure(error);
    }
  }

  void showMethodSelection() {
    if (isClosed || state.deviceInfo == null) return;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.methodSelection,
        clearError: true,
      ),
    );
  }

  Future<void> retry() => switch (_lastAction) {
    _ProvisioningAction.discover => discover(),
    _ProvisioningAction.connect when state.selectedDevice != null => selectDevice(state.selectedDevice!),
    _ProvisioningAction.openPairing => openPairing(),
    _ProvisioningAction.authorizePairing => openPairing(),
    _ => discover(),
  };

  Future<void> reset() async {
    await _discoverySubscription?.cancel();
    await _repository.stopDiscovery();
    await _repository.disconnect();
    if (!isClosed) emit(const ProvisioningState());
  }

  void _onDiscoveredDevice(ProvisioningDevice device) {
    if (isClosed) return;
    final devices = [...state.devices];
    final index = devices.indexWhere((item) => item.scanId == device.scanId);
    if (index >= 0) {
      devices[index] = device;
    } else {
      devices.add(device);
    }
    emit(
      state.copyWith(
        phase: ProvisioningPhase.discovered,
        devices: List.unmodifiable(devices),
        clearError: true,
      ),
    );
  }

  void _onFailure(Object error, [StackTrace? stackTrace]) {
    if (isClosed) return;
    emit(state.copyWith(phase: ProvisioningPhase.failure, error: error));
  }

  @override
  Future<void> close() async {
    await _discoverySubscription?.cancel();
    await _repository.stopDiscovery();
    await _repository.disconnect();
    return super.close();
  }
}

enum _ProvisioningAction { discover, connect, openPairing, authorizePairing }
