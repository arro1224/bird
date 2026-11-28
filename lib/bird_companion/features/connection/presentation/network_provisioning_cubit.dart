import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:crypto/crypto.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';

import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum NetworkProvisioningPhase {
  idle,
  methodUnavailable,
  startingDirectAp,
  stoppingDirectAp,
  choosingWifiMethod,
  scanningWifi,
  choosingWifiNetwork,
  enteringWifiManually,
  configuringSta,
  preparingDpp,
  dppUnavailable,
  confirmingNetwork,
  success,
  stopped,
  recovered,
  cancelled,
  failure,
}

/// Which attempt produced [NetworkProvisioningPhase.failure].
///
/// A failed attempt to join the target Wi-Fi must not be presented as a Bluetooth or
/// direct-AP problem: the page labels it "加入失败" and reassures the user that the box
/// keeps its last working network.
enum NetworkProvisioningFailureOrigin { wifiJoin, wifiScan }

final class NetworkProvisioningState {
  const NetworkProvisioningState({
    this.phase = NetworkProvisioningPhase.idle,
    this.trustedDeviceId,
    this.capabilities,
    this.activeOperationId,
    this.operationState,
    this.wifiNetworks = const [],
    this.baseUri,
    this.confirmedMode,
    this.recoveredMode,
    this.directApStopReason,
    this.stoppedStaRestored,
    this.dppAvailability,
    this.dppAvailabilityChecking = false,
    this.error,
    this.canCancel = false,
    this.directApSsid,
    this.failureOrigin,
  });

  final NetworkProvisioningPhase phase;
  final String? trustedDeviceId;
  final DeviceCapabilities? capabilities;
  final String? activeOperationId;
  final NetworkOperationState? operationState;
  final List<WifiScanNetwork> wifiNetworks;
  final Uri? baseUri;
  final ProvisioningNetworkMode? confirmedMode;
  final ProvisioningNetworkMode? recoveredMode;
  final String? directApStopReason;
  final bool? stoppedStaRestored;
  final DppAvailability? dppAvailability;
  final bool dppAvailabilityChecking;
  final Object? error;
  final bool canCancel;
  final String? directApSsid;

  /// Set only when the failure came from joining the target Wi-Fi.
  final NetworkProvisioningFailureOrigin? failureOrigin;

  NetworkProvisioningState copyWith({
    NetworkProvisioningPhase? phase,
    String? trustedDeviceId,
    DeviceCapabilities? capabilities,
    String? activeOperationId,
    NetworkOperationState? operationState,
    List<WifiScanNetwork>? wifiNetworks,
    Uri? baseUri,
    ProvisioningNetworkMode? confirmedMode,
    ProvisioningNetworkMode? recoveredMode,
    String? directApStopReason,
    bool? stoppedStaRestored,
    DppAvailability? dppAvailability,
    bool? dppAvailabilityChecking,
    Object? error,
    bool? canCancel,
    String? directApSsid,
    NetworkProvisioningFailureOrigin? failureOrigin,
    bool clearFailureOrigin = false,
    bool clearOperation = false,
    bool clearOperationState = false,
    bool clearNetworks = false,
    bool clearBaseUri = false,
    bool clearConfirmedMode = false,
    bool clearRecoveredMode = false,
    bool clearDirectApStopReason = false,
    bool clearDppAvailability = false,
    bool clearError = false,
  }) => NetworkProvisioningState(
    phase: phase ?? this.phase,
    trustedDeviceId: trustedDeviceId ?? this.trustedDeviceId,
    capabilities: capabilities ?? this.capabilities,
    activeOperationId: clearOperation ? null : activeOperationId ?? this.activeOperationId,
    operationState: clearOperationState ? null : operationState ?? this.operationState,
    wifiNetworks: clearNetworks ? const [] : wifiNetworks ?? this.wifiNetworks,
    baseUri: clearBaseUri ? null : baseUri ?? this.baseUri,
    confirmedMode: clearConfirmedMode ? null : confirmedMode ?? this.confirmedMode,
    recoveredMode: clearRecoveredMode ? null : recoveredMode ?? this.recoveredMode,
    directApStopReason: clearDirectApStopReason ? null : directApStopReason ?? this.directApStopReason,
    stoppedStaRestored: clearDirectApStopReason ? null : stoppedStaRestored ?? this.stoppedStaRestored,
    dppAvailability: clearDppAvailability ? null : dppAvailability ?? this.dppAvailability,
    dppAvailabilityChecking: dppAvailabilityChecking ?? this.dppAvailabilityChecking,
    error: clearError ? null : error ?? this.error,
    canCancel: canCancel ?? this.canCancel,
    directApSsid: directApSsid ?? this.directApSsid,
    failureOrigin: clearFailureOrigin ? null : failureOrigin ?? this.failureOrigin,
  );
}

final class NetworkProvisioningCubit extends Cubit<NetworkProvisioningState> {
  NetworkProvisioningCubit(
    this._repository, {
    this.directApHandoff,
    this.resolveStaEndpoint,
    this.reconcileStop = false,
    this.diagnostic,
    this.onIntentStarted,
    this.onIntentEnded,
    this.reconciliationWindow = const Duration(seconds: 60),
    this.pollInterval = const Duration(seconds: 2),
    this.wifiScanTimeout = const Duration(seconds: 30),
  }) : super(const NetworkProvisioningState()) {
    _eventSubscription = _repository.events.listen(
      _onEvent,
      onError: _onEventError,
    );
  }

  final ProvisioningRepository _repository;
  InfrastructureStaSnapshot? get savedStaSnapshot => _repository is ProvisioningEndpointSnapshot ? (_repository as ProvisioningEndpointSnapshot).lastNetworkSnapshot?.infrastructureSta : null;
  final Duration wifiScanTimeout;
  Timer? _scanDeadline;
  bool _scanCancelRequested = false;
  final bool reconcileStop;
  Timer? _stopPoll, _stopDeadline;
  bool _readingStop = false;
  String? _lastStopOperationId;
  final DirectApHandoffCubit? directApHandoff;
  final Future<Uri?> Function(String deviceId)? resolveStaEndpoint;
  final void Function(Map<String, dynamic>)? diagnostic;
  final void Function(String id)? onIntentStarted, onIntentEnded;
  final Duration reconciliationWindow, pollInterval;
  Timer? _staDeadline, _staPoll;
  bool _readingSta = false;
  String? _attemptId;
  String? get attemptId => _attemptId;
  void _beginIntent(String event) {
    _attemptId = SecureRequestIdFactory().create();
    onIntentStarted?.call(_attemptId!);
    _trace(event);
  }

  void _endIntent() {
    final id = _attemptId;
    if (id != null) onIntentEnded?.call(id);
  }

  @override
  void emit(NetworkProvisioningState state) {
    if (state.phase != NetworkProvisioningPhase.scanningWifi) {
      _scanDeadline?.cancel();
      _scanDeadline = null;
    }
    super.emit(state);
    if (reconcileStop && state.phase == NetworkProvisioningPhase.stopped && state.stoppedStaRestored == true && state.error == null) return;
    if (const {
      NetworkProvisioningPhase.failure,
      NetworkProvisioningPhase.cancelled,
      NetworkProvisioningPhase.stopped,
      NetworkProvisioningPhase.recovered,
      NetworkProvisioningPhase.methodUnavailable,
      NetworkProvisioningPhase.dppUnavailable,
    }.contains(state.phase)) {
      _endIntent();
    }
  }

  void _trace(String event, {Object? error, StackTrace? stack, Map<String, dynamic> fields = const {}}) {
    diagnostic?.call({
      'event': event,
      'attempt_id': _attemptId,
      'generation': _generation,
      'phase': state.phase.name,
      'device_id': state.trustedDeviceId,
      'operation_id': state.activeOperationId,
      if (error != null) 'error_class': error.runtimeType.toString(),
      if (error != null) 'error_code': directApErrorKind(error),
      if (stack != null) 'stack_frames': stack.toString().split('\n').take(8).map((frame) => frame.replaceAll(RegExp(r'\?.*'), '[redacted]')).join('\n'),
      ...fields,
    });
  }

  void _stopStaReconciliation() {
    _staDeadline?.cancel();
    _staPoll?.cancel();
    _staDeadline = _staPoll = null;
  }

  late final StreamSubscription<ProvisioningEvent> _eventSubscription;
  var _generation = 0;
  String? _cancellingOperationId;
  final Map<int, WifiScanBatch> _scanBatches = {};
  int? _expectedScanBatchCount;
  var _scanCompleteSeen = false;
  var _resumeConsumed = false;

  bool get networkStatusResumeRequired => !_resumeConsumed && _repository is ProvisioningSessionRepository && (_repository as ProvisioningSessionRepository).networkStatusResumeRequired;

  Future<void> startDirectAp(ProvisioningDeviceInfo info) async {
    if (state.phase == NetworkProvisioningPhase.startingDirectAp || directApHandoff?.state.active == true) return;
    final generation = ++_generation;
    if (!info.capabilities.directAp) {
      emit(
        NetworkProvisioningState(
          phase: NetworkProvisioningPhase.methodUnavailable,
          trustedDeviceId: info.deviceId,
          capabilities: info.capabilities,
        ),
      );
      return;
    }

    emit(
      NetworkProvisioningState(
        phase: NetworkProvisioningPhase.startingDirectAp,
        trustedDeviceId: info.deviceId,
        capabilities: info.capabilities,
        operationState: NetworkOperationState.startingAp,
      ),
    );
    _beginIntent('ap_intent_started');
    try {
      if (directApHandoff != null) {
        final current = await _repository.getNetworkStatus();
        if (isClosed || generation != _generation) return;
        if (!current.busy && current.activeMode == ProvisioningNetworkMode.directAp && current.operationState == NetworkOperationState.apReady && current.baseUri != null) {
          _directApReady(current.baseUri!, current.operationId ?? 'existing-direct-ap', current.directAp.ssid);
          return;
        }
        if (current.busy) {
          if (current.desiredMode == ProvisioningNetworkMode.directAp && current.operationId != null) {
            emit(state.copyWith(activeOperationId: current.operationId, operationState: current.operationState));
            return;
          }
          throw const ProvisioningException(code: ProvisioningErrorCode.networkOperationBusy, retryable: true);
        }
      }
      final accepted = await _repository.startDirectAp();
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          activeOperationId: accepted.operationId,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          clearOperation: true,
          canCancel: false,
        ),
      );
    }
  }

  bool _stopValidationInFlight = false;

  bool get networkOperationBusy => const {
    NetworkProvisioningPhase.startingDirectAp,
    NetworkProvisioningPhase.stoppingDirectAp,
    NetworkProvisioningPhase.configuringSta,
    NetworkProvisioningPhase.preparingDpp,
    NetworkProvisioningPhase.confirmingNetwork,
    NetworkProvisioningPhase.scanningWifi,
  }.contains(state.phase);

  Future<void> stopDirectAp({bool confirmCurrentState = false, bool Function()? canProceed}) async {
    if (_stopValidationInFlight || networkOperationBusy) return;
    if (!confirmCurrentState && (state.phase != NetworkProvisioningPhase.success || state.confirmedMode != ProvisioningNetworkMode.directAp)) return;
    if (confirmCurrentState) {
      final generation = _generation;
      _stopValidationInFlight = true;
      try {
        final status = await _repository.getNetworkStatus().timeout(const Duration(seconds: 15));
        if (isClosed || generation != _generation || canProceed?.call() == false) return;
        _trace('stop_ap_status_checked', fields: {'active_mode': status.activeMode.wireValue, 'operation_state': status.operationState.wireValue, 'busy': status.busy});
        if (status.activeMode != ProvisioningNetworkMode.directAp || status.busy) {
          emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: const NetworkStatusConfirmationException()));
          return;
        }
      } catch (error) {
        if (!isClosed && generation == _generation) emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: _safePresentationError(error)));
        return;
      } finally {
        _stopValidationInFlight = false;
      }
    }
    final generation = ++_generation;
    if (reconcileStop) _beginIntent('stop_ap_intent_started');
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.stoppingDirectAp,
        operationState: NetworkOperationState.stoppingAp,
        clearOperation: true,
        clearBaseUri: true,
        clearConfirmedMode: true,
        clearError: true,
        clearDirectApStopReason: true,
        canCancel: false,
      ),
    );
    try {
      final accepted = await _repository.stopDirectAp();
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(activeOperationId: accepted.operationId));
      _lastStopOperationId = accepted.operationId;
      if (reconcileStop) _startStopReconciliation(generation);
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          canCancel: false,
        ),
      );
    }
  }

  /// Rebuilds presentation state from the box's authoritative network status.
  ///
  /// This is used after BLE reconnect. An accepted operation continues on the
  /// box while the transport is down, so local phase memory must not be used as
  /// the source of truth.
  Future<void> resumeAfterBleReconnect(ProvisioningDeviceInfo info, {bool handoffDirectAp = true, bool verifyBusiness = true, CancelToken? cancelToken}) async {
    cancelToken?.throwIfCancellationRequested();
    _resumeConsumed = true;
    if (directApHandoff?.state.active == true) return;
    final generation = ++_generation;
    if (handoffDirectAp) _beginIntent('network_intent_started');
    _clearScanAccumulator();
    emit(
      NetworkProvisioningState(
        trustedDeviceId: info.deviceId,
        capabilities: info.capabilities,
      ),
    );
    try {
      final status = await _repository.getNetworkStatus();
      cancelToken?.throwIfCancellationRequested();
      if (isClosed || generation != _generation || cancelToken?.isCancelled == true) return;
      if (reconcileStop && _lastStopOperationId != null && status.operationId == _lastStopOperationId && !status.busy && status.activeMode != ProvisioningNetworkMode.directAp) {
        _beginIntent('resume_stop_terminal');
        emit(state.copyWith(phase: NetworkProvisioningPhase.stoppingDirectAp, activeOperationId: status.operationId, operationState: status.operationState, canCancel: false));
        _startStopReconciliation(generation);
        return;
      }
      if (status.busy && status.operationId != null) {
        emit(
          state.copyWith(
            phase: _phaseForResumedOperation(status),
            activeOperationId: status.operationId,
            operationState: status.operationState,
            canCancel: status.operationState.cancellable,
            clearError: true,
          ),
        );
        if (reconcileStop && status.operationState == NetworkOperationState.stoppingAp) {
          _beginIntent('resume_stop_intent');
          _lastStopOperationId = status.operationId;
          _startStopReconciliation(generation);
        }
        return;
      }
      if (status.activeMode == ProvisioningNetworkMode.directAp && status.operationState == NetworkOperationState.apReady && status.baseUri != null) {
        if (directApHandoff != null && handoffDirectAp) {
          _directApReady(status.baseUri!, status.operationId ?? 'existing-direct-ap', status.directAp.ssid);
          return;
        }
        if (verifyBusiness) await _verifyResumedTerminal(status);
        if (isClosed || generation != _generation) return;
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.success,
            activeOperationId: status.operationId,
            operationState: status.operationState,
            baseUri: status.baseUri,
            confirmedMode: ProvisioningNetworkMode.directAp,
            clearError: true,
          ),
        );
        return;
      }
      if (status.activeMode == ProvisioningNetworkMode.infrastructureSta && status.operationState == NetworkOperationState.staConnected && status.baseUri != null) {
        if (directApHandoff != null && handoffDirectAp) {
          _staReady(status.baseUri!, status.operationId ?? 'existing-sta');
          return;
        }
        if (verifyBusiness) await _verifyResumedTerminal(status);
        if (isClosed || generation != _generation) return;
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.success,
            activeOperationId: status.operationId,
            operationState: status.operationState,
            baseUri: status.baseUri,
            confirmedMode: ProvisioningNetworkMode.infrastructureSta,
            clearError: true,
          ),
        );
        return;
      }
      if (status.operationState == NetworkOperationState.failed || status.lastError != null) {
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.failure,
            activeOperationId: status.operationId,
            operationState: status.operationState,
            error: status.lastError ?? const NetworkOperationFailedException(),
            canCancel: false,
          ),
        );
        return;
      }
      if (status.operationState == NetworkOperationState.cancelled) {
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.cancelled,
            activeOperationId: status.operationId,
            operationState: status.operationState,
            canCancel: false,
            clearError: true,
          ),
        );
      }
      // idle/none deliberately remains idle so a fresh pairing continues to
      // the normal connection-method chooser.
      _endIntent();
    } catch (error) {
      if (isClosed || generation != _generation || cancelToken?.isCancelled == true) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          canCancel: false,
        ),
      );
    }
  }

  Future<void> _verifyResumedTerminal(ProvisioningNetworkStatus status) async {
    final verifier = _repository is ProvisioningNetworkStatusVerifier ? _repository as ProvisioningNetworkStatusVerifier : null;
    await verifier?.verifyNetworkStatus(status);
  }

  void acceptVerifiedHandoff(ProvisioningCompletion completion, String operationId) {
    if (isClosed || state.trustedDeviceId != completion.deviceId || state.activeOperationId != operationId) return;
    emit(state.copyWith(phase: NetworkProvisioningPhase.success, baseUri: completion.baseUri, confirmedMode: completion.networkMode, clearError: true));
  }

  void _stopStopReconciliation() {
    _stopPoll?.cancel();
    _stopDeadline?.cancel();
    _stopPoll = _stopDeadline = null;
  }

  Future<void> retryStoppedNetwork() async {
    if (!reconcileStop || _lastStopOperationId == null || _readingStop) return;
    _beginIntent('retry_stopped_network');
    _startStopReconciliation(_generation);
  }

  void _startStopReconciliation(int generation) {
    _stopStopReconciliation();
    _stopPoll = Timer.periodic(pollInterval, (_) => unawaited(_pollStoppedNetwork(generation)));
    _stopDeadline = Timer(reconciliationWindow, () {
      _stopStopReconciliation();
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(phase: state.phase == NetworkProvisioningPhase.stopped ? NetworkProvisioningPhase.stopped : NetworkProvisioningPhase.failure, error: const NetworkStatusConfirmationException(), canCancel: false));
    });
    unawaited(_pollStoppedNetwork(generation));
  }

  Future<void> _pollStoppedNetwork(int generation) async {
    if (isClosed || generation != _generation || _readingStop || _lastStopOperationId == null) return;
    _readingStop = true;
    try {
      ProvisioningNetworkStatus? status;
      try {
        status = await _repository.getNetworkStatus();
      } catch (_) {
        /* BLE may drop during AP stop. */
      }
      if (isClosed || generation != _generation) return;
      if (status?.operationId == _lastStopOperationId && status?.busy == false) {
        if (status!.activeMode != ProvisioningNetworkMode.directAp && _repository is StoppedDirectApCleanup) {
          await (_repository as StoppedDirectApCleanup).confirmStoppedNetwork(state.trustedDeviceId!, _lastStopOperationId!);
          if (isClosed || generation != _generation) return;
        }
        if (status.activeMode == ProvisioningNetworkMode.infrastructureSta && status.operationState == NetworkOperationState.staConnected && status.baseUri != null) {
          if (directApHandoff != null) {
            _staReady(status.baseUri!, _lastStopOperationId!);
          } else {
            await _verifyResumedTerminal(status);
            if (isClosed || generation != _generation) return;
            _stopStopReconciliation();
            emit(state.copyWith(phase: NetworkProvisioningPhase.success, baseUri: status.baseUri, confirmedMode: ProvisioningNetworkMode.infrastructureSta, stoppedStaRestored: true, clearError: true));
          }
          return;
        }
        if (status.activeMode == ProvisioningNetworkMode.none) {
          _stopStopReconciliation();
          emit(state.copyWith(phase: NetworkProvisioningPhase.stopped, stoppedStaRestored: false, canCancel: false));
          return;
        }
      }
      // A correlated stop terminal is required before endpoint discovery can
      // complete an operation whose BLE result disappeared with the AP.
      if (state.phase == NetworkProvisioningPhase.stopped && state.stoppedStaRestored == true) {
        final id = state.trustedDeviceId;
        final endpoint = id == null ? null : await resolveStaEndpoint?.call(id).timeout(const Duration(seconds: 5));
        if (!isClosed && generation == _generation && endpoint != null && directApHandoff != null) _staReady(endpoint, _lastStopOperationId!);
      }
    } catch (error, stack) {
      if (!isClosed && generation == _generation) _trace('stop_network_verification_pending', error: error, stack: stack);
    } finally {
      _readingStop = false;
    }
  }

  void backToMethodSelection() {
    _endIntent();
    _stopStaReconciliation();
    _stopStopReconciliation();
    _lastStopOperationId = null;
    if (directApHandoff?.state.active == true) unawaited(directApHandoff!.cancel());
    _generation++;
    _clearScanAccumulator();
    emit(const NetworkProvisioningState());
  }

  void completionFailed(Object error) {
    if (isClosed || state.phase != NetworkProvisioningPhase.success) return;
    emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: _safePresentationError(error), canCancel: false));
  }

  Future<void> retryCredentialSave() async {
    if (state.phase != NetworkProvisioningPhase.failure || state.error is! ProvisioningCredentialSaveException) return;
    final generation = ++_generation;
    emit(state.copyWith(phase: NetworkProvisioningPhase.confirmingNetwork, clearError: true));
    try {
      final status = await _repository.getNetworkStatus();
      if (isClosed || generation != _generation) return;
      final mode = status.activeMode;
      final terminal =
          (mode == ProvisioningNetworkMode.directAp && status.operationState == NetworkOperationState.apReady) || (mode == ProvisioningNetworkMode.infrastructureSta && status.operationState == NetworkOperationState.staConnected);
      if (!terminal || status.busy || status.operationId != state.activeOperationId || status.baseUri == null) throw const NetworkStatusConfirmationException();
      await _verifyResumedTerminal(status);
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(phase: NetworkProvisioningPhase.success, baseUri: status.baseUri, confirmedMode: mode, operationState: status.operationState, clearError: true));
    } catch (error) {
      if (!isClosed && generation == _generation) emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: _safePresentationError(error)));
    }
  }

  void openWifiProvisioning(ProvisioningDeviceInfo info) {
    _stopStopReconciliation();
    _lastStopOperationId = null;
    final generation = ++_generation;
    _clearScanAccumulator();
    emit(
      NetworkProvisioningState(
        phase: info.capabilities.infrastructureSta ? NetworkProvisioningPhase.choosingWifiMethod : NetworkProvisioningPhase.methodUnavailable,
        trustedDeviceId: info.deviceId,
        capabilities: info.capabilities,
        dppAvailability: info.capabilities.dppUsableByBox ? null : const DppAvailability.unavailable(),
        dppAvailabilityChecking: info.capabilities.infrastructureSta && info.capabilities.dppUsableByBox,
      ),
    );
    if (info.capabilities.infrastructureSta && info.capabilities.dppUsableByBox) {
      unawaited(_refreshDppAvailability(generation));
    }
  }

  Future<void> _refreshDppAvailability(int generation) async {
    final capabilityRepository = _repository is DppAvailabilityRepository ? _repository as DppAvailabilityRepository : null;
    if (capabilityRepository == null) {
      if (!isClosed && generation == _generation) {
        emit(
          state.copyWith(
            dppAvailability: const DppAvailability.unavailable(
              boxSupported: true,
            ),
            dppAvailabilityChecking: false,
          ),
        );
      }
      return;
    }
    try {
      final availability = await capabilityRepository.checkDppAvailability();
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          dppAvailability: availability,
          dppAvailabilityChecking: false,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          dppAvailability: const DppAvailability.unavailable(
            boxSupported: true,
          ),
          dppAvailabilityChecking: false,
        ),
      );
    }
  }

  Future<void> scanWifi() async {
    if (isClosed || state.phase == NetworkProvisioningPhase.scanningWifi || state.phase == NetworkProvisioningPhase.configuringSta || state.phase == NetworkProvisioningPhase.confirmingNetwork) return;
    final capabilities = state.capabilities;
    if (capabilities == null || !capabilities.infrastructureSta || !capabilities.wifiScan) {
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.methodUnavailable,
          clearOperation: true,
          clearOperationState: true,
          clearNetworks: true,
          clearError: true,
          canCancel: false,
        ),
      );
      return;
    }
    final generation = ++_generation;
    _clearScanAccumulator();
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.scanningWifi,
        operationState: NetworkOperationState.scanning,
        clearOperation: true,
        clearNetworks: true,
        clearError: true,
        canCancel: true,
        failureOrigin: NetworkProvisioningFailureOrigin.wifiScan,
      ),
    );
    _scanDeadline = Timer(wifiScanTimeout, () {
      if (isClosed || state.phase != NetworkProvisioningPhase.scanningWifi) return;
      _generation++;
      emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: const NetworkOperationFailedException(), failureOrigin: NetworkProvisioningFailureOrigin.wifiScan, clearOperation: true, canCancel: false));
    });
    try {
      final accepted = await _repository.scanWifi();
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(activeOperationId: accepted.operationId));
      if (_scanCancelRequested) {
        emit(state.copyWith(canCancel: true));
        await cancelActiveOperation();
      }
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          failureOrigin: NetworkProvisioningFailureOrigin.wifiScan,
          clearOperation: true,
          canCancel: false,
        ),
      );
    }
  }

  void showManualWifi() {
    if (state.phase == NetworkProvisioningPhase.scanningWifi) return;
    if (state.capabilities?.wifiManual != true) {
      emit(state.copyWith(phase: NetworkProvisioningPhase.methodUnavailable));
      return;
    }
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.enteringWifiManually,
        clearError: true,
        clearFailureOrigin: true,
      ),
    );
  }

  void returnToWifiMethodSelection() {
    _generation++;
    _clearScanAccumulator();
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.choosingWifiMethod,
        clearOperation: true,
        clearOperationState: true,
        clearNetworks: true,
        clearBaseUri: true,
        clearConfirmedMode: true,
        clearRecoveredMode: true,
        clearError: true,
        clearFailureOrigin: true,
        canCancel: false,
      ),
    );
  }

  Future<void> submitStaConfiguration(
    StaNetworkConfiguration configuration,
  ) async {
    if (state.phase == NetworkProvisioningPhase.configuringSta || state.phase == NetworkProvisioningPhase.confirmingNetwork || directApHandoff?.state.active == true) return;
    final capabilities = state.capabilities;
    final supported =
        capabilities?.infrastructureSta == true &&
        switch (configuration.selectionMethod) {
          _ when configuration.provisioningMethod == ProvisioningMethod.wifiQr => true,
          WifiSelectionMethod.scanResult => capabilities?.wifiScan == true,
          WifiSelectionMethod.manual => capabilities?.wifiManual == true,
        };
    if (!supported) {
      emit(state.copyWith(phase: NetworkProvisioningPhase.methodUnavailable));
      return;
    }
    final generation = ++_generation;
    _beginIntent('network_intent_started');
    _trace('sta_intent_started', fields: {'network_identity_hash': sha256.convert(utf8.encode(configuration.ssid)).toString()});
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.configuringSta,
        failureOrigin: NetworkProvisioningFailureOrigin.wifiJoin,
        operationState: NetworkOperationState.credentialsReceived,
        clearOperation: true,
        clearBaseUri: true,
        clearError: true,
        canCancel: false,
      ),
    );
    try {
      final accepted = await _repository.setStaConfig(configuration);
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(activeOperationId: accepted.operationId));
      _trace('sta_command_accepted');
      if (directApHandoff != null) _startStaReconciliation(generation);
    } catch (error, stack) {
      if (isClosed || generation != _generation) return;
      _trace('sta_command_failed', error: error, stack: stack);
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          failureOrigin: NetworkProvisioningFailureOrigin.wifiJoin,
          clearOperation: true,
          canCancel: false,
        ),
      );
    }
  }

  Future<void> submitWifiQrCredentials(WifiQrCredentials credentials) => submitStaConfiguration(credentials.toStaNetworkConfiguration());

  Future<void> startDppProvisioning() async {
    final currentError = state.error;
    final canStart =
        state.phase == NetworkProvisioningPhase.choosingWifiMethod ||
        (state.phase == NetworkProvisioningPhase.failure && currentError is ProvisioningException && (currentError.code == ProvisioningErrorCode.systemDppFailed || currentError.code == ProvisioningErrorCode.dppTimeout));
    if (!canStart) return;

    final capabilities = state.capabilities;
    if (capabilities?.infrastructureSta != true || capabilities?.dppUsableByBox != true) {
      emit(state.copyWith(phase: NetworkProvisioningPhase.methodUnavailable));
      return;
    }
    final generation = ++_generation;
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.preparingDpp,
        operationState: NetworkOperationState.preparingDpp,
        clearOperation: true,
        clearBaseUri: true,
        clearError: true,
        canCancel: false,
      ),
    );
    _beginIntent('network_intent_started');
    try {
      final accepted = await _repository.startDppProvisioning();
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          activeOperationId: accepted.operationId,
          canCancel: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      _emitDppOutcome(error);
    }
  }

  Future<void> cancelActiveOperation() async {
    final operationId = state.activeOperationId;
    if (!state.canCancel || operationId == null) return;
    final generation = ++_generation;
    _cancellingOperationId = operationId;
    emit(state.copyWith(canCancel: false));
    try {
      final accepted = await _repository.cancelNetworkOperation(operationId);
      if (_cancellingOperationId == operationId) {
        _cancellingOperationId = null;
      }
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          activeOperationId: accepted.operationId,
          canCancel: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_cancellingOperationId == operationId) {
        _cancellingOperationId = null;
      }
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          canCancel: false,
        ),
      );
    }
  }

  /// Cancellation is also available while the scan command is awaiting its ACK.
  /// The operation ID must come from that ACK; no synthetic cancel is sent.
  Future<void> cancelWifiScan() async {
    if (state.phase != NetworkProvisioningPhase.scanningWifi || _scanCancelRequested) return;
    _scanCancelRequested = true;
    if (state.activeOperationId == null) {
      emit(state.copyWith(canCancel: false));
    } else {
      await cancelActiveOperation();
    }
  }

  void _emitDppOutcome(Object error) {
    final safeError = _safePresentationError(error);
    final phase = switch (safeError) {
      ProvisioningException(
        code: ProvisioningErrorCode.userCancelledDppDialog,
      ) =>
        NetworkProvisioningPhase.cancelled,
      ProvisioningException(
        code: ProvisioningErrorCode.phoneDppNotSupported || ProvisioningErrorCode.systemDppActivityUnavailable || ProvisioningErrorCode.systemDppInvalidUri,
      ) =>
        NetworkProvisioningPhase.dppUnavailable,
      _ => NetworkProvisioningPhase.failure,
    };
    emit(
      state.copyWith(
        phase: phase,
        error: phase == NetworkProvisioningPhase.failure ? safeError : null,
        clearError: phase != NetworkProvisioningPhase.failure,
        clearOperation: true,
        canCancel: false,
      ),
    );
  }

  void _onEvent(ProvisioningEvent event) {
    if (isClosed || event.deviceId != state.trustedDeviceId) return;
    _trace('network_event_received', fields: {'request_id': event.requestId, 'received_operation_id': event.operationId, 'event_type': event.type.wireValue});
    final eventOperationId = event.operationId;
    if (eventOperationId != null && eventOperationId != state.activeOperationId) {
      return;
    }
    if (eventOperationId != null && eventOperationId == _cancellingOperationId) {
      return;
    }

    final payload = event.payload;
    if (payload is WifiScanBatch) {
      _onWifiScanBatch(payload);
      return;
    }
    if (payload is NetworkProgress) {
      final acceptsProgress = switch (state.phase) {
        NetworkProvisioningPhase.startingDirectAp || NetworkProvisioningPhase.stoppingDirectAp || NetworkProvisioningPhase.scanningWifi || NetworkProvisioningPhase.configuringSta || NetworkProvisioningPhase.preparingDpp => true,
        _ => false,
      };
      if (!acceptsProgress) return;
      if (payload.operationState == NetworkOperationState.failed) {
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.failure,
            operationState: payload.operationState,
            error: const NetworkOperationFailedException(),
            failureOrigin: state.phase == NetworkProvisioningPhase.configuringSta
                ? NetworkProvisioningFailureOrigin.wifiJoin
                : state.phase == NetworkProvisioningPhase.scanningWifi
                ? NetworkProvisioningFailureOrigin.wifiScan
                : null,
            canCancel: false,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          operationState: payload.operationState,
          canCancel: payload.operationState.cancellable,
          clearError: true,
        ),
      );
      return;
    }
    if (payload is DirectApStopped && state.phase == NetworkProvisioningPhase.stoppingDirectAp) {
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.stopped,
          operationState: payload.operationState,
          clearBaseUri: true,
          clearConfirmedMode: true,
          directApStopReason: payload.reason,
          stoppedStaRestored: payload.restoredSta,
          canCancel: false,
          clearError: true,
        ),
      );
      if (reconcileStop) {
        if (!payload.restoredSta) {
          _stopStopReconciliation();
        } else {
          unawaited(_pollStoppedNetwork(_generation));
        }
      }
      return;
    }
    if (payload is DppBootstrapReady && state.phase == NetworkProvisioningPhase.preparingDpp) {
      emit(
        state.copyWith(
          operationState: payload.operationState,
          canCancel: payload.operationState.cancellable,
          clearError: true,
        ),
      );
      return;
    }
    if (payload is StaConnected && (state.phase == NetworkProvisioningPhase.configuringSta || state.phase == NetworkProvisioningPhase.preparingDpp || state.phase == NetworkProvisioningPhase.stoppingDirectAp)) {
      if (directApHandoff != null) {
        // The correlated terminal event is already box evidence. A second BLE
        // command must not veto an otherwise valid HTTP/WS handoff.
        _staReady(payload.baseUri, payload.operationId);
        return;
      }
      final generation = _generation;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.confirmingNetwork,
          operationState: NetworkOperationState.staConnected,
          canCancel: false,
          clearError: true,
        ),
      );
      unawaited(_confirmSta(generation));
      return;
    }
    if (payload is NetworkRecovered) {
      if (reconcileStop && state.phase == NetworkProvisioningPhase.stoppingDirectAp && payload.recoveredMode == ProvisioningNetworkMode.infrastructureSta && payload.baseUri != null) {
        _staReady(payload.baseUri!, payload.operationId);
        return;
      }
      final acceptsRecovery = switch (state.phase) {
        NetworkProvisioningPhase.startingDirectAp || NetworkProvisioningPhase.stoppingDirectAp || NetworkProvisioningPhase.configuringSta || NetworkProvisioningPhase.preparingDpp || NetworkProvisioningPhase.failure => true,
        _ => false,
      };
      if (!acceptsRecovery) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.recovered,
          operationState: payload.operationState,
          recoveredMode: payload.recoveredMode,
          clearBaseUri: true,
          canCancel: false,
          clearError: true,
        ),
      );
      return;
    }
    if (payload is CancelledOperation) {
      if (state.phase != NetworkProvisioningPhase.scanningWifi && state.phase != NetworkProvisioningPhase.preparingDpp) {
        return;
      }
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.cancelled,
          operationState: NetworkOperationState.cancelled,
          canCancel: false,
          clearError: true,
        ),
      );
      return;
    }
    if (payload is DirectApReady && state.phase == NetworkProvisioningPhase.startingDirectAp) {
      _directApReady(payload.baseUri, payload.operationId, payload.ssid);
    }
  }

  void _staReady(Uri baseUri, String operationId) {
    _stopStaReconciliation();
    _stopStopReconciliation();
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.confirmingNetwork,
        operationState: NetworkOperationState.staConnected,
        activeOperationId: operationId,
        baseUri: baseUri,
        confirmedMode: ProvisioningNetworkMode.infrastructureSta,
        stoppedStaRestored: _lastStopOperationId == operationId ? true : null,
        clearError: true,
        canCancel: false,
      ),
    );
    _trace('sta_endpoint_ready', fields: {'base_uri': baseUri.toString()});
    final id = state.trustedDeviceId;
    if (id != null) unawaited(directApHandoff?.begin(PendingDirectAp(deviceId: id, baseUri: baseUri, operationId: operationId, networkMode: ProvisioningNetworkMode.infrastructureSta, attemptId: _attemptId)));
  }

  void _startStaReconciliation(int generation) {
    _stopStaReconciliation();
    _staPoll = Timer.periodic(pollInterval, (_) => unawaited(_pollSta(generation)));
    _staDeadline = Timer(reconciliationWindow, () => unawaited(_reconcileStaEndpoint(generation)));
    unawaited(_pollSta(generation));
  }

  bool _staCurrent(int generation) => !isClosed && generation == _generation && state.phase == NetworkProvisioningPhase.configuringSta;

  Future<void> _pollSta(int generation) async {
    if (!_staCurrent(generation) || _readingSta) return;
    _readingSta = true;
    try {
      final status = await _repository.getNetworkStatus();
      if (!_staCurrent(generation)) return;
      _trace('sta_status_read', fields: {'status_operation_id': status.operationId, 'operation_state': status.operationState.wireValue, 'busy': status.busy});
      // Another operation or an old success must not complete this intent.
      if (status.operationId != state.activeOperationId) return;
      if (!status.busy && (status.lastError != null || status.operationState == NetworkOperationState.failed || status.operationState == NetworkOperationState.cancelled)) {
        _stopStaReconciliation();
        final error = status.lastError ?? const NetworkOperationFailedException();
        _trace('sta_box_terminal_failure', error: error);
        emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: _safePresentationError(error)));
      } else if (!status.busy && status.activeMode == ProvisioningNetworkMode.infrastructureSta && status.operationState == NetworkOperationState.staConnected && status.baseUri != null) {
        _staReady(status.baseUri!, status.operationId!);
      }
    } catch (error, stack) {
      if (_staCurrent(generation)) _trace('sta_status_temporarily_unavailable', error: error, stack: stack);
      // Accepted board work survives BLE loss; reconcile before declaring failure.
    } finally {
      _readingSta = false;
    }
  }

  Future<void> _reconcileStaEndpoint(int generation) async {
    if (!_staCurrent(generation)) return;
    _stopStaReconciliation();
    try {
      final id = state.trustedDeviceId;
      final endpoint = id == null ? null : await resolveStaEndpoint?.call(id).timeout(const Duration(seconds: 5));
      if (!_staCurrent(generation)) return;
      if (endpoint != null) {
        _trace('sta_ble_terminal_missing_http_fallback');
        _staReady(endpoint, state.activeOperationId!);
        return;
      }
    } catch (error, stack) {
      if (_staCurrent(generation)) _trace('sta_endpoint_lookup_failed', error: error, stack: stack);
    }
    if (_staCurrent(generation)) {
      _trace('sta_confirmation_timeout', error: const NetworkStatusConfirmationException());
      emit(state.copyWith(phase: NetworkProvisioningPhase.failure, error: const NetworkStatusConfirmationException()));
    }
  }

  void _onWifiScanBatch(WifiScanBatch batch) {
    if (state.phase != NetworkProvisioningPhase.scanningWifi || state.activeOperationId == null || _scanCancelRequested) {
      return;
    }
    final expectedCount = _expectedScanBatchCount;
    if (expectedCount != null && expectedCount != batch.batchCount) return;
    _expectedScanBatchCount ??= batch.batchCount;
    _scanBatches[batch.batchIndex] = batch;
    _scanCompleteSeen = _scanCompleteSeen || batch.complete;
    if (!_scanCompleteSeen || _scanBatches.length != batch.batchCount) return;

    final strongestByBssid = <String, WifiScanNetwork>{};
    for (var index = 0; index < batch.batchCount; index++) {
      final currentBatch = _scanBatches[index];
      if (currentBatch == null) return;
      for (final network in currentBatch.networks) {
        final key = network.bssid.toUpperCase();
        final current = strongestByBssid[key];
        if (current == null || network.rssiDbm > current.rssiDbm) {
          strongestByBssid[key] = network;
        }
      }
    }
    final networks = strongestByBssid.values.toList()
      ..sort((a, b) {
        final supportOrder = a.unsupported == b.unsupported
            ? 0
            : a.unsupported
            ? 1
            : -1;
        if (supportOrder != 0) return supportOrder;
        final signalOrder = b.rssiDbm.compareTo(a.rssiDbm);
        if (signalOrder != 0) return signalOrder;
        final ssidOrder = a.ssid.compareTo(b.ssid);
        return ssidOrder != 0 ? ssidOrder : a.bssid.compareTo(b.bssid);
      });
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.choosingWifiNetwork,
        operationState: NetworkOperationState.scanComplete,
        wifiNetworks: List.unmodifiable(networks),
        canCancel: false,
        clearError: true,
      ),
    );
  }

  void _clearScanAccumulator() {
    _scanDeadline?.cancel();
    _scanDeadline = null;
    _scanCancelRequested = false;
    _scanBatches.clear();
    _expectedScanBatchCount = null;
    _scanCompleteSeen = false;
  }

  void _directApReady(Uri baseUri, String operationId, String? ssid) {
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.success,
        operationState: NetworkOperationState.apReady,
        activeOperationId: operationId,
        baseUri: baseUri,
        directApSsid: ssid,
        confirmedMode: ProvisioningNetworkMode.directAp,
        canCancel: false,
        clearError: true,
      ),
    );
    final id = state.trustedDeviceId;
    if (id != null) unawaited(directApHandoff?.begin(PendingDirectAp(deviceId: id, baseUri: baseUri, operationId: operationId, ssid: ssid, attemptId: _attemptId)));
  }

  Future<void> _confirmSta(int generation) async {
    await _confirmTerminalStatus(
      generation: generation,
      expectedMode: ProvisioningNetworkMode.infrastructureSta,
      expectedState: NetworkOperationState.staConnected,
    );
  }

  Future<void> _confirmTerminalStatus({
    required int generation,
    required ProvisioningNetworkMode expectedMode,
    required NetworkOperationState expectedState,
  }) async {
    try {
      final status = await _repository.getNetworkStatus();
      if (isClosed || generation != _generation) return;
      final valid = status.activeMode == expectedMode && status.operationState == expectedState && status.operationId == state.activeOperationId && status.baseUri != null;
      if (!valid) {
        emit(
          state.copyWith(
            phase: NetworkProvisioningPhase.failure,
            error: const NetworkStatusConfirmationException(),
            clearBaseUri: true,
            canCancel: false,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.success,
          operationState: status.operationState,
          baseUri: status.baseUri,
          confirmedMode: expectedMode,
          canCancel: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: _safePresentationError(error),
          clearBaseUri: true,
          canCancel: false,
        ),
      );
    }
  }

  void _onEventError(Object error, StackTrace stackTrace) {
    if (isClosed || state.trustedDeviceId == null) return;
    if (_cancellingOperationId != null) return;
    _trace('network_transport_error', error: error, stack: stackTrace);
    if (state.phase == NetworkProvisioningPhase.failure && state.error != null) return;
    if (directApHandoff?.state.active == true || (directApHandoff != null && state.phase == NetworkProvisioningPhase.configuringSta && state.activeOperationId != null)) return;
    if (state.phase == NetworkProvisioningPhase.preparingDpp) {
      _emitDppOutcome(error);
      return;
    }
    final settled = switch (state.phase) {
      NetworkProvisioningPhase.choosingWifiMethod ||
      NetworkProvisioningPhase.dppUnavailable ||
      NetworkProvisioningPhase.success ||
      NetworkProvisioningPhase.stopped ||
      NetworkProvisioningPhase.recovered ||
      NetworkProvisioningPhase.cancelled => true,
      _ => false,
    };
    if (settled) return;
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.failure,
        error: _safePresentationError(error),
        canCancel: false,
      ),
    );
  }

  @override
  Future<void> close() async {
    _clearScanAccumulator();
    _stopStopReconciliation();
    _endIntent();
    _stopStaReconciliation();
    _generation++;
    await _eventSubscription.cancel();
    return super.close();
  }
}

NetworkProvisioningPhase _phaseForResumedOperation(
  ProvisioningNetworkStatus status,
) => switch (status.operationState) {
  NetworkOperationState.startingAp => NetworkProvisioningPhase.startingDirectAp,
  NetworkOperationState.stoppingAp => NetworkProvisioningPhase.stoppingDirectAp,
  NetworkOperationState.scanning || NetworkOperationState.scanComplete => NetworkProvisioningPhase.scanningWifi,
  NetworkOperationState.preparingDpp || NetworkOperationState.waitingDppConfigurator || NetworkOperationState.dppAuthenticating || NetworkOperationState.dppConfigurationReceived => NetworkProvisioningPhase.preparingDpp,
  _ when status.desiredMode == ProvisioningNetworkMode.directAp => NetworkProvisioningPhase.startingDirectAp,
  _ => NetworkProvisioningPhase.configuringSta,
};

final class NetworkStatusConfirmationException implements Exception {
  const NetworkStatusConfirmationException();

  @override
  String toString() => 'NetworkStatusConfirmationException';
}

final class NetworkOperationFailedException implements Exception {
  const NetworkOperationFailedException();

  @override
  String toString() => 'NetworkOperationFailedException';
}

Object _safePresentationError(Object error) {
  if (error is ProvisioningException) {
    return ProvisioningException(
      code: error.code,
      retryable: error.retryable,
      retryAfter: error.retryAfter,
    );
  }
  if (error is NetworkStatusConfirmationException || error is NetworkOperationFailedException || error is ProvisioningCredentialSaveException) {
    return error;
  }
  return const NetworkOperationFailedException();
}
