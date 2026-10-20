import 'package:aves/bird_companion/features/connection/domain/ble_attempt_failure.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
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
  disconnecting,
  failure,
}

/// Last transport state observed by Dart; native resynchronization is separate.
enum BleLinkStatus { disconnected, connecting, connected, disconnecting, releaseFailed }

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
    this.linkStatus = BleLinkStatus.disconnected,
  });

  final ProvisioningPhase phase;
  final List<ProvisioningDevice> devices;
  final ProvisioningDevice? selectedDevice;
  final ProvisioningDeviceInfo? deviceInfo;
  final PairingWindow? pairingWindow;
  final BleScanDiagnosticSession? latestScanDiagnostic;
  final Object? error;
  final BlePairingProgress? pairingProgress;
  final BleLinkStatus linkStatus;
  bool get releaseBlocked => linkStatus == BleLinkStatus.disconnecting || linkStatus == BleLinkStatus.releaseFailed;

  ProvisioningState copyWith({
    ProvisioningPhase? phase,
    List<ProvisioningDevice>? devices,
    ProvisioningDevice? selectedDevice,
    ProvisioningDeviceInfo? deviceInfo,
    PairingWindow? pairingWindow,
    BleScanDiagnosticSession? latestScanDiagnostic,
    Object? error,
    BlePairingProgress? pairingProgress,
    BleLinkStatus? linkStatus,
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
    linkStatus: linkStatus ?? this.linkStatus,
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
        if (_alive && (state.phase == ProvisioningPhase.authorizing || state.phase == ProvisioningPhase.connecting)) emit(state.copyWith(pairingProgress: progress));
      });
    }
    if (repository is BleScanDiagnosticsRepository) {
      _scanDiagnosticSubscription = (repository as BleScanDiagnosticsRepository).scanDiagnostics.listen(_onScanDiagnostic);
    }
    if (repository is ProvisioningSessionRepository) {
      _disconnectSubscription = (repository as ProvisioningSessionRepository).disconnects.listen((_) {
        if (!_alive || state.releaseBlocked || state.linkStatus != BleLinkStatus.connected) return;
        if (state.phase == ProvisioningPhase.authorizing) {
          // Let the command Future deliver its saved first error.
          emit(state.copyWith(linkStatus: BleLinkStatus.disconnected));
          return;
        }
        emit(state.copyWith(phase: ProvisioningPhase.failure, linkStatus: BleLinkStatus.disconnected, clearDeviceInfo: true, clearPairingWindow: true, clearPairingProgress: true));
        _onFailure(const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true));
      });
    }
  }

  final ProvisioningRepository _repository;
  final Future<bool> Function()? permissionSettingsOpener;
  StreamSubscription<ProvisioningDevice>? _discoverySubscription;
  StreamSubscription<BleScanDiagnosticSession>? _scanDiagnosticSubscription;
  var _lastAction = _ProvisioningAction.discover;
  BleAttemptFailure? _failures;
  bool _connectionActionActive = false;
  BleProvisioningControl? _control;
  Object? _owner;
  StreamSubscription<BlePairingProgress>? _pairingSubscription;
  StreamSubscription<void>? _disconnectSubscription;
  Future<void>? _resetFuture;
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
    if (!_alive || state.releaseBlocked || _settingsRequest != null) return;
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
    if (!_alive || state.releaseBlocked || _settingsRequest != null || _control == null || _owner == null) return;
    final request = _SettingsRequest(_SettingsKind.location, _actionGeneration, _owner, ++_settingsSequence);
    _settingsRequest = request;
    try {
      await _control!.openLocationSettings(request.owner!);
    } catch (error, stack) {
      if (_settingsOwnerCurrent(request) && identical(request, _settingsRequest)) {
        _settingsOpeningFailed(request);
        _failures = null;
        _onFailure(error, stack);
      }
    }
  }

  Future<void> onAppBackgrounded() async {
    if (!_alive || state.releaseBlocked) return;
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
    if (!_alive || state.releaseBlocked) return;
    final generation = _actionGeneration;
    final owner = _owner;
    final request = _settingsRequest;
    try {
      if (_control != null && owner != null) await _control!.resumeDiscovery(owner);
    } catch (error, stack) {
      if (_current(generation) && identical(owner, _owner)) _onFailure(error, stack);
      return;
    }
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
        } catch (error, stack) {
          if (_settingsOwnerCurrent(request) && _settingsRequest == null) _onFailure(error, stack);
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
        _failures = null;
        _onFailure(const ProvisioningException(code: ProvisioningErrorCode.locationServicesDisabled, retryable: true));
      }
    } catch (error, stack) {
      if (_settingsOwnerCurrent(request) && _settingsRequest == null) {
        _failures = null;
        _onFailure(error, stack);
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
    if (!_alive || state.releaseBlocked || state.linkStatus == BleLinkStatus.connected || _connectionActionActive || state.phase == ProvisioningPhase.authorizing) return;
    final generation = _nextAction();
    _failures = null;
    _lastAction = _ProvisioningAction.discover;
    try {
      await _discoverySubscription?.cancel();
      if (_repository is BleSessionReleaseGuard) {
        final guard = _repository as BleSessionReleaseGuard;
        if (guard.sessionReleasePending || guard.sessionReleaseFailed) {
          emit(state.copyWith(phase: ProvisioningPhase.disconnecting, linkStatus: BleLinkStatus.disconnecting));
          await guard.waitForSessionRelease();
          if (!_current(generation)) return;
        }
      }
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
    } catch (error, stack) {
      if (_current(generation)) _onFailure(error, stack);
    }
  }

  Future<void> selectDevice(ProvisioningDevice device) async {
    if (!_alive || state.releaseBlocked || state.phase == ProvisioningPhase.authorizing || _connectionActionActive) return;
    if (state.linkStatus == BleLinkStatus.connected) {
      await reset();
      if (!_alive || state.releaseBlocked || state.phase != ProvisioningPhase.idle) return;
    }
    _connectionActionActive = true;
    final generation = _nextAction();
    _failures = null;
    _lastAction = _ProvisioningAction.connect;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.connecting,
        linkStatus: BleLinkStatus.connecting,
        clearPairingProgress: true,
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
      if (_repository is BleSessionReleaseGuard) {
        final guard = _repository as BleSessionReleaseGuard;
        if (guard.sessionReleasePending || guard.sessionReleaseFailed) {
          emit(state.copyWith(phase: ProvisioningPhase.disconnecting, linkStatus: BleLinkStatus.disconnecting));
          await guard.waitForSessionRelease();
          if (!_current(generation)) return;
          emit(state.copyWith(phase: ProvisioningPhase.connecting, linkStatus: BleLinkStatus.connecting));
        }
      }
      final info = await _repository.connect(device);
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.trusted,
          linkStatus: BleLinkStatus.connected,
          deviceInfo: info,
          clearError: true,
        ),
      );
    } catch (error, stack) {
      if (_current(generation)) _onFailure(error, stack);
    } finally {
      if (generation == _actionGeneration) _connectionActionActive = false;
    }
  }

  Future<void> openPairing() async {
    if (!_alive || state.releaseBlocked || state.linkStatus != BleLinkStatus.connected || (state.phase != ProvisioningPhase.trusted && state.phase != ProvisioningPhase.methodSelection) || state.deviceInfo == null) return;
    final generation = _nextAction();
    _lastAction = _ProvisioningAction.openPairing;
    _failures = null;
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
      if (state.linkStatus != BleLinkStatus.connected) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
      emit(
        state.copyWith(
          phase: ProvisioningPhase.pairingCode,
          pairingWindow: window,
          clearError: true,
        ),
      );
    } catch (error, stack) {
      if (_current(generation)) _onFailure(error, stack);
    }
  }

  Future<void> authorizePairing(String pairingCode) async {
    if (!_alive || state.releaseBlocked || state.phase != ProvisioningPhase.pairingCode || pairingCode.trim().isEmpty) return;
    final generation = _nextAction();
    _lastAction = _ProvisioningAction.authorizePairing;
    _failures = null;
    emit(
      state.copyWith(phase: ProvisioningPhase.authorizing, clearError: true, clearPairingProgress: true),
    );
    try {
      await _repository.authorizePairing(pairingCode.trim());
      if (!_current(generation)) return;
      if (state.linkStatus != BleLinkStatus.connected) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
      // The authorization value intentionally never enters presentation state.
      emit(
        state.copyWith(
          phase: ProvisioningPhase.methodSelection,
          clearError: true,
        ),
      );
    } catch (error, stack) {
      if (_current(generation)) _onFailure(error, stack);
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
    _ProvisioningAction.disconnect => returnToDiscovery(),
    _ProvisioningAction.discover => discover(),
    _ProvisioningAction.connect when state.selectedDevice != null => selectDevice(state.selectedDevice!),
    _ProvisioningAction.openPairing || _ProvisioningAction.authorizePairing => _reconnectAndOpenPairing(),
    _ => discover(),
  };

  Future<void> _reconnectAndOpenPairing() async {
    if (!_alive || state.releaseBlocked || _connectionActionActive) return;
    final device = state.selectedDevice;
    if (device == null) {
      await discover();
      return;
    }
    _connectionActionActive = true;
    final generation = _nextAction();
    _failures = null;
    emit(
      state.copyWith(
        phase: ProvisioningPhase.disconnecting,
        linkStatus: BleLinkStatus.disconnecting,
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
      emit(state.copyWith(phase: ProvisioningPhase.connecting, linkStatus: BleLinkStatus.connecting));
      final info = await _repository.connect(device);
      if (!_current(generation)) return;
      emit(
        state.copyWith(
          phase: ProvisioningPhase.trusted,
          linkStatus: BleLinkStatus.connected,
          deviceInfo: info,
          clearError: true,
        ),
      );
      _connectionActionActive = false;
      await openPairing();
    } catch (error, stack) {
      if (_current(generation)) _onFailure(error, stack);
    } finally {
      if (generation == _actionGeneration) _connectionActionActive = false;
    }
  }

  Future<void> reset() => _resetSession(rescan: false);

  Future<void> returnToDiscovery() => _resetSession(rescan: true);

  Future<void> _resetSession({required bool rescan}) {
    final pending = _resetFuture;
    if (pending != null) return pending;
    if (!_alive) return Future.value();
    final completion = Completer<void>();
    _resetFuture = completion.future;
    unawaited(
      _performReset(rescan: rescan).then(completion.complete, onError: completion.completeError).whenComplete(() {
        if (identical(_resetFuture, completion.future)) _resetFuture = null;
      }),
    );
    return completion.future;
  }

  Future<void> _performReset({required bool rescan}) async {
    final generation = _nextAction();
    _lastAction = _ProvisioningAction.disconnect;
    _connectionActionActive = false;
    emit(state.copyWith(phase: ProvisioningPhase.disconnecting, linkStatus: BleLinkStatus.disconnecting));
    try {
      await _discoverySubscription?.cancel();
      await _disconnectOwned();
      if (_current(generation)) {
        _failures = null;
        emit(const ProvisioningState());
        if (rescan) await discover();
      }
    } catch (error, stack) {
      if (_current(generation)) {
        emit(state.copyWith(linkStatus: BleLinkStatus.releaseFailed));
        _onFailure(error, stack);
      }
    }
  }

  void _onDiscoveredDevice(ProvisioningDevice device) {
    if (!_alive || _failures != null) return;
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
    final releaseFailed = state.linkStatus == BleLinkStatus.releaseFailed || state.linkStatus == BleLinkStatus.disconnecting || (_repository is BleSessionReleaseGuard && (_repository as BleSessionReleaseGuard).sessionReleaseFailed);
    if (releaseFailed) _lastAction = _ProvisioningAction.disconnect;
    final failure = _failures ??= BleAttemptFailure(attemptId: 'page-$_actionGeneration');
    failure.capture(error, stackTrace, method: _lastAction.name, expectedState: 'action_completed', currentState: state.phase.name);
    emit(
      state.copyWith(
        phase: ProvisioningPhase.failure,
        error: failure.exception,
        clearDeviceInfo: state.linkStatus == BleLinkStatus.disconnected || state.linkStatus == BleLinkStatus.connecting,
        clearPairingWindow: state.linkStatus == BleLinkStatus.disconnected || state.linkStatus == BleLinkStatus.connecting,
        clearPairingProgress: state.linkStatus == BleLinkStatus.disconnected || state.linkStatus == BleLinkStatus.connecting,
        linkStatus: releaseFailed
            ? BleLinkStatus.releaseFailed
            : state.linkStatus == BleLinkStatus.connecting
            ? BleLinkStatus.disconnected
            : state.linkStatus,
      ),
    );
    final repository = _repository;
    if (repository is BleFailureDiagnostics) {
      unawaited((repository as BleFailureDiagnostics).recordFailureDetails(failure.exception).catchError((Object _) {}));
    }
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
    final cleanup =
        _resetFuture ??
        (_control != null && _owner != null && !retainSession
            ? _control!.endSession(_owner!).catchError((Object error, StackTrace stack) {
                final failure = _failures ??= BleAttemptFailure(attemptId: 'page-$_actionGeneration');
                failure.capture(error, stack, method: 'close.endSession', expectedState: 'gatt_closed', currentState: 'closing');
                final repository = _repository;
                if (repository is BleFailureDiagnostics) unawaited((repository as BleFailureDiagnostics).recordFailureDetails(failure.exception).catchError((Object _) {}));
              })
            : null);
    await _discoverySubscription?.cancel();
    await _scanDiagnosticSubscription?.cancel();
    await _pairingSubscription?.cancel();
    await _disconnectSubscription?.cancel();
    if (_control != null && _owner != null) {
      await cleanup;
    } else {
      await _repository.stopDiscovery();
    }
    return super.close();
  }
}

enum _ProvisioningAction { discover, connect, openPairing, authorizePairing, disconnect }

enum _SettingsKind { permission, location }

final class _SettingsRequest {
  _SettingsRequest(this.kind, this.generation, this.owner, this.sequence);
  final _SettingsKind kind;
  final int generation;
  final Object? owner;
  final int sequence;
  bool leftApp = false;
}
