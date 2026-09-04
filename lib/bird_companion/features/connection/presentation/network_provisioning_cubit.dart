import 'dart:async';

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
    this.dppAvailability,
    this.dppAvailabilityChecking = false,
    this.error,
    this.canCancel = false,
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
  final DppAvailability? dppAvailability;
  final bool dppAvailabilityChecking;
  final Object? error;
  final bool canCancel;

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
    DppAvailability? dppAvailability,
    bool? dppAvailabilityChecking,
    Object? error,
    bool? canCancel,
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
    dppAvailability: clearDppAvailability ? null : dppAvailability ?? this.dppAvailability,
    dppAvailabilityChecking: dppAvailabilityChecking ?? this.dppAvailabilityChecking,
    error: clearError ? null : error ?? this.error,
    canCancel: canCancel ?? this.canCancel,
  );
}

final class NetworkProvisioningCubit extends Cubit<NetworkProvisioningState> {
  NetworkProvisioningCubit(this._repository) : super(const NetworkProvisioningState()) {
    _eventSubscription = _repository.events.listen(
      _onEvent,
      onError: _onEventError,
    );
  }

  final ProvisioningRepository _repository;
  late final StreamSubscription<ProvisioningEvent> _eventSubscription;
  var _generation = 0;
  String? _cancellingOperationId;
  final Map<int, WifiScanBatch> _scanBatches = {};
  int? _expectedScanBatchCount;
  var _scanCompleteSeen = false;
  var _resumeConsumed = false;

  bool get networkStatusResumeRequired => !_resumeConsumed && _repository is ProvisioningSessionRepository && (_repository as ProvisioningSessionRepository).networkStatusResumeRequired;

  Future<void> startDirectAp(ProvisioningDeviceInfo info) async {
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
    try {
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

  Future<void> stopDirectAp() async {
    if (state.phase != NetworkProvisioningPhase.success || state.confirmedMode != ProvisioningNetworkMode.directAp) {
      return;
    }
    final generation = ++_generation;
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
  Future<void> resumeAfterBleReconnect(ProvisioningDeviceInfo info) async {
    _resumeConsumed = true;
    final generation = ++_generation;
    _clearScanAccumulator();
    emit(
      NetworkProvisioningState(
        trustedDeviceId: info.deviceId,
        capabilities: info.capabilities,
      ),
    );
    try {
      final status = await _repository.getNetworkStatus();
      if (isClosed || generation != _generation) return;
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
        return;
      }
      if (status.activeMode == ProvisioningNetworkMode.directAp && status.operationState == NetworkOperationState.apReady && status.baseUri != null) {
        await _verifyResumedTerminal(status);
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
        await _verifyResumedTerminal(status);
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

  Future<void> _verifyResumedTerminal(ProvisioningNetworkStatus status) async {
    final verifier = _repository is ProvisioningNetworkStatusVerifier ? _repository as ProvisioningNetworkStatusVerifier : null;
    await verifier?.verifyNetworkStatus(status);
  }

  void backToMethodSelection() {
    _generation++;
    _clearScanAccumulator();
    emit(const NetworkProvisioningState());
  }

  void openWifiProvisioning(ProvisioningDeviceInfo info) {
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
      ),
    );
    try {
      final accepted = await _repository.scanWifi();
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(activeOperationId: accepted.operationId));
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

  void showManualWifi() {
    if (state.capabilities?.wifiManual != true) {
      emit(state.copyWith(phase: NetworkProvisioningPhase.methodUnavailable));
      return;
    }
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.enteringWifiManually,
        clearError: true,
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
        canCancel: false,
      ),
    );
  }

  Future<void> submitStaConfiguration(
    StaNetworkConfiguration configuration,
  ) async {
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
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.configuringSta,
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
          canCancel: false,
          clearError: true,
        ),
      );
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
      final generation = _generation;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.confirmingNetwork,
          operationState: NetworkOperationState.apReady,
          canCancel: false,
          clearError: true,
        ),
      );
      unawaited(_confirmDirectAp(generation));
    }
  }

  void _onWifiScanBatch(WifiScanBatch batch) {
    if (state.phase != NetworkProvisioningPhase.scanningWifi || state.activeOperationId == null) {
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
    _scanBatches.clear();
    _expectedScanBatchCount = null;
    _scanCompleteSeen = false;
  }

  Future<void> _confirmDirectAp(int generation) async {
    await _confirmTerminalStatus(
      generation: generation,
      expectedMode: ProvisioningNetworkMode.directAp,
      expectedState: NetworkOperationState.apReady,
    );
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
  if (error is NetworkStatusConfirmationException || error is NetworkOperationFailedException) {
    return error;
  }
  return const NetworkOperationFailedException();
}
