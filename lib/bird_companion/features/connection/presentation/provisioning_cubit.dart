import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';

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
    this.latestScanDiagnostic,
    this.error,
    this.pairingProgress,
  });

  final ProvisioningPhase phase;
  final List<ProvisioningDevice> devices;
  final ProvisioningDevice? selectedDevice;
  final ProvisioningDeviceInfo? deviceInfo;
  final PairingWindow? pairingWindow;
  final BleScanDiagnosticSession? latestScanDiagnostic;
  final Object? error;
  final BlePairingProgress? pairingProgress;

  ProvisioningState copyWith({
    ProvisioningPhase? phase,
    List<ProvisioningDevice>? devices,
    ProvisioningDevice? selectedDevice,
    ProvisioningDeviceInfo? deviceInfo,
    PairingWindow? pairingWindow,
    BleScanDiagnosticSession? latestScanDiagnostic,
    Object? error,
    BlePairingProgress? pairingProgress,
    bool clearSelection = false,
    bool clearDeviceInfo = false,
    bool clearPairingWindow = false,
    bool clearScanDiagnostic = false,
    bool clearError = false,
    bool clearPairingProgress = false,
  }) => ProvisioningState(
    phase: phase ?? this.phase,
    devices: devices ?? this.devices,
    selectedDevice: clearSelection ? null : selectedDevice ?? this.selectedDevice,
    deviceInfo: clearDeviceInfo ? null : deviceInfo ?? this.deviceInfo,
    pairingWindow: clearPairingWindow ? null : pairingWindow ?? this.pairingWindow,
    latestScanDiagnostic: clearScanDiagnostic ? null : latestScanDiagnostic ?? this.latestScanDiagnostic,
    error: clearError ? null : error ?? this.error,
    pairingProgress: clearPairingProgress ? null : pairingProgress ?? this.pairingProgress,
  );
}

/// Presentation-only BLE onboarding state.
///
/// Trusted setup deliberately begins after [ProvisioningRepository.connect]
/// returns Device Info. Advertisement names and scan IDs are shown only as
/// discovery hints and never become a device identity.
final class ProvisioningCubit extends Cubit<ProvisioningState> {
  ProvisioningCubit(this._repository, {this.permissionSettingsOpener}) : super(const ProvisioningState()) {
    final repository = _repository;
    if (repository is BleProvisioningControl) {
      _control = repository as BleProvisioningControl;
      _owner = _control!.claimSession();
      _pairingSubscription = _control!.pairingProgress.listen((progress) {
        if (_alive && state.phase == ProvisioningPhase.authorizing) emit(state.copyWith(pairingProgress: progress));
      });
    }
    if (repository is BleScanDiagnosticsRepository) {
      _scanDiagnosticSubscription = (repository as BleScanDiagnosticsRepository).scanDiagnostics.listen(_onScanDiagnostic);
    }
  }

  final ProvisioningRepository _repository;
  final Future<bool> Function()? permissionSettingsOpener;
  StreamSubscription<ProvisioningDevice>? _discoverySubscription;
  StreamSubscription<BleScanDiagnosticSession>? _scanDiagnosticSubscription;
  var _lastAction = _ProvisioningAction.discover;
  Object? _rootFailure;
  bool _connectionActionActive = false;
  BleProvisioningControl? _control;
  Object? _owner;
  StreamSubscription<BlePairingProgress>? _pairingSubscription;
  int _actionGeneration = 0;
  bool _closing = false;
  bool retainSession = false;
  bool _awaitingLocationSettings = false;
  bool _leftForLocationSettings = false;
  bool _awaitingPermissionSettings = false;
  bool _leftForPermissionSettings = false;
  bool get _alive => !isClosed && !_closing && (_owner == null || (_control?.ownsSession(_owner!) ?? true));
  bool _current(int generation) => _alive && generation == _actionGeneration;

  Future<void> openPermissionSettings() async {
    if (!_alive || _awaitingPermissionSettings) return;
    final opener = permissionSettingsOpener;
    if (opener == null) return;
    _awaitingPermissionSettings = true;
    _leftForPermissionSettings = false;
    final generation = _actionGeneration;
    try {
      final opened = await opener();
      if (_current(generation) && !opened) _awaitingPermissionSettings = false;
    } catch (_) {
      if (_current(generation)) _awaitingPermissionSettings = false;
    }
  }

  Future<void> openLocationSettings() async {
    if (!_alive || _awaitingLocationSettings || _control == null || _owner == null) return;
    _awaitingLocationSettings = true;
    _leftForLocationSettings = false;
    final generation = _actionGeneration;
    try {
      await _control!.openLocationSettings(_owner!);
    } catch (error) {
      _awaitingLocationSettings = false;
      if (_current(generation)) {
        _rootFailure = null;
        _onFailure(error);
      }
    }
  }

  Future<void> onAppBackgrounded() async {
    if (!_alive) return;
    if (_awaitingLocationSettings) _leftForLocationSettings = true;
    if (_awaitingPermissionSettings) _leftForPermissionSettings = true;
    // A system bond dialog may pause the Activity. Preserve its active attempt.
    if (state.phase == ProvisioningPhase.authorizing || state.phase == ProvisioningPhase.connecting) return;
    if (_control != null && _owner != null) {
      await _control!.pauseDiscovery(_owner!);
    } else {
      await _repository.stopDiscovery();
    }
  }

  Future<void> onAppResumed() async {
    if (!_alive) return;
    if (_control != null && _owner != null) await _control!.resumeDiscovery(_owner!);
    if (_alive && _awaitingPermissionSettings && _leftForPermissionSettings) {
      _awaitingPermissionSettings = false;
      _leftForPermissionSettings = false;
      final generation = _actionGeneration;
      if (_control != null) {
        try {
          final environment = await _control!.readScanEnvironment();
          if (!_current(generation)) return;
          if (environment.permission != BleScanPermissionState.granted) return;
        } catch (error) {
          if (_current(generation)) _onFailure(error);
          return;
        }
      }
      if (_current(generation)) await discover();
      return;
    }
    if (!_alive || !_awaitingLocationSettings || !_leftForLocationSettings) return;
    _awaitingLocationSettings = false;
    _leftForLocationSettings = false;
    final generation = _actionGeneration;
    try {
      final environment = await _control!.readScanEnvironment();
      if (!_current(generation)) return;
      await _control!.locationSettingsReturned(_owner!, enabled: environment.locationService == BleLocationServiceState.enabled);
      if (!_current(generation)) return;
      if (environment.locationService == BleLocationServiceState.enabled) {
        await discover();
      } else {
        _rootFailure = null;
        _onFailure(const ProvisioningException(code: ProvisioningErrorCode.locationServicesDisabled, retryable: true));
      }
    } catch (error) {
      if (_current(generation)) {
        _rootFailure = null;
        _onFailure(error);
      }
    }
  }

  Future<void> _disconnectOwned() async {
    final owner = _owner;
    if (_control != null && owner != null) {
      if (!_control!.ownsSession(owner)) return;
      await _control!.endSession(owner);
      if (!_closing && !isClosed && identical(_owner, owner) && _control!.ownsSession(owner)) _owner = _control!.claimSession();
    } else {
      await _repository.disconnect();
    }
  }

  Future<void> discover() async {
    if (!_alive || _connectionActionActive || state.phase == ProvisioningPhase.authorizing) return;
    final generation = ++_actionGeneration;
    _awaitingLocationSettings = false;
    _rootFailure = null;
    _awaitingPermissionSettings = false;
    _lastAction = _ProvisioningAction.discover;
    await _discoverySubscription?.cancel();
    await _repository.stopDiscovery();
    if (!_current(generation)) return;
    emit(const ProvisioningState(phase: ProvisioningPhase.discovering));

    _discoverySubscription = _repository.discoverDevices().listen(
      (device) {
        if (_current(generation)) _onDiscoveredDevice(device);
      },
      onError: (Object error, StackTrace stack) {
        if (_current(generation)) _onFailure(error, stack);
      },
      onDone: () {
        if (_current(generation) && state.phase == ProvisioningPhase.discovering) {
          emit(state.copyWith(phase: ProvisioningPhase.discovered));
        }
      },
    );
  }

  Future<void> selectDevice(ProvisioningDevice device) async {
    if (!_alive || _connectionActionActive) return;
    _connectionActionActive = true;
    final generation = ++_actionGeneration;
    _rootFailure = null;
    _lastAction = _ProvisioningAction.connect;
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
      await _discoverySubscription?.cancel();
      await _repository.stopDiscovery();
      if (!_current(generation)) return;
      final info = await _repository.connect(device);
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.trusted,
          deviceInfo: info,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_current(generation)) _onFailure(error);
    } finally {
      if (generation == _actionGeneration) _connectionActionActive = false;
    }
  }

  Future<void> openPairing() async {
    if (!_alive || state.phase != ProvisioningPhase.trusted || state.deviceInfo == null) return;
    final generation = ++_actionGeneration;
    _lastAction = _ProvisioningAction.openPairing;
    _rootFailure = null;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.authorizing,
        clearPairingProgress: true,
        clearPairingWindow: true,
        clearError: true,
      ),
    );
    try {
      final window = await _repository.openPairing();
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.pairingCode,
          pairingWindow: window,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_current(generation)) _onFailure(error);
    }
  }

  Future<void> authorizePairing(String pairingCode) async {
    if (!_alive || state.phase != ProvisioningPhase.pairingCode || pairingCode.trim().isEmpty) return;
    final generation = ++_actionGeneration;
    _lastAction = _ProvisioningAction.authorizePairing;
    _rootFailure = null;
    emit(
      state.copyWith(phase: ProvisioningPhase.authorizing, clearError: true, clearPairingProgress: true),
    );
    try {
      await _repository.authorizePairing(pairingCode.trim());
      if (!_current(generation)) return;
      // The authorization value intentionally never enters presentation state.
      emit(
        state.copyWith(
          phase: ProvisioningPhase.methodSelection,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_current(generation)) _onFailure(error);
    }
  }

  void showMethodSelection() {
    if (!_alive || state.deviceInfo == null || state.phase != ProvisioningPhase.methodSelection) return;
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
    _ProvisioningAction.openPairing || _ProvisioningAction.authorizePairing => _reconnectAndOpenPairing(),
    _ => discover(),
  };

  Future<void> _reconnectAndOpenPairing() async {
    if (!_alive || _connectionActionActive) return;
    final device = state.selectedDevice;
    if (device == null) {
      await discover();
      return;
    }
    _connectionActionActive = true;
    final generation = ++_actionGeneration;
    _rootFailure = null;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.connecting,
        clearDeviceInfo: true,
        clearPairingWindow: true,
        clearError: true,
      ),
    );
    try {
      // A failed/timeout Bond may leave both Android and the vendor GATT stack
      // in an uncertain state. A user retry always tears down that session and
      // re-verifies Device Info before opening a fresh pairing window.
      await _disconnectOwned();
      if (!_current(generation)) return;
      final info = await _repository.connect(device);
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.trusted,
          deviceInfo: info,
          clearError: true,
        ),
      );
      _connectionActionActive = false;
      await openPairing();
    } catch (error) {
      if (_current(generation)) _onFailure(error);
    } finally {
      if (generation == _actionGeneration) _connectionActionActive = false;
    }
  }

  Future<void> reset() async {
    if (!_alive) return;
    final generation = ++_actionGeneration;
    _connectionActionActive = false;
    _awaitingLocationSettings = false;
    final cleanup = _disconnectOwned();
    await _discoverySubscription?.cancel();
    await cleanup;
    if (_current(generation)) emit(const ProvisioningState());
  }

  void _onDiscoveredDevice(ProvisioningDevice device) {
    if (!_alive) return;
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
    if (!_alive) return;
    // Keep the first actionable root cause. A later disconnect/cancellation
    // callback must not replace a GATT security or Bond failure with a generic
    // "operation failed" message.
    if (_rootFailure != null) return;
    _rootFailure = error;
    emit(state.copyWith(phase: ProvisioningPhase.failure, error: _rootFailure));
  }

  void _onScanDiagnostic(BleScanDiagnosticSession diagnostic) {
    if (!_alive) return;
    emit(state.copyWith(latestScanDiagnostic: diagnostic));
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _awaitingPermissionSettings = false;
    ++_actionGeneration;
    _awaitingLocationSettings = false;
    final cleanup = _control != null && _owner != null && !retainSession
        ? _control!.endSession(_owner!).catchError((Object error) {
            debugPrint('BLE owned page cleanup failed: ${error.runtimeType}');
          })
        : null;
    await _discoverySubscription?.cancel();
    await _scanDiagnosticSubscription?.cancel();
    await _pairingSubscription?.cancel();
    if (_control != null && _owner != null) {
      await cleanup;
    } else {
      await _repository.stopDiscovery();
    }
    return super.close();
  }
}

enum _ProvisioningAction { discover, connect, openPairing, authorizePairing }
