import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'dart:async';
import 'package:aves/bird_companion/core/diagnostics/http_request_diagnostics.dart';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_attempt.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceSessionCubit extends Cubit<DeviceSessionState> {
  DeviceSessionCubit(
    this._repository,
    this._connectivityMonitor,
    this._eventClient,
    this._refreshCoordinator, {
    this.onConnectionRecovered,
    SessionCoordinator? sessionCoordinator,
    this.diagnostic,
    this.retryDelay = const Duration(seconds: 1),
    Stream<void>? transportChanges,
    Stream<void>? connectionFailures,
    Stream<ApiConnectionFailure>? connectionFailureDetails,
    this.probeReachability,
    this.prepareSavedNetwork,
    this.onSavedNetworkVerified,
    Stream<void>? directApLosses,
  }) : super(const DeviceSessionState()) {
    _directApLossSubscription = directApLosses?.listen(
      (_) {
        if (isClosed || provisioningHandoffActive || state.device?.networkMode != NetworkMode.directAp || _restoring != null) return;
        emit(state.copyWith(phase: DeviceSessionPhase.reconnecting, message: '盒子直连已断开，正在恢复原设备连接。'));
        _apLossRetry ??= Timer(retryDelay, () {
          _apLossRetry = null;
          if (!isClosed && !provisioningHandoffActive && state.device?.networkMode == NetworkMode.directAp) unawaited(verifySavedSession(intent: 'direct_ap_lost'));
        });
      },
      onError: (Object _, StackTrace _) {
        /* A malformed event is not evidence of network loss. */
      },
    );
    _requestFailureSubscription = connectionFailureDetails != null ? connectionFailureDetails.listen(reportUnreachable) : connectionFailures?.listen((_) => reportUnreachable());
    _networkSubscription = _connectivityMonitor.onNetworkChanged.listen(_onNetworkChanged);
    _transportSubscription = transportChanges?.listen((_) => unawaited(_onTransportChanged()));
    _eventSubscription = _eventClient.connectionStates.listen((eventState) {
      if (isClosed || !state.isConnected) return;
      switch (eventState) {
        case EventConnectionState.disconnected:
          emit(state.copyWith(message: _eventUnavailableMessage));
        case EventConnectionState.connected:
          if (state.message == _eventUnavailableMessage) emit(state.copyWith(clearMessage: true));
        case EventConnectionState.connecting:
        case EventConnectionState.reconnecting:
          break;
      }
    });
    _authenticationSubscription = sessionCoordinator?.authenticationFailures.listen((failure) {
      if (isClosed || sessionCoordinator.isCurrentAuthenticationFailure(failure) == false) return;
      final attempt = _activeAttempt;
      if (attempt != null) {
        attempt.record('connection_authentication_invalidated', {'final_trigger': 'authentication_failure'});
      } else {
        try {
          diagnostic?.call({'event': 'connection_authentication_invalidated', ...diagnosticContext, 'final_trigger': 'authentication_failure'});
        } catch (_) {}
      }
      _invalidateConnection(reason: 'authentication_failure');
      emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: '设备授权已失效，请重新配对。'));
    });
    _addressSubscription = sessionCoordinator?.addressChanges.listen((change) {
      final device = state.device;
      // Session activation is not yet protected-HTTP verification. Its address
      // may be used only when this intent finally commits.
      if (isClosed || !state.isConnected || device == null || device.id != change.deviceId || (_activeAttempt != null && !_activeAttempt!.committed)) return;
      if (device.baseUri != change.baseUri) _cancelReachabilityProbe();
      emit(
        state.copyWith(
          device: device.copyWith(baseUri: change.baseUri),
          lastUpdatedAt: DateTime.now(),
        ),
      );
      _refreshCoordinator.requestRefresh();
    });
  }

  final ConnectionRepository _repository;
  final ConnectivityMonitor _connectivityMonitor;
  final EventClient _eventClient;
  final SessionRefreshCoordinator _refreshCoordinator;
  final Future<void> Function()? onConnectionRecovered;
  final void Function(Map<String, dynamic>)? diagnostic;
  final Duration retryDelay;
  final Future<bool> Function(Uri baseUri, CancelToken cancelToken)? probeReachability;
  final Future<void> Function(DeviceConnection device, ConnectionAttempt attempt)? prepareSavedNetwork;
  final void Function(String attemptId)? onSavedNetworkVerified;
  StreamSubscription<void>? _directApLossSubscription;
  Timer? _apLossRetry;
  static const _reachabilityBudget = Duration(seconds: 3);
  CancelToken? _reachabilityProbe;
  String? _reachabilityCheckId;
  static const _eventUnavailableMessage = '实时事件连接暂不可用，页面会在刷新时读取最新状态。';
  late final StreamSubscription<bool> _networkSubscription;
  late final StreamSubscription<EventConnectionState> _eventSubscription;
  StreamSubscription<void>? _transportSubscription;
  StreamSubscription? _requestFailureSubscription;
  StreamSubscription<SessionAuthenticationFailure>? _authenticationSubscription;
  StreamSubscription<SessionAddressChange>? _addressSubscription;
  bool _legacyHandoffActive = false;
  final _handoffOwners = <Object>{};
  bool _networkIntentPending = false;
  String? _intentId;
  int _connectionGeneration = 0;
  ConnectionAttempt? _activeAttempt;
  Future<bool>? _restoring;
  _RecoveryBudget? _recoveryBudget;
  int _transportGeneration = 0;
  bool? _wifiAvailable;
  bool? _networkAvailable;

  bool get _acceptsTransport => !isClosed && !provisioningHandoffActive && state.device != null && state.phase != DeviceSessionPhase.connecting && _activeAttempt?.stage != 'direct_ap_restore';

  void _onNetworkChanged(bool available) {
    if (!_acceptsTransport) return;
    final changed = _networkAvailable != available;
    _networkAvailable = available;
    _recordTransport('network_changed', _wifiAvailable);
    if (!available || !state.isConnected) {
      _recoverAfterTransportChange('network_changed', changed: changed, unavailable: !available);
    }
  }

  Future<void> _onTransportChanged() async {
    if (!_acceptsTransport) return;
    final generation = ++_transportGeneration;
    final connectionGeneration = _connectionGeneration;
    bool? available;
    try {
      available = await _connectivityMonitor.hasWifi.timeout(const Duration(seconds: 2));
    } catch (_) {
      // A missing/stalled OS hint is not evidence that the local box is lost.
    }
    if (!_acceptsTransport || generation != _transportGeneration || connectionGeneration != _connectionGeneration) return;
    final changed = available != null && _wifiAvailable != available;
    _wifiAvailable = available;
    _recordTransport(available == null ? 'transport_check_unavailable' : 'transport_changed', available);
    _recoverAfterTransportChange('transport_changed', changed: changed, unavailable: available == false);
  }

  void _recoverAfterTransportChange(String source, {required bool changed, required bool unavailable}) {
    // Repeated OS notifications neither reset a deadline nor restart an
    // exhausted recovery. A real change or explicit user retry can try again.
    if (!changed && (_restoring == null && !state.isConnected || unavailable && state.isConnected)) return;
    if (unavailable) {
      emit(state.copyWith(phase: DeviceSessionPhase.reconnecting, message: '手机网络状态已变化，正在验证盒子的本地连接。'));
    }
    unawaited(
      _verifySavedSession(
        timeout: const Duration(seconds: 20),
        force: true,
        intent: source,
        restart: changed,
        continueBudget: true,
      ),
    );
  }

  String get _networkRole => state.device?.networkMode.wireValue == 'direct_ap'
      ? 'box_direct_ap'
      : _wifiAvailable == true
      ? 'wifi_client'
      : _wifiAvailable == false
      ? state.isConnected
            ? 'local_link_verified_without_wifi_client'
            : 'local_link_unconfirmed'
      : 'unknown';

  void _recordTransport(String event, bool? available) {
    final fields = {
      'event': event,
      'wifi_available': available,
      'has_network': _networkAvailable,
      'network_role': _networkRole,
      'network_mode': state.device?.networkMode.wireValue,
      'transport_generation': _transportGeneration,
      'generation': _connectionGeneration,
      'device_id': state.device?.id,
    };
    try {
      if (_activeAttempt != null) {
        _activeAttempt!.record(event, fields);
      } else {
        diagnostic?.call(fields);
      }
    } catch (_) {}
  }

  String? get activeAttemptId => _activeAttempt?.id ?? _intentId;
  Map<String, Object?> get diagnosticContext => {
    'generation': _connectionGeneration,
    'attempt_id': activeAttemptId,
    'phase': _activeAttempt?.stage ?? state.verificationStage,
    'device_id': state.device?.id,
    'connection_state': state.phase.name,
    'network_role': _networkRole,
    'network_mode': state.device?.networkMode.wireValue,
  };
  @override
  void onChange(Change<DeviceSessionState> change) {
    super.onChange(change);
    try {
      diagnostic?.call({
        'event': 'connection_state_changed',
        ...diagnosticContext,
        'previous_state': change.currentState.phase.name,
        'next_state': change.nextState.phase.name,
        'device_id': change.nextState.device?.id,
        'attempt_id': change.nextState.attemptId ?? activeAttemptId,
      });
    } catch (_) {}
  }

  bool get provisioningHandoffActive => _legacyHandoffActive || _handoffOwners.isNotEmpty || _networkIntentPending;
  set provisioningHandoffActive(bool value) {
    if (value && !_legacyHandoffActive) _invalidateConnection(reason: 'legacy_handoff', successorAction: 'network_handoff');
    _legacyHandoffActive = value;
  }

  void setHandoffActive(Object owner, bool value) {
    if (value) {
      if (_handoffOwners.add(owner)) _invalidateConnection(reason: 'handoff_claimed', successorAction: 'network_handoff', preserveIntent: true);
    } else {
      _handoffOwners.remove(owner);
    }
  }

  void beginNetworkIntent(String id) {
    if (isClosed || (_intentId == id && _networkIntentPending)) return;
    _invalidateConnection(reason: 'network_intent_started', successorAction: 'network_handoff', successorAttemptId: id);
    _intentId = id;
    _networkIntentPending = true;
  }

  void endNetworkIntent(String id) {
    if (_intentId != id) return;
    _networkIntentPending = false;
    if (!state.isConnected && _handoffOwners.isEmpty) {
      _invalidateConnection(reason: 'network_intent_ended');
    }
  }

  bool acceptsNetworkIntent(String id) => !isClosed && _intentId == id;

  void _invalidateConnection({required String reason, String successorAction = 'disconnected', String? successorAttemptId, bool preserveIntent = false}) {
    _cancelReachabilityProbe();
    _apLossRetry?.cancel();
    _apLossRetry = null;
    final previous = _activeAttempt;
    final fields = {
      'final_trigger': reason,
      'cancel_source': reason,
      'successor_action': successorAction,
      'previous_generation': _connectionGeneration,
      'next_generation': _connectionGeneration + 1,
      'successor_attempt_id': successorAttemptId,
      'network_role': _networkRole,
    };
    if (previous != null) {
      previous.record('connection_superseded', fields);
    } else {
      try {
        diagnostic?.call({'event': 'connection_invalidated', ...diagnosticContext, ...fields});
      } catch (_) {}
    }
    ++_connectionGeneration;
    ++_transportGeneration;
    previous?.token.cancel(reason);
    _activeAttempt = null;
    _restoring = null;
    _recoveryBudget = null;
    if (!preserveIntent) {
      _intentId = null;
      _networkIntentPending = false;
    }
    if (!isClosed && state.isVerifying && !{'verify_saved_session', 'connected', 'closed'}.contains(successorAction)) {
      emit(
        state.copyWith(
          phase: DeviceSessionPhase.disconnected,
          clearVerification: true,
          message: successorAction == 'network_handoff' ? '正在切换网络，连接验证由配网流程接管。' : '连接验证已结束。可重试原设备，当前内容为手机缓存。',
        ),
      );
    }
  }

  void _cancelReachabilityProbe() {
    if (_reachabilityProbe != null) {
      try {
        diagnostic?.call({'event': 'business_failure_probe_cancelled', 'reachability_check_id': _reachabilityCheckId, ...diagnosticContext});
      } catch (_) {}
    }
    _reachabilityProbe?.cancel('Device session changed');
    _reachabilityProbe = null;
    _reachabilityCheckId = null;
  }

  ConnectionAttempt _beginAttempt(String intent, {String? attemptId, String? deviceId, String? operationId, CancelToken? token}) {
    token?.throwIfCancellationRequested();
    final id = attemptId ?? SecureRequestIdFactory().create();
    _invalidateConnection(reason: intent, successorAction: 'verify_saved_session', successorAttemptId: id, preserveIntent: attemptId != null);
    final generation = _connectionGeneration;
    _intentId = id;
    final attempt = ConnectionAttempt(
      id: id,
      generation: generation,
      token: token ?? CancelToken(),
      deviceId: deviceId,
      operationId: operationId,
      isCurrent: () => !isClosed && generation == _connectionGeneration,
      diagnostic: diagnostic,
      intent: intent,
      onStage: (stage) {
        if (isClosed || generation != _connectionGeneration) return;
        final message = switch (stage) {
          'events' => '盒子已联网，正在验证实时连接。',
          'protected_http' => '盒子已联网，正在验证授权连接。',
          _ => '正在恢复并验证盒子连接，当前相册可能来自手机缓存。',
        };
        emit(state.copyWith(attemptId: id, operationId: operationId, verificationStage: stage, message: message));
      },
    );
    _activeAttempt = attempt;
    attempt.record('connection_intent_started', {'intent': intent});
    return attempt;
  }

  ConnectionAttempt beginEndpointVerification({required String attemptId, required String deviceId, required String operationId, required CancelToken token}) {
    token.throwIfCancellationRequested();
    if (!acceptsNetworkIntent(attemptId)) throw StateError('Network intent superseded');
    final active = _activeAttempt;
    if (active != null && identical(active.token, token) && active.id == attemptId) {
      active.check();
      return active;
    }
    final attempt = _beginAttempt('network_handoff', attemptId: attemptId, deviceId: deviceId, operationId: operationId, token: token);
    emit(state.copyWith(phase: DeviceSessionPhase.connecting, attemptId: attemptId, operationId: operationId, message: '盒子已联网，正在验证连接。'));
    return attempt;
  }

  void connecting() {
    if (isClosed) return;
    _invalidateConnection(reason: 'manual_connection_started', successorAction: 'network_handoff');
    emit(state.copyWith(phase: DeviceSessionPhase.connecting, clearMessage: true, clearVerification: true));
  }

  Future<void> connected(DeviceSessionState next) async {
    if (isClosed) return;
    _invalidateConnection(reason: 'verified_status_received', successorAction: 'connected');
    emit(next);
    _refreshCoordinator.requestRefresh();
    unawaited(_synchronizeAfterConnection());
  }

  Future<void> setConnectedFromStatus(DeviceStatus status, {ConnectionAttempt? attempt}) async {
    if (attempt == null) {
      await connected(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
      return;
    }
    attempt.check();
    if (attempt.deviceId != null && status.connection.id != attempt.deviceId) throw StateError('Verified device identity mismatch');
    attempt.committed = true;
    _restoring = null;
    _recoveryBudget = null;
    _networkIntentPending = false;
    attempt.record('connection_committed', {
      'http_result': 'protected_read_ok',
      'ws_state': _eventClient.currentState.name,
      'final_trigger': 'verified_session',
      'network_role': status.connection.networkMode.wireValue == 'direct_ap'
          ? 'box_direct_ap'
          : _wifiAvailable == false
          ? 'local_link_verified_without_wifi_client'
          : _networkRole,
    });
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now(), attemptId: attempt.id, operationId: attempt.operationId, verificationStage: 'connected'));
    _refreshCoordinator.requestRefresh();
    unawaited(_synchronizeAfterConnection());
  }

  /// One total budget includes cached-device lookup, connectivity, identity,
  /// secure credential restore, protected REST and the authenticated event gate.
  Future<bool> restoreSavedSession({Duration timeout = const Duration(seconds: 20)}) => _verifySavedSession(timeout: timeout, force: false, intent: 'cold_restore');

  /// Seed only public metadata before choosing the first page. Network work
  /// then runs while the saved album shell can display its recovery state.
  void seedSavedDevice(DeviceConnection device) {
    if (!isClosed && state.device == null) emit(DeviceSessionState(phase: DeviceSessionPhase.reconnecting, device: device, message: '正在恢复盒子连接，当前相册为手机缓存。'));
  }

  Future<bool> verifySavedSession({Duration timeout = const Duration(seconds: 20), String? expectedDeviceId, String intent = 'explicit_reconnect', bool restart = false}) {
    return _verifySavedSession(timeout: timeout, force: true, expectedDeviceId: expectedDeviceId, intent: intent, restart: restart);
  }

  Future<bool> _verifySavedSession({required Duration timeout, required bool force, required String intent, String? expectedDeviceId, bool restart = false, bool continueBudget = false}) {
    if (isClosed || provisioningHandoffActive) return Future<bool>.value(false);
    if (!force && state.isConnected) return Future<bool>.value(true);
    if (!restart && _restoring != null && (expectedDeviceId == null || _activeAttempt?.deviceId == expectedDeviceId)) {
      _activeAttempt?.record('connection_request_coalesced', {'intent': intent});
      return _restoring!;
    }
    final budget = continueBudget && _restoring != null ? _recoveryBudget ?? _RecoveryBudget(timeout) : _RecoveryBudget(timeout);
    final attempt = _beginAttempt(intent, deviceId: expectedDeviceId);
    _recoveryBudget = budget;
    final future = _restoreSavedSession(attempt, budget: budget, expectedDeviceId: expectedDeviceId);
    _restoring = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_restoring, future)) {
          _restoring = null;
          _recoveryBudget = null;
        }
      }),
    );
    return future;
  }

  Future<bool> _restoreSavedSession(ConnectionAttempt attempt, {required _RecoveryBudget budget, String? expectedDeviceId}) async {
    attempt.record('connection_budget', {'deadline_ms': budget.limit.inMilliseconds, 'recovery_elapsed_ms': budget.elapsed.elapsedMilliseconds});
    Timer? timer;
    void schedule() {
      timer?.cancel();
      final remaining = budget.limit - budget.elapsed.elapsed;
      timer = Timer(remaining > Duration.zero ? remaining : Duration.zero, () {
        if (attempt.isCurrent() && !attempt.committed) {
          attempt.record('connection_deadline', {'timeout_ms': budget.limit.inMilliseconds, 'recovery_elapsed_ms': budget.elapsed.elapsedMilliseconds, 'final_trigger': 'deadline', 'successor_action': 'disconnected'});
          attempt.token.cancel(TimeoutException('Connection verification deadline'));
        }
      });
    }

    schedule();
    try {
      return await Future.any<bool>([
        _runSavedVerification(
          attempt,
          expectedDeviceId: expectedDeviceId,
          onApPreparation: () {
            if (budget.limit < const Duration(seconds: 90)) budget.limit = const Duration(seconds: 90);
            attempt.record('direct_ap_restore_budget', {'deadline_ms': budget.limit.inMilliseconds});
            schedule();
          },
        ),
        attempt.token.whenCancel.then<bool>((error) => throw error),
      ]);
    } catch (error) {
      if (!isClosed && attempt.isCurrent() && !attempt.committed) {
        attempt.record('connection_failed', {
          'final_trigger': 'verification_failed',
          'cancel_source': attempt.token.isCancelled ? 'current_attempt_token' : 'verification_error',
          'successor_action': 'disconnected',
          'recovery_elapsed_ms': budget.elapsed.elapsedMilliseconds,
          ...ConnectionAttempt.errorFields(error),
        });
        final message = error is DirectApRestoreSuspended
            ? '自动直连已停止。可在确认后重试原设备，不会反复弹出系统连接请求。'
            : error is PairingRequiredException || error is ApiException && {401, 403}.contains(error.statusCode)
            ? '盒子可达，但手机授权已失效。请重新安全授权，无需重复配网。'
            : error is ProvisioningException && error.code == ProvisioningErrorCode.deviceIdMismatch
            ? '设备身份不一致，已停止恢复。当前内容为手机缓存。'
            : attempt.stage == 'events'
            ? '盒子已联网，但实时连接尚未验证完成。可继续验证，无需重复配网。'
            : '暂时无法验证盒子连接，可重试原设备。当前相册为手机缓存。';
        emit(state.copyWith(phase: DeviceSessionPhase.disconnected, attemptId: attempt.id, verificationStage: attempt.stage, message: message));
      }
      return false;
    } finally {
      timer?.cancel();
      if (attempt.isCurrent() && !attempt.committed) {
        _activeAttempt = null;
        _intentId = null;
        if (!attempt.token.isCancelled) attempt.token.cancel('Saved session verification finished');
        emit(
          state.copyWith(
            phase: DeviceSessionPhase.disconnected,
            clearVerification: true,
            message: state.isVerifying ? '暂时无法验证盒子连接，可重试原设备。当前内容为手机缓存。' : state.message,
          ),
        );
      }
    }
  }

  Future<bool> _runSavedVerification(ConnectionAttempt attempt, {String? expectedDeviceId, void Function()? onApPreparation}) async {
    final device = await attempt.run('saved_device', _repository.savedDevice);
    attempt.record('saved_device_loaded', {'saved_device_present': device != null, if (device != null) 'base_uri': device.baseUri.toString(), 'endpoint_source': 'saved'});
    if (device == null || (expectedDeviceId != null && device.id != expectedDeviceId)) {
      attempt.record('connection_not_restored', {'final_trigger': device == null ? 'no_saved_device' : 'saved_identity_mismatch'});
      return false;
    }
    attempt.deviceId = device.id;
    final wasConnected = state.isConnected && state.device?.id == device.id;
    if (!wasConnected) emit(DeviceSessionState(phase: DeviceSessionPhase.reconnecting, device: device, attemptId: attempt.id, verificationStage: 'connectivity', message: '正在恢复上次的盒子连接，当前相册为手机缓存。'));
    final localAp = device.networkMode == NetworkMode.directAp && prepareSavedNetwork != null;
    if (localAp) {
      onApPreparation?.call();
      await attempt.run('direct_ap_restore', () => prepareSavedNetwork!(device, attempt));
    }
    Future<bool?> networkHint() async {
      try {
        return await _connectivityMonitor.hasNetwork.timeout(const Duration(seconds: 2));
      } catch (error) {
        attempt.check();
        attempt.record('network_hint_unavailable', ConnectionAttempt.errorFields(error));
        return null;
      }
    }

    var hasNetwork = localAp ? true : await attempt.run('connectivity', networkHint);
    attempt.record('network_checked', {'has_network': hasNetwork});
    if (hasNetwork == false) {
      // The OS may briefly report none while Wi-Fi is settling after startup.
      await Future<void>.delayed(retryDelay);
      attempt.check();
      hasNetwork = await attempt.run('connectivity', networkHint);
      // A phone hosting the box's Wi-Fi may expose only cellular/none. The
      // saved local endpoint still gets authenticated verification within the
      // same budget; OS connectivity alone never establishes a session.
      attempt.record('local_link_verification', {'has_network': hasNetwork, 'network_role': _networkRole});
    }
    var retries = 0;
    while (true) {
      attempt.check();
      try {
        final status = await _repository.reconnect(cancelToken: attempt.token);
        attempt.check();
        await setConnectedFromStatus(status, attempt: attempt);
        if (localAp) onSavedNetworkVerified?.call(attempt.id);
        return true;
      } catch (error) {
        attempt.check();
        if (wasConnected && error is EventSessionNotReadyException) {
          attempt.committed = true;
          emit(state.copyWith(message: _eventUnavailableMessage));
          attempt.record('connection_kept', {'http_result': 'protected_read_ok', 'ws_state': _eventClient.currentState.name, 'final_trigger': 'events_degraded'});
          return true;
        }
        final retryable =
            error is EventSessionNotReadyException ||
            error is TimeoutException ||
            (error is ApiException && error.retryable && !{401, 403}.contains(error.statusCode)) ||
            (error is DioException && error.type != DioExceptionType.badResponse);
        if (!retryable) rethrow;
        if (error is EventSessionNotReadyException) {
          attempt.stage = 'events';
          emit(state.copyWith(message: '盒子已联网，正在验证实时连接。', verificationStage: 'events'));
        }
        final delay = retryDelay * (1 << (retries < 3 ? retries : 3));
        retries++;
        attempt.record('connection_retry_wait', {'attempt': retries, 'retry_delay_ms': delay.inMilliseconds, ...ConnectionAttempt.errorFields(error)});
        await Future.any([Future<void>.delayed(delay), attempt.token.whenCancel]);
      }
    }
  }

  Future<void> _synchronizeAfterConnection() async {
    final generation = _connectionGeneration;
    try {
      await onConnectionRecovered?.call();
      if (!isClosed && generation == _connectionGeneration && state.isConnected) _refreshCoordinator.requestRefresh();
    } catch (_) {
      if (!isClosed && generation == _connectionGeneration) emit(state.copyWith(message: '已连接盒子，手机上保存的修改会自动传回盒子。'));
    }
  }

  @Deprecated('Use setConnectedFromStatus so refresh and offline synchronization are also performed.')
  void setConnectedFromStatusWithoutRecovery(dynamic status) {
    emit(DeviceSessionState(phase: DeviceSessionPhase.connected, device: status.connection, lastUpdatedAt: DateTime.now()));
  }

  Future<void> reconnect() async {
    if (isClosed || provisioningHandoffActive || state.device == null) return;
    await verifySavedSession();
  }

  /// A page error stays local unless a separate, bounded probe fails.
  /// Actual Wi-Fi loss still enters recovery immediately via transport events.
  void reportUnreachable([Object? error]) {
    final device = state.device;
    final probe = probeReachability;
    if (isClosed || provisioningHandoffActive || !state.isConnected || device == null || probe == null) {
      return;
    }
    final failure = error is ApiConnectionFailure ? error : null;
    if (_reachabilityProbe != null) {
      try {
        diagnostic?.call({'event': 'business_failure_probe_coalesced', 'cause_request_id': failure?.requestId, 'reachability_check_id': _reachabilityCheckId, ...diagnosticContext});
      } catch (_) {}
      return;
    }
    final token = _reachabilityProbe = CancelToken();
    final checkId = _reachabilityCheckId = SecureRequestIdFactory().create();
    try {
      diagnostic?.call({'event': 'business_failure_probe_started', 'cause_request_id': failure?.requestId, 'reachability_check_id': checkId, ...diagnosticContext});
    } catch (_) {}
    unawaited(_checkReachability(device, probe, token, failure, checkId));
  }

  Future<void> _checkReachability(
    DeviceConnection device,
    Future<bool> Function(Uri, CancelToken) probe,
    CancelToken token,
    ApiConnectionFailure? failure,
    String checkId,
  ) async {
    final clock = Stopwatch()..start();
    try {
      final reachable = await probe(device.baseUri, token).timeout(_reachabilityBudget, onTimeout: () => false);
      if (isClosed || provisioningHandoffActive || !state.isConnected || !identical(_reachabilityProbe, token) || state.device?.id != device.id || state.device?.baseUri != device.baseUri) {
        return;
      }
      try {
        diagnostic?.call({
          'event': 'business_failure_reachability_checked',
          'reachability_check_id': checkId,
          'cause_request_id': failure?.requestId,
          'probe_request_id': HttpRequestDiagnostics.requestId(token.requestOptions),
          'route': failure?.route,
          'error_class': failure?.errorType,
          'device_id': device.id,
          'generation': _connectionGeneration,
          'elapsed_ms': clock.elapsedMilliseconds,
          'outcome': reachable ? 'reachable' : 'unreachable',
          'timeout_ms': _reachabilityBudget.inMilliseconds,
        });
      } catch (_) {
        // Diagnostics must not affect the connection decision.
      }
      if (reachable) return;
    } catch (_) {
      // An unexpected or cancelled probe is not proof of a network failure.
      return;
    } finally {
      if (identical(_reachabilityProbe, token)) {
        _reachabilityProbe = null;
        _reachabilityCheckId = null;
      }
      token.cancel('Reachability probe finished');
    }
    try {
      diagnostic?.call({
        'event': 'business_failure_recovery_started',
        'reachability_check_id': checkId,
        'cause_request_id': failure?.requestId,
        'probe_request_id': HttpRequestDiagnostics.requestId(token.requestOptions),
        ...diagnosticContext,
      });
    } catch (_) {}
    emit(state.copyWith(phase: DeviceSessionPhase.reconnecting, message: '盒子连接暂时不可用，正在恢复…'));
    unawaited(verifySavedSession(intent: 'page_reported_unreachable'));
  }

  void disconnected([String? message, bool clearDevice = false, String source = 'explicit_disconnect']) {
    _invalidateConnection(reason: source, preserveIntent: provisioningHandoffActive);
    if (!isClosed) emit(state.copyWith(phase: DeviceSessionPhase.disconnected, message: message, clearMessage: message == null, clearDevice: clearDevice, clearVerification: true));
  }

  @override
  Future<void> close() async {
    _invalidateConnection(reason: 'session_closed', successorAction: 'closed');
    _apLossRetry?.cancel();
    await _directApLossSubscription?.cancel();
    await _networkSubscription.cancel();
    await _transportSubscription?.cancel();
    await _requestFailureSubscription?.cancel();
    await _eventSubscription.cancel();
    await _authenticationSubscription?.cancel();
    await _addressSubscription?.cancel();
    return super.close();
  }
}

/// Transport replacements during an active recovery share this clock. AP
/// preparation retains its existing 90-second system window.
class _RecoveryBudget {
  _RecoveryBudget(this.limit);
  Duration limit;
  final elapsed = Stopwatch()..start();
}
