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
  _SettingsRequest? _settingsRequest;
  int _settingsSequence = 0;
  bool get _alive => !isClosed && !_closing && (_owner == null || (_control?.ownsSession(_owner!) ?? true));
  bool _current(int generation) => _alive && generation == _actionGeneration;

  int _nextAction() {
    _settingsRequest = null;
    return ++_actionGeneration;
  }

  bool _settingsOwnerCurrent(_SettingsRequest request) => _current(request.generation) && identical(request.owner, _owner) && request.sequence == _settingsSequence;

  void _settingsOpeningFailed(_SettingsRequest request) {
    if (_settingsOwnerCurrent(request) && identical(request, _settingsRequest)) _settingsRequest = null;
  }

  Future<void> openPermissionSettings() async {
    if (!_alive || _settingsRequest != null) return;
    final opener = permissionSettingsOpener;
    if (opener == null) return;
    final request = _SettingsRequest(_SettingsKind.permission, _actionGeneration, _owner, ++_settingsSequence);
    _settingsRequest = request;
    try {
      final opened = await opener();
      if (!opened) _settingsOpeningFailed(request);
    } catch (_) {
      _settingsOpeningFailed(request);
    }
  }

  Future<void> openLocationSettings() async {
    if (!_alive || _settingsRequest != null || _control == null || _owner == null) return;
    final request = _SettingsRequest(_SettingsKind.location, _actionGeneration, _owner, ++_settingsSequence);
    _settingsRequest = request;
    try {
      await _control!.openLocationSettings(request.owner!);
    } catch (error) {
      if (_settingsOwnerCurrent(request) && identical(request, _settingsRequest)) {
        _settingsOpeningFailed(request);
        _rootFailure = null;
        _onFailure(error);
      }
    }
  }

  Future<void> onAppBackgrounded() async {
    if (!_alive) return;
    final request = _settingsRequest;
    if (request != null && _settingsOwnerCurrent(request)) request.leftApp = true;
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
    final generation = _actionGeneration;
    final owner = _owner;
    final request = _settingsRequest;
    if (_control != null && owner != null) await _control!.resumeDiscovery(owner);
    if (!_current(generation) || !identical(owner, _owner)) return;
    if (request == null || !identical(request, _settingsRequest) || !request.leftApp || !_settingsOwnerCurrent(request)) return;
    // Consume this exact return before awaiting the environment. Duplicate
    // lifecycle callbacks and old opener results must not consume a new request.
    _settingsRequest = null;
    if (request.kind == _SettingsKind.permission) {
      if (_control != null) {
        try {
          final environment = await _control!.readScanEnvironment();
          if (!_settingsOwnerCurrent(request)) return;
          if (environment.permission != BleScanPermissionState.granted) return;
        } catch (error) {
          if (_settingsOwnerCurrent(request) && _settingsRequest == null) _onFailure(error);
          return;
        }
      }
      if (_settingsOwnerCurrent(request) && _settingsRequest == null) await discover();
      return;
    }
    try {
      final environment = await _control!.readScanEnvironment();
      if (!_settingsOwnerCurrent(request) || _settingsRequest != null) return;
      await _control!.locationSettingsReturned(request.owner!, enabled: environment.locationService == BleLocationServiceState.enabled);
      if (!_settingsOwnerCurrent(request) || _settingsRequest != null) return;
      if (environment.locationService == BleLocationServiceState.enabled) {
        await discover();
      } else {
        _rootFailure = null;
        _onFailure(const ProvisioningException(code: ProvisioningErrorCode.locationServicesDisabled, retryable: true));
      }
    } catch (error) {
      if (_settingsOwnerCurrent(request) && _settingsRequest == null) {
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
    final generation = _nextAction();
    _rootFailure = null;
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
    final generation = _nextAction();
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
    if (!_alive || (state.phase != ProvisioningPhase.trusted && state.phase != ProvisioningPhase.methodSelection) || state.deviceInfo == null) return;
    final generation = _nextAction();
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
    final generation = _nextAction();
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
    final generation = _nextAction();
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
    final generation = _nextAction();
    _connectionActionActive = false;
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
    _nextAction();
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

enum _SettingsKind { permission, location }

final class _SettingsRequest {
  _SettingsRequest(this.kind, this.generation, this.owner, this.sequence);
  final _SettingsKind kind;
  final int generation;
  final Object? owner;
  final int sequence;
  bool leftApp = false;
}
