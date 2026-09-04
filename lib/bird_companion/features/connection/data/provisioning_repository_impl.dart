import 'dart:async';

import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// Production owner of rc4 identifiers, authorization, operation correlation,
/// Android routing and transient secret lifetime.
final class ProvisioningRepositoryImpl implements ProvisioningRepository, DppAvailabilityRepository, ProvisioningSessionRepository, ProvisioningNetworkStatusVerifier {
  factory ProvisioningRepositoryImpl({
    required BirdBoxBleDataSource ble,
    required BirdBoxWifiPlatform wifi,
    required BirdBoxDppPlatform dpp,
    required ClientIdentityStore clientIdentityStore,
    required SecureSessionStore credentialStore,
    required HealthApi healthApi,
    required PairingApi pairingApi,
    SessionCoordinator? sessionCoordinator,
    Future<void> Function(
      String deviceId,
      Uri baseUri,
      ProvisioningNetworkMode mode,
    )?
    rememberDynamicAddress,
    RequestIdFactory? requestIds,
    DateTime Function()? clock,
  }) => ProvisioningRepositoryImpl._(
    ble,
    wifi,
    dpp,
    clientIdentityStore,
    credentialStore,
    healthApi,
    pairingApi,
    sessionCoordinator,
    rememberDynamicAddress,
    requestIds ?? SecureRequestIdFactory(),
    clock ?? DateTime.now,
  );

  ProvisioningRepositoryImpl._(
    this._ble,
    this._wifi,
    this._dpp,
    this._clientIdentityStore,
    this._credentialStore,
    this._healthApi,
    this._pairingApi,
    this._sessionCoordinator,
    this._rememberDynamicAddress,
    this._requestIds,
    this._clock,
  ) {
    _bleEventSubscription = _ble.events.asyncMap(_processBleEvent).where((event) => event != null).cast<ProvisioningEvent>().listen(_events.add, onError: _events.addError);
    _disconnectSubscription = _ble.disconnects.listen((_) {
      _clearTransientState();
      _disconnects.add(null);
    }, onError: _disconnects.addError);
    _wifiLossSubscription = _wifi.networkLosses.listen((loss) {
      scheduleMicrotask(() {
        if (_disposed) return;
        _events.addError(
          ProvisioningException(
            code: ProvisioningErrorCode.networkInternalError,
            retryable: true,
            diagnosticMessage: 'Android local-only Wi-Fi network was lost: ${loss.reason}',
          ),
        );
      });
    }, onError: _events.addError);
  }

  final BirdBoxBleDataSource _ble;
  final BirdBoxWifiPlatform _wifi;
  final BirdBoxDppPlatform _dpp;
  final ClientIdentityStore _clientIdentityStore;
  final SecureSessionStore _credentialStore;
  final HealthApi _healthApi;
  final PairingApi _pairingApi;
  final SessionCoordinator? _sessionCoordinator;
  final Future<void> Function(
    String deviceId,
    Uri baseUri,
    ProvisioningNetworkMode mode,
  )?
  _rememberDynamicAddress;
  final RequestIdFactory _requestIds;
  final DateTime Function() _clock;

  final StreamController<ProvisioningEvent> _events = StreamController<ProvisioningEvent>.broadcast(sync: true);
  final StreamController<void> _disconnects = StreamController<void>.broadcast(sync: true);
  final StreamController<List<WifiScanNetwork>> _wifiScanResults = StreamController<List<WifiScanNetwork>>.broadcast(sync: true);
  final Map<String, BleCommandType> _requestTypes = {};
  final Map<String, BleCommandType> _operations = {};
  final Map<int, WifiScanBatch> _scanBatches = {};
  final Set<String> _activeDppLaunches = {};

  late final StreamSubscription<ProvisioningEvent> _bleEventSubscription;
  late final StreamSubscription<void> _disconnectSubscription;
  late final StreamSubscription<WifiNetworkLoss> _wifiLossSubscription;
  ProvisioningDeviceInfo? _deviceInfo;
  String? _clientId;
  SessionCredential? _credential;
  _TransientPairingSession? _pairingSession;
  int? _expectedScanBatchCount;
  bool _scanSawComplete = false;
  String? _activeScanRequestId;
  int _scanSequence = 0;
  bool _disposed = false;
  String? _lastTrustedDeviceId;
  bool _networkStatusResumeRequired = false;

  /// Final de-duplicated scan snapshots for B-owned selection pages.
  Stream<List<WifiScanNetwork>> get wifiScanResults => _wifiScanResults.stream;

  /// BLE disconnect is informational. It never sends a cancellation command.
  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => _deviceInfo;

  @override
  bool get networkStatusResumeRequired => _networkStatusResumeRequired;

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) async* {
    _checkNotDisposed();
    await for (final advertisement in _ble.scan(timeout: timeout)) {
      final opaqueId = advertisement.platformDeviceId;
      yield ProvisioningDevice(
        scanId: opaqueId == null || opaqueId.isEmpty ? 'candidate-${_scanSequence++}' : opaqueId,
        advertisement: advertisement,
      );
    }
  }

  @override
  Future<void> stopDiscovery() => _ble.stopScan();

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device) async {
    _checkNotDisposed();
    await _ble.connect(device.advertisement);
    try {
      final info = await _ble.readDeviceInfo();
      await _ble.subscribeRequiredNotifications();
      final clientId = await _clientIdentityStore.readOrCreate();
      _deviceInfo = info;
      _clientId = clientId;
      final stored = await _credentialStore.read(info.deviceId);
      if (stored != null && stored.clientId == clientId && stored.isUsableAt(_clock())) {
        _credential = stored;
      } else {
        _credential = null;
        if (stored != null && !stored.isUsableAt(_clock())) {
          await _credentialStore.delete(info.deviceId);
        }
      }
      final reconnecting = _lastTrustedDeviceId == info.deviceId;
      _networkStatusResumeRequired = reconnecting;
      _lastTrustedDeviceId = info.deviceId;
      final status = reconnecting ? await _networkStatusAfterReconnect() : await _ble.readNetworkStatus();
      _resumeOperation(status);
      return info;
    } catch (_) {
      await _ble.disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _clearTransientState();
    await _wifi.releaseNetwork();
    await _ble.disconnect();
  }

  @override
  Stream<ProvisioningEvent> get events => _events.stream;

  @override
  Future<PairingWindow> openPairing() async {
    final event = await _send(BleCommandType.openPairing);
    if (event.type != ProvisioningEventType.pairingOpened || event.payload is! PairingWindow) {
      throw const ProvisioningProtocolException(
        'type',
        'open_pairing must return pairing_opened',
      );
    }
    return event.payload as PairingWindow;
  }

  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    final code = pairingCode.trim();
    if (code.isEmpty) {
      throw const ProvisioningProtocolException(
        'pairing_code',
        'must not be empty',
      );
    }
    final event = await _send(
      BleCommandType.authorizePairing,
      payload: {'pairing_code': code},
    );
    if (event.type != ProvisioningEventType.pairingAuthorized || event.payload is! PairingAuthorization) {
      throw const ProvisioningProtocolException(
        'type',
        'authorize_pairing must return pairing_authorized',
      );
    }
    final authorization = event.payload as PairingAuthorization;
    _pairingSession = _TransientPairingSession(
      value: authorization.pairingSessionId,
      expiresAt: _clock().toUtc().add(authorization.expiresIn),
    );
    return authorization;
  }

  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() async {
    final event = await _send(BleCommandType.getNetworkStatus);
    if (event.type != ProvisioningEventType.networkStatus || event.payload is! ProvisioningNetworkStatus) {
      throw const ProvisioningProtocolException(
        'type',
        'get_network_status must return network_status',
      );
    }
    final status = event.payload as ProvisioningNetworkStatus;
    _resumeOperation(status);
    return status;
  }

  @override
  Future<void> verifyNetworkStatus(ProvisioningNetworkStatus status) async {
    final baseUri = status.baseUri;
    final isTerminal =
        !status.busy &&
        ((status.activeMode == ProvisioningNetworkMode.directAp && status.operationState == NetworkOperationState.apReady) ||
            (status.activeMode == ProvisioningNetworkMode.infrastructureSta && status.operationState == NetworkOperationState.staConnected));
    if (!isTerminal || baseUri == null) {
      throw const ProvisioningProtocolException(
        'network_status',
        'cannot verify a non-terminal network status',
      );
    }
    if (status.activeMode == ProvisioningNetworkMode.infrastructureSta) {
      await _wifi.releaseNetwork();
    }
    await _validateAndExchange(baseUri, status.activeMode);
  }

  Future<ProvisioningNetworkStatus> _networkStatusAfterReconnect() async {
    try {
      return await getNetworkStatus();
    } on StateError {
      // A characteristic read is the safe compatibility fallback when an
      // older box cannot answer the explicit recovery command yet.
      return _ble.readNetworkStatus();
    } on ProvisioningException catch (error) {
      // Never mask a permanent protocol, identity, or authorization failure.
      if (!error.retryable) rethrow;
      return _ble.readNetworkStatus();
    }
  }

  void _resumeOperation(ProvisioningNetworkStatus status) {
    final operationId = status.operationId;
    if (operationId == null || !status.busy) return;
    _operations[operationId] = switch (status.operationState) {
      NetworkOperationState.stoppingAp => BleCommandType.stopDirectAp,
      NetworkOperationState.scanning || NetworkOperationState.scanComplete => BleCommandType.scanWifi,
      NetworkOperationState.preparingDpp || NetworkOperationState.waitingDppConfigurator || NetworkOperationState.dppAuthenticating || NetworkOperationState.dppConfigurationReceived => BleCommandType.startDppProvisioning,
      _ when status.desiredMode == ProvisioningNetworkMode.directAp => BleCommandType.startDirectAp,
      _ => BleCommandType.setStaConfig,
    };
  }

  @override
  Future<CommandAccepted> startDirectAp() => _startOperation(BleCommandType.startDirectAp);

  @override
  Future<CommandAccepted> stopDirectAp() => _startOperation(
    BleCommandType.stopDirectAp,
    payload: const {'restore_previous_sta': true},
  );

  @override
  Future<CommandAccepted> scanWifi() async {
    _scanBatches.clear();
    _expectedScanBatchCount = null;
    _scanSawComplete = false;
    final requestId = _requestIds.create();
    _activeScanRequestId = requestId;
    return _startOperation(BleCommandType.scanWifi, requestId: requestId);
  }

  @override
  Future<CommandAccepted> setStaConfig(
    StaNetworkConfiguration configuration,
  ) => _startOperation(
    BleCommandType.setStaConfig,
    payload: configuration.toProtocolJson(),
  );

  @override
  Future<DppAvailability> checkDppAvailability() async {
    final boxSupported = _requireDeviceInfo().capabilities.dppUsableByBox;
    var sessionReady = false;
    try {
      await _authorization();
      sessionReady = true;
    } catch (_) {
      // Capability probing is fail-closed. The command path will surface the
      // precise authorization error if it is invoked after state recovery.
    }
    if (!boxSupported || !sessionReady) {
      return DppAvailability.unavailable(boxSupported: boxSupported);
    }
    try {
      final phone = await _dpp.checkCapability();
      return DppAvailability(
        boxSupported: true,
        apiLevelSupported: phone.apiLevelSupported,
        easyConnectSupported: phone.easyConnectSupported,
        activityAvailable: phone.activityAvailable,
        sessionReady: true,
      );
    } catch (_) {
      return const DppAvailability.unavailable(boxSupported: true);
    }
  }

  @override
  Future<CommandAccepted> startDppProvisioning() async {
    final info = _requireDeviceInfo();
    if (!info.capabilities.dppUsableByBox) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.capabilityUnsupported,
        retryable: false,
      );
    }
    _requireDppCapability(await _dpp.checkCapability());
    return _startOperation(BleCommandType.startDppProvisioning);
  }

  @override
  Future<CommandAccepted> cancelNetworkOperation(String operationId) => _startOperation(
    BleCommandType.cancelNetworkOperation,
    payload: {'operation_id': operationId},
  );

  Future<CommandAccepted> _startOperation(
    BleCommandType type, {
    Map<String, dynamic> payload = const {},
    String? requestId,
  }) async {
    final authorization = await _authorization();
    final event = await _send(
      type,
      requestId: requestId,
      payload: {
        'authorization': authorization.toProtocolJson(),
        ...payload,
      },
    );
    if (event.type != ProvisioningEventType.commandAccepted || event.payload is! CommandAccepted) {
      throw ProvisioningProtocolException(
        'type',
        '${type.wireValue} must return command_accepted',
      );
    }
    final accepted = event.payload as CommandAccepted;
    _operations[accepted.operationId] = type;
    _requestTypes.remove(event.requestId);
    return accepted;
  }

  Future<ProvisioningEvent> _send(
    BleCommandType type, {
    Map<String, dynamic> payload = const {},
    String? requestId,
  }) async {
    final info = _requireDeviceInfo();
    final clientId = _requireClientId();
    final request = BleCommandRequest(
      type: type,
      requestId: requestId ?? _requestIds.create(),
      clientId: clientId,
      payload: payload,
    );
    _requestTypes[request.requestId] = type;
    try {
      ProvisioningEvent response;
      try {
        response = await _ble.writeCommand(request);
      } on ProvisioningException catch (error) {
        if (!error.retryable) rethrow;
        // The sole retry reuses the exact request object and request_id.
        response = await _ble.writeCommand(request);
      }
      if (response.deviceId != info.deviceId) {
        throw const ProvisioningException(
          code: ProvisioningErrorCode.deviceIdMismatch,
          retryable: false,
        );
      }
      if (response.requestId != request.requestId) {
        throw const ProvisioningProtocolException(
          'request_id',
          'response does not match the active request',
        );
      }
      return response;
    } finally {
      if (!_isAsynchronous(type)) _requestTypes.remove(request.requestId);
    }
  }

  Future<ProvisioningAuthorization> _authorization() async {
    final session = _pairingSession;
    if (session != null) {
      if (session.expiresAt.isAfter(_clock().toUtc())) {
        return ProvisioningAuthorization(
          type: ProvisioningAuthorizationType.pairingSession,
          value: session.value,
        );
      }
      _pairingSession = null;
    }
    final credential = _credential;
    if (credential != null && credential.isUsableAt(_clock())) {
      return ProvisioningAuthorization(
        type: ProvisioningAuthorizationType.bearerToken,
        value: credential.accessToken,
      );
    }
    throw const ProvisioningException(
      code: ProvisioningErrorCode.authorizationRequired,
      retryable: false,
    );
  }

  Future<ProvisioningEvent?> _processBleEvent(
    ProvisioningEvent event,
  ) async {
    final info = _deviceInfo;
    if (info == null) return null;
    if (event.deviceId != info.deviceId) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.deviceIdMismatch,
        retryable: false,
      );
    }
    if (event.payload is CommandAccepted) {
      final accepted = event.payload as CommandAccepted;
      final type = _requestTypes[event.requestId];
      if (type != null) {
        _operations[accepted.operationId] = type;
        _requestTypes.remove(event.requestId);
      }
      return event;
    }
    if (event.type == ProvisioningEventType.wifiScanResults) {
      if (event.requestId != _activeScanRequestId) return null;
      _acceptScanBatch(event.payload as WifiScanBatch);
      return event;
    }

    if (event.payload case final ProvisioningNetworkStatus status) {
      _resumeOperation(status);
    }

    final operationId = event.operationId;
    if (operationId != null && event.type != ProvisioningEventType.networkStatus && !_operations.containsKey(operationId)) {
      return null;
    }

    switch (event.payload) {
      case DirectApReady ready:
        await _joinAndValidateDirectAp(ready);
      case StaConnected connected:
        await _wifi.releaseNetwork();
        await _validateAndExchange(
          connected.baseUri,
          ProvisioningNetworkMode.infrastructureSta,
        );
      case DppBootstrapReady ready:
        if (_operations[ready.operationId] != BleCommandType.startDppProvisioning) {
          return null;
        }
        if (_activeDppLaunches.add(ready.operationId)) {
          unawaited(
            _launchDppSystemFlow(ready)
                .catchError((Object error, StackTrace stackTrace) {
                  if (!_disposed) _events.addError(error, stackTrace);
                })
                .whenComplete(
                  () => _activeDppLaunches.remove(ready.operationId),
                ),
          );
        }
      case NetworkRecovered recovered:
        await _applyRecovery(recovered);
      case DirectApStopped _:
        await _wifi.releaseNetwork();
      default:
        break;
    }
    if (operationId != null && event.terminal) {
      _operations.remove(operationId);
    }
    return event;
  }

  void _acceptScanBatch(WifiScanBatch batch) {
    final expected = _expectedScanBatchCount;
    if (expected != null && expected != batch.batchCount) {
      _scanBatches.clear();
      _expectedScanBatchCount = null;
      throw const ProvisioningProtocolException(
        'batch_count',
        'changed during Wi-Fi scan',
      );
    }
    _expectedScanBatchCount = batch.batchCount;
    _scanBatches[batch.batchIndex] = batch;
    _scanSawComplete = _scanSawComplete || batch.complete;
    if (!_scanSawComplete || _scanBatches.length != batch.batchCount) return;
    final networks = <String, WifiScanNetwork>{};
    for (var index = 0; index < batch.batchCount; index++) {
      final part = _scanBatches[index];
      if (part == null) return;
      for (final network in part.networks) {
        final key = '${network.ssid}\u0000${network.bssid.toUpperCase()}';
        final existing = networks[key];
        if (existing == null || network.rssiDbm > existing.rssiDbm) {
          networks[key] = network;
        }
      }
    }
    final sorted = networks.values.toList()..sort((left, right) => right.rssiDbm.compareTo(left.rssiDbm));
    _wifiScanResults.add(List.unmodifiable(sorted));
  }

  Future<void> _joinAndValidateDirectAp(DirectApReady ready) async {
    if (!await _wifi.ensurePermissions()) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.localNetworkPermissionDenied,
        retryable: false,
      );
    }
    final result = await _wifi.joinDirectAp(
      ssid: ready.ssid,
      passphrase: ready.passphrase,
    );
    if (!result.joined) throw _wifiJoinError(result.outcome);
    final network = result.network!;
    await _wifi.bindProcessToNetwork(network);
    try {
      await _validateAndExchange(
        ready.baseUri,
        ProvisioningNetworkMode.directAp,
      );
    } catch (_) {
      await _wifi.releaseNetwork();
      rethrow;
    }
  }

  Future<void> _applyRecovery(NetworkRecovered recovered) async {
    switch (recovered.recoveredMode) {
      case ProvisioningNetworkMode.directAp:
        final ssid = recovered.ssid;
        final passphrase = recovered.passphrase;
        final baseUri = recovered.baseUri;
        if (ssid == null || passphrase == null || baseUri == null) {
          throw const ProvisioningProtocolException(
            'network_recovered',
            'direct_ap recovery requires ssid, passphrase and base_uri',
          );
        }
        await _joinAndValidateDirectApRecovery(
          ssid: ssid,
          passphrase: passphrase,
          baseUri: baseUri,
        );
        return;
      case ProvisioningNetworkMode.infrastructureSta:
        final baseUri = recovered.baseUri;
        if (baseUri == null) {
          throw const ProvisioningProtocolException(
            'network_recovered.base_uri',
            'is required for infrastructure_sta recovery',
          );
        }
        await _wifi.releaseNetwork();
        await _validateAndExchange(
          baseUri,
          ProvisioningNetworkMode.infrastructureSta,
        );
        return;
      case ProvisioningNetworkMode.none:
        await _wifi.releaseNetwork();
        return;
    }
  }

  Future<void> _joinAndValidateDirectApRecovery({
    required String ssid,
    required String passphrase,
    required Uri baseUri,
  }) async {
    if (!await _wifi.ensurePermissions()) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.localNetworkPermissionDenied,
        retryable: false,
      );
    }
    final result = await _wifi.joinDirectAp(
      ssid: ssid,
      passphrase: passphrase,
    );
    if (!result.joined) throw _wifiJoinError(result.outcome);
    await _wifi.bindProcessToNetwork(result.network!);
    try {
      await _validateAndExchange(
        baseUri,
        ProvisioningNetworkMode.directAp,
      );
    } catch (_) {
      await _wifi.releaseNetwork();
      rethrow;
    }
  }

  Future<void> _validateAndExchange(
    Uri baseUri,
    ProvisioningNetworkMode mode,
  ) async {
    final info = _requireDeviceInfo();
    await _healthApi.waitForDevice(
      baseUri,
      expectedDeviceId: info.deviceId,
    );
    await _rememberDynamicAddress?.call(info.deviceId, baseUri, mode);
    final session = _pairingSession;
    if (session == null) {
      final credential = _credential;
      if (credential == null || !credential.isUsableAt(_clock())) return;
      final relocated = SessionCredential(
        deviceId: credential.deviceId,
        baseUri: baseUri,
        accessToken: credential.accessToken,
        expiresAt: credential.expiresAt,
        apiVersion: credential.apiVersion,
        clientId: credential.clientId,
      );
      await _credentialStore.write(relocated);
      _credential = relocated;
      await _sessionCoordinator?.activate(relocated, persist: false);
      return;
    }
    if (!session.expiresAt.isAfter(_clock().toUtc())) {
      _pairingSession = null;
      throw const ProvisioningException(
        code: ProvisioningErrorCode.pairingSessionExpired,
        retryable: false,
      );
    }
    final credential = await _pairingApi.exchangeSession(
      baseUri,
      deviceId: info.deviceId,
      clientId: _requireClientId(),
      pairingSessionId: session.value,
      clock: _clock,
    );
    // HTTP success consumes the pairing session even if local persistence
    // subsequently fails, so it must never be reused.
    _pairingSession = null;
    await _credentialStore.write(credential);
    _credential = credential;
    await _sessionCoordinator?.activate(credential, persist: false);
  }

  Future<void> _launchDppSystemFlow(DppBootstrapReady ready) async {
    try {
      _requireDppCapability(await _dpp.checkCapability());
      final result = await _dpp.launchEasyConnect(ready.dppUri);
      if (result.systemAccepted) return;
      await _cancelDppOperationBestEffort(ready.operationId);
      throw _dppLaunchError(result.outcome, result.systemResultCode);
    } finally {
      await _clearDppTransientUri();
    }
  }

  void _requireDppCapability(DppCapability capability) {
    if (!capability.apiLevelSupported || !capability.easyConnectSupported) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.phoneDppNotSupported,
        retryable: false,
      );
    }
    if (!capability.activityAvailable) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.systemDppActivityUnavailable,
        retryable: false,
      );
    }
  }

  Future<void> _cancelDppOperationBestEffort(String operationId) async {
    try {
      await cancelNetworkOperation(operationId);
    } catch (_) {
      // Preserve the local Easy Connect failure. The box will also expire its
      // short-lived bootstrap state, so cancellation failure is non-fatal here.
    }
  }

  ProvisioningException _dppLaunchError(
    DppLaunchOutcome outcome,
    String? systemResultCode,
  ) => ProvisioningException(
    code: switch (outcome) {
      DppLaunchOutcome.userCancelled => ProvisioningErrorCode.userCancelledDppDialog,
      DppLaunchOutcome.activityUnavailable => ProvisioningErrorCode.systemDppActivityUnavailable,
      DppLaunchOutcome.invalidUri => ProvisioningErrorCode.systemDppInvalidUri,
      DppLaunchOutcome.timedOut => ProvisioningErrorCode.dppTimeout,
      _ => ProvisioningErrorCode.systemDppFailed,
    },
    retryable: outcome == DppLaunchOutcome.failed,
    diagnosticMessage: systemResultCode == null ? null : 'Android Easy Connect result: $systemResultCode',
  );

  Future<void> _clearDppTransientUri() async {
    try {
      await _dpp.clearTransientUri();
    } catch (_) {
      // Secret cleanup is best effort across Flutter engine teardown. The
      // native channel also clears its reference on result and disposal.
    }
  }

  ProvisioningException _wifiJoinError(WifiJoinOutcome outcome) => ProvisioningException(
    code: switch (outcome) {
      WifiJoinOutcome.userCancelled => ProvisioningErrorCode.userCancelledWifiDialog,
      WifiJoinOutcome.deniedNoInternet => ProvisioningErrorCode.phoneRejectedNoInternetNetwork,
      WifiJoinOutcome.systemDenied => ProvisioningErrorCode.systemWifiJoinDenied,
      _ => ProvisioningErrorCode.networkSwitchFailed,
    },
    retryable: outcome == WifiJoinOutcome.failed,
  );

  ProvisioningDeviceInfo _requireDeviceInfo() {
    _checkNotDisposed();
    final info = _deviceInfo;
    if (info == null) throw StateError('No trusted BirdBox is connected');
    return info;
  }

  String _requireClientId() {
    final clientId = _clientId;
    if (clientId == null) throw StateError('Client identity is not loaded');
    return clientId;
  }

  void _clearTransientState() {
    _pairingSession = null;
    _operations.clear();
    _requestTypes.clear();
    _scanBatches.clear();
    _expectedScanBatchCount = null;
    _scanSawComplete = false;
    _activeScanRequestId = null;
    _activeDppLaunches.clear();
    unawaited(_clearDppTransientUri());
    _deviceInfo = null;
    _clientId = null;
    _credential = null;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Provisioning repository is disposed');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _bleEventSubscription.cancel();
    await _disconnectSubscription.cancel();
    await _wifiLossSubscription.cancel();
    await _wifi.dispose();
    await _clearDppTransientUri();
    await _ble.dispose();
    await _events.close();
    await _disconnects.close();
    await _wifiScanResults.close();
  }
}

final class _TransientPairingSession {
  const _TransientPairingSession({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

bool _isAsynchronous(BleCommandType type) => switch (type) {
  BleCommandType.startDirectAp || BleCommandType.stopDirectAp || BleCommandType.scanWifi || BleCommandType.setStaConfig || BleCommandType.startDppProvisioning || BleCommandType.cancelNetworkOperation => true,
  _ => false,
};
