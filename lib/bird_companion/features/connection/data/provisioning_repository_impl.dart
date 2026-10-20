import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'dart:async';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:dio/dio.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';

import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';

/// Production owner of rc4 identifiers, authorization, operation correlation,
/// Android routing and transient secret lifetime.
final class ProvisioningRepositoryImpl
    implements ProvisioningRepository, DppAvailabilityRepository, ProvisioningSessionRepository, ProvisioningNetworkStatusVerifier, BleScanDiagnosticsRepository, BleProvisioningControl, DirectApHttpPreparation {
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
    DirectApAuthorizationStore? directApAuthorizationStore,
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
    directApAuthorizationStore ?? MemoryDirectApAuthorizationStore(),
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
    this._directApAuthorizationStore,
  ) {
    _bleEventSubscription = _ble.events.asyncMap(_processBleEvent).where((event) => event != null).cast<ProvisioningEvent>().listen(_events.add, onError: _processBleError);
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
  final DirectApAuthorizationStore _directApAuthorizationStore;
  final Map<String, SessionCredential> _directApUnsavedCredentials = {};

  @override
  Future<void> cancelDirectApHttp(String deviceId) async {
    _directApUnsavedCredentials.remove(deviceId);
    await _directApAuthorizationStore.remove(deviceId);
  }

  Future<void> _saveDirectApAuthorization() async {
    final info = _requireDeviceInfo();
    final session = _pairingSession;
    if (session == null) return;
    await _directApAuthorizationStore.write(info.deviceId, {
      'device_id': info.deviceId,
      'client_id': _requireClientId(),
      'pairing_session_id': session.value,
      'expires_at': session.expiresAt.toUtc().toIso8601String(),
    });
  }

  Future<String?> directApPassphrase(String deviceId) async => (await _directApAuthorizationStore.load(deviceId))?['passphrase'] as String?;

  /// Called only after HTTP has verified the frozen BLE device identity.
  /// It deliberately survives BLE loss and never replays an uncertain redemption.
  @override
  Future<void> prepareDirectApHttp(ProvisioningCompletion completion, CancelToken cancelToken) async {
    cancelToken.throwIfCancellationRequested();
    final deviceId = completion.deviceId;
    final health = await _healthApi.read(completion.baseUri, cancellation: cancelToken);
    if (health.deviceId != deviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
    var credential = _directApUnsavedCredentials[deviceId] ?? await _credentialStore.read(deviceId);
    cancelToken.throwIfCancellationRequested();
    if (credential == null || !credential.isUsableAt(_clock())) {
      final pending = await _directApAuthorizationStore.load(deviceId);
      final expiresAt = DateTime.tryParse(pending?['expires_at'] as String? ?? '');
      if (pending == null || pending['device_id'] != deviceId || expiresAt == null || !expiresAt.isAfter(_clock().toUtc())) {
        await _directApAuthorizationStore.remove(deviceId);
        throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
      }
      cancelToken.throwIfCancellationRequested();
      // Consume durably before POST: a lost response may hide successful redemption.
      await _directApAuthorizationStore.remove(deviceId);
      _pairingSession = null;
      cancelToken.throwIfCancellationRequested();
      try {
        credential = await _pairingApi.exchangeSession(completion.baseUri, deviceId: deviceId, clientId: pending['client_id'] as String, pairingSessionId: pending['pairing_session_id'] as String, clock: _clock, cancelToken: cancelToken);
      } catch (_) {
        cancelToken.throwIfCancellationRequested();
        throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
      }
      _directApUnsavedCredentials[deviceId] = credential;
    }
    cancelToken.throwIfCancellationRequested();
    if (credential.deviceId != deviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
    final relocated = SessionCredential(deviceId: deviceId, baseUri: completion.baseUri, accessToken: credential.accessToken, expiresAt: credential.expiresAt, apiVersion: credential.apiVersion, clientId: credential.clientId);
    await _saveCredential(relocated);
    cancelToken.throwIfCancellationRequested();
    _directApUnsavedCredentials.remove(deviceId);
    if (_deviceInfo?.deviceId == deviceId) _credential = relocated;
    await _directApAuthorizationStore.remove(deviceId);
  }

  final StreamController<ProvisioningEvent> _events = StreamController<ProvisioningEvent>.broadcast(sync: true);
  final StreamController<void> _disconnects = StreamController<void>.broadcast(sync: true);
  final StreamController<List<WifiScanNetwork>> _wifiScanResults = StreamController<List<WifiScanNetwork>>.broadcast(sync: true);
  final Map<String, BleCommandType> _requestTypes = {};
  final Map<String, BleCommandType> _operations = {};
  final Map<String, String> _operationRequests = {};
  final Map<int, WifiScanBatch> _scanBatches = {};
  final Set<String> _activeDppLaunches = {};

  late final StreamSubscription<ProvisioningEvent> _bleEventSubscription;
  late final StreamSubscription<void> _disconnectSubscription;
  late final StreamSubscription<WifiNetworkLoss> _wifiLossSubscription;
  ProvisioningDeviceInfo? _deviceInfo;
  String? _clientId;
  SessionCredential? _credential;
  SessionCredential? _pendingCredential;
  int _connectionEpoch = 0;
  _TransientPairingSession? _pairingSession;
  int? _expectedScanBatchCount;
  bool _scanSawComplete = false;
  String? _activeScanRequestId;
  int _scanSequence = 0;
  bool _disposed = false;
  String? _lastTrustedDeviceId;
  bool _networkStatusResumeRequired = false;

  BleProvisioningControl? get _bleControl => _ble is BleProvisioningControl ? _ble as BleProvisioningControl : null;
  Object? _sessionOwner;
  @override
  Object claimSession() => _sessionOwner = _bleControl?.claimSession() ?? Object();
  @override
  bool ownsSession(Object owner) => !_disposed && identical(owner, _sessionOwner) && (_bleControl?.ownsSession(owner) ?? true);
  @override
  Future<void> endSession(Object owner) async {
    if (!ownsSession(owner)) return;
    final control = _bleControl;
    if (control != null) {
      await control.endSession(owner);
    } else {
      await _ble.stopScan();
      if (!ownsSession(owner)) return;
      await _ble.disconnect();
    }
    if (!identical(owner, _sessionOwner)) return;
    _clearTransientState();
    await _wifi.releaseNetwork();
  }

  @override
  Future<void> pauseDiscovery(Object owner) async {
    if (!ownsSession(owner)) return;
    final control = _bleControl;
    if (control != null) {
      await control.pauseDiscovery(owner);
    } else {
      await _ble.stopScan();
    }
  }

  @override
  Future<void> resumeDiscovery(Object owner) async {
    if (ownsSession(owner)) await _bleControl?.resumeDiscovery(owner);
  }

  @override
  Future<void> openLocationSettings(Object owner) async {
    if (!ownsSession(owner)) return;
    final control = _bleControl;
    if (control == null) throw const ProvisioningException(code: ProvisioningErrorCode.locationSettingsUnavailable, retryable: false);
    await control.openLocationSettings(owner);
  }

  @override
  Future<void> locationSettingsReturned(Object owner, {required bool enabled}) async {
    if (ownsSession(owner)) await _bleControl?.locationSettingsReturned(owner, enabled: enabled);
  }

  @override
  Future<BleScanEnvironment> readScanEnvironment() async => await _bleControl?.readScanEnvironment() ?? const BleScanEnvironment.unknown();
  @override
  Stream<BlePairingProgress> get pairingProgress => _bleControl?.pairingProgress ?? const Stream.empty();

  /// Final de-duplicated scan snapshots for B-owned selection pages.
  Stream<List<WifiScanNetwork>> get wifiScanResults => _wifiScanResults.stream;

  /// BLE disconnect is informational. It never sends a cancellation command.
  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Stream<BleScanDiagnosticSession> get scanDiagnostics {
    final ble = _ble;
    return ble is BleScanDiagnosticSource ? (ble as BleScanDiagnosticSource).scanDiagnostics : const Stream.empty();
  }

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
    final owner = _sessionOwner;
    await _ble.connect(device.advertisement);
    _checkOwner(owner);
    try {
      final info = await _ble.readDeviceInfo();
      await _ble.subscribeRequiredNotifications();
      final clientId = await _clientIdentityStore.readOrCreate();
      _checkOwner(owner);
      _deviceInfo = info;
      _clientId = clientId;
      final stored = await _credentialStore.read(info.deviceId);
      _checkOwner(owner);
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
      _checkOwner(owner);
      return info;
    } catch (_) {
      if (identical(owner, _sessionOwner)) await _ble.disconnect();
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
    await _saveDirectApAuthorization();
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
    _operations.clear();
    _operationRequests.clear();
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
    _registerOperation(accepted.operationId, type, event.requestId);
    _requestTypes.remove(event.requestId);
    return accepted;
  }

  void _registerOperation(String operationId, BleCommandType type, String requestId) {
    if (type != BleCommandType.scanWifi) _activeScanRequestId = null;
    _operations.clear();
    _operationRequests.clear();
    _operations[operationId] = type;
    _operationRequests[operationId] = requestId;
  }

  Future<ProvisioningEvent> _send(
    BleCommandType type, {
    Map<String, dynamic> payload = const {},
    String? requestId,
  }) async {
    final owner = _sessionOwner;
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
      // Transport/security recovery and the one permitted same-command retry
      // are owned by BirdBoxBleDataSource.writeCommand. Retrying the complete
      // command here would stack a second retry on top of that state machine
      // and could deliver open_pairing more than twice.
      final response = await _ble.writeCommand(request);
      _checkOwner(owner);
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
      _requestTypes.remove(request.requestId);
    }
  }

  void _checkOwner(Object? owner) {
    if (!identical(owner, _sessionOwner)) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true, diagnosticMessage: 'Superseded provisioning session');
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
    final credential = _pendingCredential ?? _credential;
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
      if (type == null) return null;
      _registerOperation(accepted.operationId, type, event.requestId);
      return event;
    }
    if (event.type == ProvisioningEventType.wifiScanResults) {
      if (event.requestId != _activeScanRequestId) return null;
      _acceptScanBatch(event.payload as WifiScanBatch);
      return event;
    }

    // Only explicit, request-correlated status reads may restore ownership.
    // Unsolicited snapshots must not revive a superseded operation.
    if (event.type == ProvisioningEventType.networkStatus) return null;

    final operationId = event.operationId;
    if (operationId != null && event.type != ProvisioningEventType.networkStatus && !_operations.containsKey(operationId)) {
      return null;
    }
    final expectedRequest = _operationRequests[operationId];
    if (expectedRequest != null && event.requestId != expectedRequest) return null;
    final epoch = _connectionEpoch;

    try {
      switch (event.payload) {
        case DirectApReady ready:
          // AP readiness is not phone WLAN readiness. Forward immediately; the
          // cancellable HTTP handoff owns waiting, manual join and authorization.
          await _saveDirectApAuthorization();
          final saved = await _directApAuthorizationStore.load(info.deviceId) ?? <String, dynamic>{};
          await _directApAuthorizationStore.write(info.deviceId, {...saved, 'ssid': ready.ssid, 'passphrase': ready.passphrase});
        case StaConnected connected:
          await _wifi.releaseNetwork();
          await _validateAndExchange(
            connected.baseUri,
            ProvisioningNetworkMode.infrastructureSta,
            operationId: connected.operationId,
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
    } catch (_) {
      if (epoch != _connectionEpoch || (operationId != null && !_operations.containsKey(operationId))) return null;
      rethrow;
    }
    if (epoch != _connectionEpoch || (operationId != null && !_operations.containsKey(operationId))) return null;
    if (operationId != null && event.terminal) {
      _operations.remove(operationId);
      _operationRequests.remove(operationId);
    }
    return event;
  }

  void _processBleError(Object error, StackTrace stack) {
    if (error is BleOperationFailure) {
      if (error.deviceId != _deviceInfo?.deviceId || !_operationRequests.containsValue(error.requestId)) return;
      _operationRequests.removeWhere((id, request) {
        if (request != error.requestId) return false;
        _operations.remove(id);
        return true;
      });
      _events.addError(error.error, stack);
      return;
    }
    _events.addError(error, stack);
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
    _activeScanRequestId = null;
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
    ProvisioningNetworkMode mode, {
    String? operationId,
  }) async {
    final info = _requireDeviceInfo();
    final epoch = _connectionEpoch;
    void checkConnection() {
      if (_disposed || epoch != _connectionEpoch || !identical(info, _deviceInfo) || (operationId != null && !_operations.containsKey(operationId))) {
        throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
      }
    }

    await _healthApi.waitForDevice(
      baseUri,
      expectedDeviceId: info.deviceId,
    );
    checkConnection();
    await _rememberDynamicAddress?.call(info.deviceId, baseUri, mode);
    checkConnection();
    final session = _pairingSession;
    if (session == null) {
      final credential = _pendingCredential ?? _credential;
      if (credential == null || !credential.isUsableAt(_clock())) {
        throw const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false);
      }
      final relocated = SessionCredential(
        deviceId: credential.deviceId,
        baseUri: baseUri,
        accessToken: credential.accessToken,
        expiresAt: credential.expiresAt,
        apiVersion: credential.apiVersion,
        clientId: credential.clientId,
      );
      await _saveCredential(relocated);
      checkConnection();
      _pendingCredential = null;
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
    // Once sent, a transport failure may hide a successful server redemption.
    // Require fresh application authorization instead of replaying a one-use session.
    _pairingSession = null;
    final SessionCredential credential;
    try {
      credential = await _pairingApi.exchangeSession(
        baseUri,
        deviceId: info.deviceId,
        clientId: _requireClientId(),
        pairingSessionId: session.value,
        clock: _clock,
      );
    } catch (error) {
      checkConnection();
      final code = error is ApiException ? error.code : null;
      final authorizationCode = switch (code) {
        'PAIRING_SESSION_EXPIRED' => ProvisioningErrorCode.pairingSessionExpired,
        'PAIRING_SESSION_USED' => ProvisioningErrorCode.pairingSessionUsed,
        'PAIRING_SESSION_INVALID' => ProvisioningErrorCode.pairingSessionInvalid,
        _ => ProvisioningErrorCode.authorizationRequired,
      };
      if (error is ProvisioningException) rethrow;
      throw ProvisioningException(code: authorizationCode, retryable: false, diagnosticMessage: 'HTTP session exchange failed: ${error.runtimeType}');
    }
    // HTTP success consumes the pairing session even if local persistence
    // subsequently fails, so it must never be reused.
    checkConnection();
    _pendingCredential = credential;
    await _saveCredential(credential);
    checkConnection();
    _pendingCredential = null;
    _credential = credential;
    await _sessionCoordinator?.activate(credential, persist: false);
  }

  Future<void> _saveCredential(SessionCredential credential) async {
    try {
      await _credentialStore.write(credential);
    } catch (_) {
      throw const ProvisioningCredentialSaveException();
    }
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
    _connectionEpoch++;
    _pairingSession = null;
    _operations.clear();
    _operationRequests.clear();
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
    _pendingCredential = null;
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
