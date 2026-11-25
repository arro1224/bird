import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble_peer_hint_store.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_profile_store.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_connection_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_attempt_failure.dart';
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
    implements
        ProvisioningRepository,
        DppAvailabilityRepository,
        ProvisioningSessionRepository,
        ReusableBleSession,
        ProvisioningNetworkStatusVerifier,
        BleScanDiagnosticsRepository,
        BleProvisioningControl,
        DirectApHttpPreparation,
        DirectApNetworkPreparation,
        SavedDirectApRecovery,
        BleControlRecovery,
        StoppedDirectApCleanup,
        ProvisioningHttpAuthorizationReadiness,
        ProvisioningEndpointSnapshot,
        BleFailureDiagnostics,
        BleSessionReleaseGuard {
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
    DirectApProfileStore? directApProfileStore,
    BlePeerHintStore? blePeerHintStore,
    Duration controlRecoveryTimeout = const Duration(seconds: 30),
    Duration controlScanTimeout = const Duration(seconds: 10),
    void Function(Map<String, dynamic>)? diagnostic,
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
    DirectApConnectionCoordinator(wifi, diagnostic: diagnostic),
    directApProfileStore ?? DirectApProfileStore(MemoryDirectApAuthorizationStore()),
    blePeerHintStore ?? BlePeerHintStore(MemoryDirectApAuthorizationStore()),
    controlRecoveryTimeout,
    controlScanTimeout,
    diagnostic,
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
    this.directApConnection,
    this._apProfiles,
    this._bleHints,
    this._controlRecoveryTimeout,
    this._controlScanTimeout,
    this._diagnostic,
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
  final DirectApConnectionCoordinator directApConnection;
  final DirectApProfileStore _apProfiles;
  final BlePeerHintStore _bleHints;
  final Duration _controlRecoveryTimeout, _controlScanTimeout;
  final void Function(Map<String, dynamic>)? _diagnostic;
  int _controlRecoverySequence = 0;
  CancelToken? _activeControlToken;
  final Map<String, ProvisioningDevice> _bleDevices = {};
  final _sessionChanges = StreamController<void>.broadcast();
  @override
  Stream<void> get sessionChanges => _sessionChanges.stream;
  final Map<String, String> _profileAttempts = {};
  final Set<String> _automaticJoinBlocked = {};
  Future<ProvisioningDeviceInfo>? _controlRecovery;
  String? _controlRecoveryDevice, _expectedRecoveryDevice;

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
  _DirectApNetworkConfiguration? _readyAp;
  String? _readyApDeviceId;

  @override
  Future<bool> prepareDirectApNetwork(ProvisioningCompletion completion, {required String operationId, required String attemptId, required CancelToken cancelToken, bool manualRescue = false}) async {
    cancelToken.throwIfCancellationRequested();
    _profileAttempts[completion.deviceId] = attemptId;
    if (_readyApDeviceId != completion.deviceId || _readyAp == null) {
      final stored = await _apProfiles.load(completion.deviceId);
      cancelToken.throwIfCancellationRequested();
      if (stored != null) _useProfile(stored);
    }
    final ready = _readyApDeviceId == completion.deviceId ? _readyAp : null;
    _profileAttempts[completion.deviceId] = attemptId;
    if (completion.networkMode != ProvisioningNetworkMode.directAp) return false;
    if (manualRescue || ready == null) {
      if (manualRescue) await directApConnection.release(reason: 'manual_rescue', intentId: attemptId);
      // Reuse a genuinely reachable current AP, not a cached SSID/approval.
      // This probe is public and sends no pairing material or bearer token.
      final health = await _healthApi.read(completion.baseUri, cancellation: cancelToken);
      cancelToken.throwIfCancellationRequested();
      if (health.deviceId != completion.deviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
      return manualRescue; // A manual switch must also rebuild old sockets.
    }
    if (_readyApDeviceId != completion.deviceId || ready.baseUri != completion.baseUri || (ready.operationId != operationId && !operationId.startsWith('existing-'))) throw const DirectApConfigurationUnavailable();
    await _apProfiles.setEnabled(completion.deviceId, true);
    cancelToken.throwIfCancellationRequested();
    final before = directApConnection.networkGeneration;
    await directApConnection.connect(deviceId: completion.deviceId, operationId: operationId, intentId: attemptId, ssid: ready.ssid, passphrase: ready.passphrase, security: ready.security, cancelToken: cancelToken);
    cancelToken.throwIfCancellationRequested();
    return before != directApConnection.networkGeneration;
  }

  @override
  void confirmDirectApNetwork(String attemptId) => directApConnection.markOnline(attemptId);

  @override
  Future<void> releaseDirectApNetwork(String attemptId, {required String reason}) async {
    final ids = _profileAttempts.entries.where((e) => e.value == attemptId).map((e) => e.key).toList();
    final release = directApConnection.release(reason: reason, intentId: attemptId);
    if (reason == 'cancelled') {
      for (final id in ids) {
        await _apProfiles.setEnabled(id, false);
        _automaticJoinBlocked.add(id);
      }
    }
    await release;
  }

  @override
  Future<void> selectDirectApDevice(String? deviceId) => directApConnection.selectDevice(deviceId);

  void _useProfile(DirectApProfile profile) {
    _readyApDeviceId = profile.deviceId;
    _readyAp = _DirectApNetworkConfiguration(profile.operationId, profile.ssid, profile.passphrase, profile.security, profile.baseUri);
  }

  @override
  Stream<void> get directApNetworkLosses => _wifi.networkLosses.map((_) {});

  @override
  Future<bool> restoreSavedDirectApNetwork(String deviceId, String attemptId, CancelToken token, {bool userInitiated = false}) async {
    token.throwIfCancellationRequested();
    _profileAttempts[deviceId] = attemptId;
    var profile = await _apProfiles.load(deviceId);
    token.throwIfCancellationRequested();
    if (!userInitiated && (_automaticJoinBlocked.contains(deviceId) || profile?.automaticRestore == false)) throw const DirectApRestoreSuspended();
    _profileAttempts[deviceId] = attemptId;
    if (userInitiated && (profile == null || !profile.automaticRestore || _automaticJoinBlocked.contains(deviceId))) {
      try {
        profile = await _refreshApProfile(deviceId, token);
      } catch (_) {
        if (_profileAttempts[deviceId] == attemptId) _automaticJoinBlocked.add(deviceId);
        rethrow;
      }
      if (profile == null) return true; // BLE confirmed that the box is on STA.
    }
    if (profile == null) throw const DirectApConfigurationUnavailable();
    _useProfile(profile);
    final before = directApConnection.networkGeneration;
    try {
      await directApConnection.connect(deviceId: deviceId, operationId: profile.operationId, intentId: attemptId, ssid: profile.ssid, passphrase: profile.passphrase, security: profile.security, cancelToken: token);
      token.throwIfCancellationRequested();
      await _rememberDynamicAddress?.call(deviceId, profile.baseUri, ProvisioningNetworkMode.directAp);
      token.throwIfCancellationRequested();
      if (userInitiated) await _apProfiles.setEnabled(deviceId, true);
      token.throwIfCancellationRequested();
      if (_profileAttempts[deviceId] == attemptId) _automaticJoinBlocked.remove(deviceId);
      return before != directApConnection.networkGeneration;
    } catch (error) {
      // onUnavailable may mean user denial. Do not issue another OS prompt
      // merely because a transport/foreground event arrives in this process.
      if (_profileAttempts[deviceId] == attemptId) {
        _automaticJoinBlocked.add(deviceId);
        if (error is ProvisioningException && error.code == ProvisioningErrorCode.userCancelledWifiDialog) await _apProfiles.setEnabled(deviceId, false);
      }
      rethrow;
    }
  }

  Future<DirectApProfile?> _refreshApProfile(String deviceId, CancelToken token) async {
    await recoverBleControl(deviceId, token);
    token.throwIfCancellationRequested();
    final status = await getNetworkStatus();
    token.throwIfCancellationRequested();
    if (status.busy) throw const ProvisioningException(code: ProvisioningErrorCode.networkOperationBusy, retryable: true);
    if (status.activeMode == ProvisioningNetworkMode.infrastructureSta && status.baseUri != null) {
      await directApConnection.release(reason: 'sta_confirmed', deviceId: deviceId);
      await _apProfiles.setEnabled(deviceId, false);
      await _rememberDynamicAddress?.call(deviceId, status.baseUri!, ProvisioningNetworkMode.infrastructureSta);
      return null;
    }
    // The existing authorized start command requests current AP configuration.
    // It is never retried automatically; firmware idempotence remains a real-
    // hardware gate. No new wire command or guessed password is introduced.
    String? operationId;
    final ready = Completer<void>();
    final subscription = events.listen(
      (event) {
        if (event.payload is DirectApReady && event.deviceId == deviceId && event.operationId == operationId && !ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    // Observe a possible early error even before the command is accepted.
    final observed = ready.future;
    unawaited(observed.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    var completed = false;
    try {
      final accepted = await startDirectAp();
      operationId = accepted.operationId;
      token.throwIfCancellationRequested();
      if (_readyApDeviceId != deviceId || _readyAp?.operationId != operationId) {
        await Future.any<void>([observed.timeout(const Duration(seconds: 20)), token.whenCancel.then<void>((e) => throw e)]);
      }
      token.throwIfCancellationRequested();
      final profile = await _apProfiles.load(deviceId);
      token.throwIfCancellationRequested();
      completed = true;
      return profile;
    } finally {
      if (!completed && operationId != null) {
        _operations.remove(operationId);
        _operationRequests.remove(operationId);
      }
      await subscription.cancel();
    }
  }

  @override
  Future<ProvisioningDeviceInfo> recoverBleControl(String deviceId, CancelToken cancelToken) {
    _checkNotDisposed();
    cancelToken.throwIfCancellationRequested();
    if (_controlRecovery != null) {
      if (_controlRecoveryDevice != deviceId) return Future.error(const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true));
      return Future.any([_controlRecovery!, cancelToken.whenCancel.then<ProvisioningDeviceInfo>((e) => throw e)]);
    }
    if (_deviceInfo != null && _ble.isConnected && !_connectActive && !sessionReleasePending && !sessionReleaseFailed) {
      if (_deviceInfo!.deviceId != deviceId) return Future.error(const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false));
      return Future.value(_deviceInfo!);
    }
    final future = _recoverBleControl(deviceId, cancelToken);
    _controlRecoveryDevice = deviceId;
    _controlRecovery = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_controlRecovery, future)) _controlRecovery = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_controlRecovery, future)) _controlRecovery = null;
        },
      ),
    );
    return future;
  }

  void _recordControl(Map<String, dynamic> event) {
    try {
      _diagnostic?.call(event);
    } catch (_) {
      /* Diagnostics cannot change recovery. */
    }
  }

  bool _retryableControlError(ProvisioningException error) =>
      error.retryable &&
      const {
        ProvisioningErrorCode.bleGattNotReady,
        ProvisioningErrorCode.bleGattOperationFailed,
        ProvisioningErrorCode.bleGattRecoveryFailed,
        ProvisioningErrorCode.bleCommandResponseTimeout,
      }.contains(error.code);

  Future<ProvisioningDeviceInfo> _recoverBleControl(String deviceId, CancelToken callerToken) async {
    if (_connectActive) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    if (_nativeSessionOwner == null || _bleControl?.ownsSession(_nativeSessionOwner!) == false) claimSession();
    final owner = _sessionOwner;
    final token = CancelToken();
    _activeControlToken = token;
    var active = true, timedOut = false, attempts = 0;
    final watch = Stopwatch()..start();
    final generation = ++_controlRecoverySequence;
    final recoveryId = 'ble-control-${SecureRequestIdFactory().create()}';
    void trace(String event, {String? source, String? outcome, String? code, int? count}) => _recordControl({
      'event': event,
      'device_id': deviceId,
      'attempt_id': recoveryId,
      'generation': generation,
      'candidate_source': source,
      'candidate_count': count,
      'attempt': attempts,
      'outcome': outcome,
      'error_code': code,
      'elapsed_ms': watch.elapsedMilliseconds,
      'timeout_ms': _controlRecoveryTimeout.inMilliseconds,
    });
    final deadline = Timer(_controlRecoveryTimeout, () {
      timedOut = true;
      token.cancel('BLE control recovery deadline');
    });
    unawaited(
      callerToken.whenCancel.then((error) {
        if (active) {
          final reason = error.error;
          if (reason is BleControlRecoveryException && reason.reason == BleControlRecoveryFailure.timeout) timedOut = true;
          token.cancel(error);
        }
      }),
    );
    unawaited(
      token.whenCancel.then((_) async {
        if (!active || !identical(_sessionOwner, owner)) return;
        _sessionOwner = Object(); // Reject late GATT and storage results.
        try {
          await _releaseSession();
        } catch (_) {
          /* Native release remains guarded. */
        }
      }),
    );
    Future<T> bounded<T>(Future<T> work) => Future.any([work, token.whenCancel.then<T>((error) => throw error)]);
    void check() {
      token.throwIfCancellationRequested();
      _checkOwner(owner);
    }

    trace('ble_control_recovery_started');
    try {
      check();
      BlePeerHint? hint;
      try {
        hint = await bounded(_bleHints.load(deviceId));
      } on DioException {
        rethrow;
      } catch (_) {
        trace('ble_control_hint_read_failed');
      }
      check();
      String? hintName = hint?.name;
      var candidate = _bleDevices[deviceId];
      var source = candidate == null ? 'stored_hint' : 'memory';
      if (candidate == null && hint?.platformId != null) {
        candidate = ProvisioningDevice(
          scanId: hint!.platformId!,
          advertisement: BirdBoxAdvertisement(localName: hint.name ?? '', serviceUuids: const [BleProtocolConstants.serviceUuid], rssi: 0, platformDeviceId: hint.platformId),
        );
      }
      if (candidate == null && hint == null) {
        // Read legacy AP transport hints only as a migration fallback. STA-only
        // devices do not need an AP profile to discover or recover BLE.
        DirectApProfile? legacy;
        try {
          legacy = await bounded(_apProfiles.load(deviceId));
        } on DioException {
          rethrow;
        } catch (_) {
          trace('ble_control_hint_read_failed');
        }
        check();
        hintName = legacy?.bleName;
        if (legacy?.blePlatformId != null) {
          source = 'legacy_ap_hint';
          candidate = ProvisioningDevice(
            scanId: legacy!.blePlatformId!,
            advertisement: BirdBoxAdvertisement(localName: legacy.bleName ?? '', serviceUuids: const [BleProtocolConstants.serviceUuid], rssi: 0, platformDeviceId: legacy.blePlatformId),
          );
        }
      }
      _expectedRecoveryDevice = deviceId;
      final tried = <String, int>{};
      ProvisioningException? lastError;
      Future<ProvisioningDeviceInfo> attempt(ProvisioningDevice device, String from) async {
        check();
        attempts++;
        tried.update(device.scanId, (value) => value + 1, ifAbsent: () => 1);
        trace('ble_control_candidate_connecting', source: from);
        final info = await bounded(connect(device));
        check();
        if (info.deviceId != deviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
        trace('ble_control_recovery_finished', source: from, outcome: 'connected');
        return info;
      }

      if (candidate != null) {
        try {
          return await attempt(candidate, source);
        } on ProvisioningException catch (error) {
          if (token.isCancelled || sessionReleaseFailed || (!_retryableControlError(error) && error.code != ProvisioningErrorCode.deviceIdMismatch)) rethrow;
          lastError = error;
          trace('ble_control_candidate_failed', source: source, code: error.code.wireValue);
        }
      }
      check();
      trace('ble_control_scan_started', source: 'scan');
      final candidates = <String, ProvisioningDevice>{};
      final completed = Completer<List<ProvisioningDevice>>();
      void finish() {
        if (!completed.isCompleted) completed.complete(candidates.values.toList());
      }

      final subscription = discoverDevices(timeout: _controlScanTimeout).listen(
        (device) {
          if (!device.advertisement.hasBirdBoxService) return;
          candidates[device.scanId] = device;
          if (candidates.length >= 16) finish();
        },
        onError: (Object error, StackTrace stack) {
          if (!completed.isCompleted) completed.completeError(error, stack);
        },
        onDone: finish,
      );
      final scanDeadline = Timer(_controlScanTimeout, finish);
      late final List<ProvisioningDevice> discovered;
      try {
        discovered = await bounded(completed.future);
      } finally {
        scanDeadline.cancel();
        await bounded(subscription.cancel());
        if (identical(_sessionOwner, owner)) await bounded(stopDiscovery());
      }
      check();
      trace('ble_control_scan_finished', source: 'scan', count: discovered.length);
      final expectedName = hintName ?? (deviceId.startsWith('bbx-') && deviceId.length >= 12 ? 'BirdBox-${deviceId.substring(4, 12).toUpperCase()}' : '');
      discovered.sort((a, b) {
        final preferredA = a.advertisement.localName == expectedName, preferredB = b.advertisement.localName == expectedName;
        if (preferredA != preferredB) return preferredA ? -1 : 1;
        return b.advertisement.rssi.compareTo(a.advertisement.rssi);
      });
      for (var index = 0; index < discovered.length && attempts < 3; index++) {
        final device = discovered[index];
        if ((tried[device.scanId] ?? 0) >= 2) continue;
        try {
          return await attempt(device, 'scan');
        } on ProvisioningException catch (error) {
          if (token.isCancelled || sessionReleaseFailed || (!_retryableControlError(error) && error.code != ProvisioningErrorCode.deviceIdMismatch)) rethrow;
          lastError = error;
          trace('ble_control_candidate_failed', source: 'scan', code: error.code.wireValue);
          if (_retryableControlError(error) && tried[device.scanId] == 1) discovered.add(device);
        }
      }
      if (lastError != null) throw lastError;
      throw const BleControlRecoveryException(BleControlRecoveryFailure.notFound);
    } catch (error) {
      final reported = timedOut ? const BleControlRecoveryException(BleControlRecoveryFailure.timeout) : error;
      trace(
        'ble_control_recovery_finished',
        outcome: timedOut
            ? 'timeout'
            : token.isCancelled
            ? 'cancelled'
            : 'failed',
        code: reported is ProvisioningException
            ? reported.code.wireValue
            : reported is BleControlRecoveryException
            ? reported.code
            : reported.runtimeType.toString(),
      );
      throw reported;
    } finally {
      active = false;
      deadline.cancel();
      _expectedRecoveryDevice = null;
      if (identical(_activeControlToken, token)) _activeControlToken = null;
    }
  }

  @override
  Future<bool> hasHttpAuthorization(String deviceId) async {
    final credential = _directApUnsavedCredentials[deviceId] ?? await _credentialStore.read(deviceId);
    if (credential != null && credential.deviceId == deviceId && credential.isUsableAt(_clock())) return true;
    final pending = await _directApAuthorizationStore.load(deviceId);
    final client = pending?['client_id'];
    final session = pending?['pairing_session_id'];
    final expires = pending?['expires_at'];
    return pending?['device_id'] == deviceId && client is String && isUuidV4(client) && session is String && session.isNotEmpty && expires is String && (DateTime.tryParse(expires)?.isAfter(_clock().toUtc()) ?? false);
  }

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
      cancelToken.throwIfCancellationRequested();
      _directApUnsavedCredentials[deviceId] = credential;
    }
    cancelToken.throwIfCancellationRequested();
    if (credential.deviceId != deviceId) throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
    final relocated = SessionCredential(deviceId: deviceId, baseUri: completion.baseUri, accessToken: credential.accessToken, expiresAt: credential.expiresAt, apiVersion: credential.apiVersion, clientId: credential.clientId);
    await _saveCredential(relocated, cancelToken: cancelToken);
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
  ProvisioningNetworkStatus? _lastNetworkSnapshot;
  @override
  ProvisioningNetworkStatus? get lastNetworkSnapshot => _deviceInfo == null ? null : _lastNetworkSnapshot;
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
  bool _connectActive = false;
  String? _lastTrustedDeviceId;
  bool _networkStatusResumeRequired = false;

  BleProvisioningControl? get _bleControl => _ble is BleProvisioningControl ? _ble as BleProvisioningControl : null;
  Object? _sessionOwner;
  Object? _nativeSessionOwner;
  Future<void>? _sessionRelease;
  ProvisioningException? _sessionReleaseError;
  @override
  bool get sessionReleasePending => _sessionRelease != null;
  @override
  bool get sessionReleaseFailed => _sessionReleaseError != null;
  @override
  Object claimSession() {
    // Do not invalidate the releasing native owner when a new page appears.
    if (!sessionReleasePending && !sessionReleaseFailed) _nativeSessionOwner = _bleControl?.claimSession();
    final owner = _sessionOwner = Object();
    _sessionChanges.add(null);
    return owner;
  }

  @override
  bool ownsSession(Object owner) => !_disposed && identical(owner, _sessionOwner) && (_nativeSessionOwner == null || (_bleControl?.ownsSession(_nativeSessionOwner!) ?? true));
  @override
  Future<void> endSession(Object owner) => ownsSession(owner) ? _releaseSession() : Future.value();

  Future<void> _releaseSession() {
    final pending = _sessionRelease;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _sessionRelease = completion.future;
    unawaited(
      _performSessionRelease().then(
        (_) {
          _sessionRelease = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          final failure = BleAttemptFailure(attemptId: 'session-release-$_connectionEpoch')..capture(error, stack, method: 'repository.endSession', expectedState: 'released', currentState: 'release_failed');
          _sessionReleaseError = failure.exception;
          _sessionRelease = null;
          completion.completeError(failure.exception, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _performSessionRelease() async {
    final control = _bleControl;
    final nativeOwner = _nativeSessionOwner;
    if (control != null && nativeOwner != null) {
      await control.endSession(nativeOwner);
    } else {
      await _ble.stopScan();
      await _ble.disconnect();
    }
    _clearTransientState();
    // BLE control lifetime is independent from the application Wi-Fi lease.
    _nativeSessionOwner = null;
    _sessionReleaseError = null;
  }

  @override
  Future<void> waitForSessionRelease() async {
    while (_sessionRelease != null) {
      await _sessionRelease;
    }
    if (_sessionReleaseError != null) throw _sessionReleaseError!;
    _checkNotDisposed();
    _nativeSessionOwner ??= _bleControl?.claimSession();
  }

  @override
  Future<void> pauseDiscovery(Object owner) async {
    if (!ownsSession(owner)) return;
    if (sessionReleasePending || sessionReleaseFailed) return;
    await waitForSessionRelease();
    if (!ownsSession(owner)) return;
    final control = _bleControl;
    if (control != null) {
      await control.pauseDiscovery(_nativeSessionOwner!);
    } else {
      await _ble.stopScan();
    }
  }

  @override
  Future<void> resumeDiscovery(Object owner) async {
    if (!ownsSession(owner) || sessionReleasePending || sessionReleaseFailed) return;
    await waitForSessionRelease();
    if (ownsSession(owner)) await _bleControl?.resumeDiscovery(_nativeSessionOwner!);
  }

  @override
  Future<void> openLocationSettings(Object owner) async {
    if (!ownsSession(owner)) return;
    final control = _bleControl;
    if (control == null) throw const ProvisioningException(code: ProvisioningErrorCode.locationSettingsUnavailable, retryable: false);
    await waitForSessionRelease();
    if (ownsSession(owner)) await control.openLocationSettings(_nativeSessionOwner!);
  }

  @override
  Future<void> locationSettingsReturned(Object owner, {required bool enabled}) async {
    if (!ownsSession(owner) || sessionReleasePending || sessionReleaseFailed) return;
    await waitForSessionRelease();
    if (ownsSession(owner)) await _bleControl?.locationSettingsReturned(_nativeSessionOwner!, enabled: enabled);
  }

  @override
  Future<BleScanEnvironment> readScanEnvironment() async => await _bleControl?.readScanEnvironment() ?? const BleScanEnvironment.unknown();
  @override
  Stream<BlePairingProgress> get pairingProgress => _bleControl?.pairingProgress ?? const Stream.empty();

  /// Final de-duplicated scan snapshots for B-owned selection pages.
  Stream<List<WifiScanNetwork>> get wifiScanResults => _wifiScanResults.stream;

  @override
  Future<void> recordFailureDetails(ProvisioningException error) async {
    final ble = _ble;
    if (ble is BleFailureDiagnostics) {
      try {
        await (ble as BleFailureDiagnostics).recordFailureDetails(error);
      } catch (_) {
        // Diagnostic persistence can never replace the operation failure.
      }
    }
  }

  /// BLE disconnect is informational. It never sends a cancellation command.
  @override
  Stream<void> get disconnects => _disconnects.stream;

  @override
  Stream<BleScanDiagnosticSession> get scanDiagnostics {
    final ble = _ble;
    return ble is BleScanDiagnosticSource ? (ble as BleScanDiagnosticSource).scanDiagnostics : const Stream.empty();
  }

  @override
  ProvisioningDeviceInfo? get connectedDeviceInfo => sessionReleasePending || sessionReleaseFailed ? null : _deviceInfo;

  @override
  Object? get observableSessionOwner {
    if (_disposed || sessionReleasePending || sessionReleaseFailed) return null;
    final control = _bleControl;
    if (control != null) return _nativeSessionOwner != null && control.ownsSession(_nativeSessionOwner!) ? _sessionOwner : null;
    return _deviceInfo != null && _ble.isConnected ? _sessionOwner : null;
  }

  @override
  ProvisioningDevice? get currentBleDevice {
    final info = connectedDeviceInfo;
    if (info == null || !_ble.isConnected || _connectActive || observableSessionOwner == null) return null;
    final candidate = _bleDevices[info.deviceId];
    return candidate == null ? null : ProvisioningDevice(scanId: candidate.scanId, advertisement: candidate.advertisement, deviceInfo: info);
  }

  @override
  bool get networkStatusResumeRequired => _networkStatusResumeRequired;

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) async* {
    _checkNotDisposed();
    final owner = _sessionOwner;
    await waitForSessionRelease();
    _checkOwner(owner);
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
    if (_connectActive) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
    _connectActive = true;
    var transportStarted = false;
    try {
      await waitForSessionRelease();
      _checkOwner(owner);
      final clientId = await _clientIdentityStore.readOrCreate();
      _checkOwner(owner);
      final ble = _ble;
      final ProvisioningDeviceInfo info;
      transportStarted = true;
      if (ble is BirdBoxPairingPreparation) {
        info = await (ble as BirdBoxPairingPreparation).prepareConnection(device.advertisement, clientId: clientId);
      } else {
        await ble.connect(device.advertisement);
        _checkOwner(owner);
        await ble.subscribeRequiredNotifications();
        info = await ble.readDeviceInfo();
        if (info.capabilities.pairingPreflightV1) throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
      }
      _checkOwner(owner);
      if (_expectedRecoveryDevice != null && _expectedRecoveryDevice != info.deviceId) {
        throw const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false);
      }
      if (_lastTrustedDeviceId != null && _lastTrustedDeviceId != info.deviceId) {
        await directApConnection.release(reason: 'device_changed');
        _readyAp = null;
        _readyApDeviceId = null;
        _checkOwner(owner);
      }
      _bleDevices[info.deviceId] = device;
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
      // Production preparation may leave native BOND_NONE waiting for the user.
      // The public read cannot implicitly enter get_network_status security setup.
      final status = reconnecting && ble is! BirdBoxPairingPreparation ? await _networkStatusAfterReconnect() : await _ble.readNetworkStatus();
      _lastNetworkSnapshot = status;
      _resumeOperation(status);
      _checkOwner(owner);
      try {
        await _bleHints.save(BlePeerHint(deviceId: info.deviceId, platformId: device.advertisement.platformDeviceId, name: device.advertisement.localName, verifiedAt: _clock()));
      } catch (_) {
        _recordControl({'event': 'ble_control_hint_save_failed', 'device_id': info.deviceId});
      }
      _checkOwner(owner);
      return info;
    } catch (error, stack) {
      final failure = BleAttemptFailure(attemptId: 'repository-connect-$_connectionEpoch')..capture(error, stack, method: 'repository.connect', expectedState: 'trusted', currentState: 'connecting');
      final releaseBlocked = _ble is BleNativeReleaseState && (_ble as BleNativeReleaseState).nativeReleaseBlocked;
      if (releaseBlocked && identical(owner, _sessionOwner)) _sessionReleaseError = failure.exception;
      if (!releaseBlocked && transportStarted && identical(owner, _sessionOwner)) {
        try {
          await _releaseSession();
        } catch (cleanupError, cleanupStack) {
          failure.capture(cleanupError, cleanupStack, method: 'repository.connect.disconnect', expectedState: 'gatt_closed', currentState: 'cleanup_failed');
        }
      }
      await recordFailureDetails(failure.exception);
      Error.throwWithStackTrace(failure.exception, stack);
    } finally {
      _connectActive = false;
      if (!_disposed) _sessionChanges.add(null);
    }
  }

  @override
  Future<void> disconnect() async {
    await _releaseSession();
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
    _lastNetworkSnapshot = status;
    if (!status.busy && _operations[status.operationId] == BleCommandType.stopDirectAp && status.activeMode != ProvisioningNetworkMode.directAp) {
      await confirmStoppedNetwork(_requireDeviceInfo().deviceId, status.operationId!);
    }
    _resumeOperation(status);
    return status;
  }

  @override
  Future<void> confirmStoppedNetwork(String deviceId, String operationId) async {
    final status = _lastNetworkSnapshot;
    if (_requireDeviceInfo().deviceId != deviceId || status == null || status.operationId != operationId || status.busy || status.activeMode == ProvisioningNetworkMode.directAp) {
      throw const ProvisioningProtocolException('network_status', 'stop is not confirmed by the current device');
    }
    _automaticJoinBlocked.add(deviceId);
    await _apProfiles.setEnabled(deviceId, false);
    await directApConnection.release(reason: 'stop_confirmed', deviceId: deviceId);
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
      await directApConnection.release(reason: 'network_mode_changed', force: true);
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
    if (sessionReleasePending || sessionReleaseFailed) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: true);
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
          // Retain this trusted configuration across BLE loss. The handoff
          // requests the system network before any HTTP identity/auth traffic.
          _readyAp = _DirectApNetworkConfiguration(ready.operationId, ready.ssid, ready.passphrase, ready.security, ready.baseUri);
          _readyApDeviceId = info.deviceId;
          final hint = _bleDevices[info.deviceId]?.advertisement;
          await _apProfiles.save(
            DirectApProfile(
              deviceId: info.deviceId,
              operationId: ready.operationId,
              ssid: ready.ssid,
              passphrase: ready.passphrase,
              security: ready.security,
              baseUri: ready.baseUri,
              blePlatformId: hint?.platformDeviceId,
              bleName: hint?.localName,
            ),
          );
          _automaticJoinBlocked.remove(info.deviceId);
          await _saveDirectApAuthorization();
          final saved = await _directApAuthorizationStore.load(info.deviceId) ?? <String, dynamic>{};
          await _directApAuthorizationStore.write(info.deviceId, {...saved, 'ssid': ready.ssid, 'passphrase': ready.passphrase, 'security': ready.security.wireValue});
        case StaConnected _:
          await directApConnection.release(reason: 'network_mode_changed', force: true);
          // Readiness is evidence, not a UI session. The shared HTTP handoff
          // verifies identity/auth and promotes the global session independently
          // of BLE lifetime. Do not establish WS here then fail a second BLE read.
          // Authorization was persisted at authorize_pairing. Do not require a
          // live BLE peer again after releasing phone routing: a disconnect may
          // already have cleared transient state. Presentation still checks its
          // own generation, trusted identity and operation before HTTP handoff.
          _operations.remove(operationId);
          _operationRequests.remove(operationId);
          return event;
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
          _automaticJoinBlocked.add(info.deviceId);
          await _apProfiles.setEnabled(info.deviceId, false);
          await directApConnection.release(reason: 'network_mode_changed', force: true);
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
        if (recovered.security == null) throw const ProvisioningProtocolException('network_recovered.security', 'is required for direct AP recovery');
        _readyApDeviceId = _requireDeviceInfo().deviceId;
        _readyAp = _DirectApNetworkConfiguration(recovered.operationId, ssid, passphrase, recovered.security!, baseUri);
        final hint = _bleDevices[_readyApDeviceId]?.advertisement;
        await _apProfiles.save(
          DirectApProfile(
            deviceId: _readyApDeviceId!,
            operationId: recovered.operationId,
            ssid: ssid,
            passphrase: passphrase,
            security: recovered.security!,
            baseUri: baseUri,
            automaticRestore: _operations[recovered.operationId] != BleCommandType.stopDirectAp,
            blePlatformId: hint?.platformDeviceId,
            bleName: hint?.localName,
          ),
        );
        await _joinAndValidateDirectApRecovery(
          ssid: ssid,
          passphrase: passphrase,
          baseUri: baseUri,
          security: recovered.security,
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
        await directApConnection.release(reason: 'network_mode_changed', force: true);
        if (_operations[recovered.operationId] == BleCommandType.stopDirectAp) {
          final deviceId = _requireDeviceInfo().deviceId;
          _automaticJoinBlocked.add(deviceId);
          await _apProfiles.setEnabled(deviceId, false);
          return; // The independent settings handoff verifies business reachability.
        }
        await _validateAndExchange(
          baseUri,
          ProvisioningNetworkMode.infrastructureSta,
        );
        return;
      case ProvisioningNetworkMode.none:
        await directApConnection.release(reason: 'network_mode_changed', force: true);
        return;
    }
  }

  Future<void> _joinAndValidateDirectApRecovery({
    required String ssid,
    required String passphrase,
    required Uri baseUri,
    required WifiSecurity? security,
  }) async {
    if (security == null) throw const ProvisioningProtocolException('network_recovered.security', 'is required for automatic direct AP recovery');
    final info = _requireDeviceInfo();
    final intentId = 'recovery:$_connectionEpoch:${_lastNetworkSnapshot?.operationId ?? "network"}';
    await directApConnection.connect(deviceId: info.deviceId, operationId: _lastNetworkSnapshot?.operationId ?? 'recovery', intentId: intentId, ssid: ssid, passphrase: passphrase, security: security, cancelToken: CancelToken());
    try {
      await _validateAndExchange(baseUri, ProvisioningNetworkMode.directAp);
      directApConnection.markOnline(intentId);
    } catch (_) {
      await directApConnection.release(reason: 'validation_failed', intentId: intentId);
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

  Future<void> _saveCredential(SessionCredential credential, {CancelToken? cancelToken}) async {
    cancelToken?.throwIfCancellationRequested();
    try {
      await _credentialStore.write(credential);
    } catch (_) {
      throw const ProvisioningCredentialSaveException();
    }
    cancelToken?.throwIfCancellationRequested();
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

  ProvisioningDeviceInfo _requireDeviceInfo() {
    _checkNotDisposed();
    final info = _deviceInfo;
    if (info == null) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattNotReady, retryable: true);
    return info;
  }

  String _requireClientId() {
    final clientId = _clientId;
    if (clientId == null) throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
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
    if (_disposed) throw const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _activeControlToken?.cancel('Provisioning repository disposed');
    await disconnect();
    _disposed = true;
    await _bleEventSubscription.cancel();
    await _disconnectSubscription.cancel();
    await _wifiLossSubscription.cancel();
    await directApConnection.dispose();
    await _wifi.dispose();
    await _clearDppTransientUri();
    await _ble.dispose();
    await _events.close();
    await _disconnects.close();
    await _sessionChanges.close();
    await _wifiScanResults.close();
  }
}

final class _TransientPairingSession {
  const _TransientPairingSession({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

/// Trusted current AP configuration, kept in memory only. No secret string output.
final class _DirectApNetworkConfiguration {
  const _DirectApNetworkConfiguration(this.operationId, this.ssid, this.passphrase, this.security, this.baseUri);
  final String operationId, ssid, passphrase;
  final WifiSecurity security;
  final Uri baseUri;
}
