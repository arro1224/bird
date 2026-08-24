import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
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
    Object? error,
    bool? canCancel,
    bool clearOperation = false,
    bool clearOperationState = false,
    bool clearNetworks = false,
    bool clearBaseUri = false,
    bool clearConfirmedMode = false,
    bool clearRecoveredMode = false,
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
  final Map<int, WifiScanBatch> _scanBatches = {};
  int? _expectedScanBatchCount;
  var _scanCompleteSeen = false;

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
          error: error,
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
          error: error,
          canCancel: false,
        ),
      );
    }
  }

  void backToMethodSelection() {
    _generation++;
    _clearScanAccumulator();
    emit(const NetworkProvisioningState());
  }

  void openWifiProvisioning(ProvisioningDeviceInfo info) {
    _generation++;
    _clearScanAccumulator();
    emit(
      NetworkProvisioningState(
        phase: info.capabilities.infrastructureSta ? NetworkProvisioningPhase.choosingWifiMethod : NetworkProvisioningPhase.methodUnavailable,
        trustedDeviceId: info.deviceId,
        capabilities: info.capabilities,
      ),
    );
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
          error: error,
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

  Future<void> submitStaConfiguration(
    StaNetworkConfiguration configuration,
  ) async {
    final capabilities = state.capabilities;
    final supported =
        capabilities?.infrastructureSta == true &&
        switch (configuration.selectionMethod) {
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
          error: error,
          clearOperation: true,
          canCancel: false,
        ),
      );
    }
  }

  Future<void> startDppProvisioning() async {
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
        canCancel: true,
      ),
    );
    try {
      final accepted = await _repository.startDppProvisioning();
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(activeOperationId: accepted.operationId));
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: error,
          clearOperation: true,
          canCancel: false,
        ),
      );
    }
  }

  Future<void> cancelActiveOperation() async {
    final operationId = state.activeOperationId;
    if (!state.canCancel || operationId == null) return;
    final generation = ++_generation;
    try {
      final accepted = await _repository.cancelNetworkOperation(operationId);
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          activeOperationId: accepted.operationId,
          canCancel: false,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.failure,
          error: error,
          canCancel: false,
        ),
      );
    }
  }

  void _onEvent(ProvisioningEvent event) {
    if (isClosed || event.deviceId != state.trustedDeviceId) return;
    final eventOperationId = event.operationId;
    if (eventOperationId != null && eventOperationId != state.activeOperationId) {
      return;
    }

    final payload = event.payload;
    if (payload is WifiScanBatch) {
      _onWifiScanBatch(payload);
      return;
    }
    if (payload is NetworkProgress) {
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
    if (payload is StaConnected && (state.phase == NetworkProvisioningPhase.configuringSta || state.phase == NetworkProvisioningPhase.preparingDpp)) {
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
      emit(
        state.copyWith(
          phase: NetworkProvisioningPhase.recovered,
          operationState: payload.operationState,
          recoveredMode: payload.recoveredMode,
          baseUri: payload.baseUri,
          canCancel: false,
          clearError: true,
        ),
      );
      return;
    }
    if (payload is CancelledOperation) {
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
        final current = strongestByBssid[network.bssid];
        if (current == null || network.rssiDbm > current.rssiDbm) {
          strongestByBssid[network.bssid] = network;
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
          error: error,
          clearBaseUri: true,
          canCancel: false,
        ),
      );
    }
  }

  void _onEventError(Object error, StackTrace stackTrace) {
    if (isClosed || state.trustedDeviceId == null) return;
    emit(
      state.copyWith(
        phase: NetworkProvisioningPhase.failure,
        error: error,
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
