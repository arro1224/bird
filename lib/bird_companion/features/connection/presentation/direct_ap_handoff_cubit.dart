import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum DirectApHandoffPhase { idle, waitingForPhoneApJoin, verifyingDirectApHttp, directApConnected, directApJoinTimeout, failure }

final class PendingDirectAp {
  const PendingDirectAp({required this.deviceId, required this.baseUri, required this.operationId, this.ssid});
  final String deviceId;
  final Uri baseUri;
  final String operationId;
  final String? ssid;
  ProvisioningCompletion get completion => ProvisioningCompletion(deviceId: deviceId, baseUri: baseUri, networkMode: ProvisioningNetworkMode.directAp);
  Map<String, dynamic> toJson() => {'device_id': deviceId, 'base_uri': baseUri.toString(), 'operation_id': operationId, 'ssid': ssid};
  factory PendingDirectAp.fromJson(Map json) {
    final uri = Uri.parse(json['base_uri'] as String);
    final id = json['device_id'] as String;
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(id) || !{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Invalid direct AP endpoint');
    }
    return PendingDirectAp(deviceId: id, baseUri: uri, operationId: json['operation_id'] as String, ssid: json['ssid'] as String?);
  }
}

final class DirectApHandoffState {
  const DirectApHandoffState({this.phase = DirectApHandoffPhase.idle, this.pending, this.attempt = 0, this.remainingSeconds = 90, this.message, this.firstError, this.lastError});
  final DirectApHandoffPhase phase;
  final PendingDirectAp? pending;
  final int attempt, remainingSeconds;
  final String? message;
  final String? firstError;
  final String? lastError;
  bool get active => pending != null && phase != DirectApHandoffPhase.idle;
  bool get canContinue => phase != DirectApHandoffPhase.failure || lastError == 'ProvisioningCredentialSaveException';
}

/// One cancellable HTTP handoff. It never issues a BLE or start_direct_ap command.
final class DirectApHandoffCubit extends Cubit<DirectApHandoffState> {
  DirectApHandoffCubit({required this.store, required this.verify, this.onCancel, this.activeChanged, this.window = const Duration(seconds: 90), this.retryUnit = const Duration(seconds: 1), this.diagnostic})
    : super(const DirectApHandoffState());
  static const pendingKey = 'connection:pending-direct-ap:v1';
  final DiagnosticStorage store;
  final Future<void> Function(PendingDirectAp, CancelToken) verify;
  final Future<void> Function(String deviceId)? onCancel;
  final void Function(bool active)? activeChanged;
  final void Function(Map<String, dynamic>)? diagnostic;
  final Duration window, retryUnit;
  CancelToken? _cancel;
  Timer? _deadlineTimer, _countdown;
  Timer? _retryTimer;
  Completer<void>? _wake;
  Future<void>? _running;
  int _generation = 0;
  bool _backgrounded = false;
  bool _initialized = false;
  Future<void> _writes = Future<void>.value();

  Future<void> _persist(Future<void> Function() operation) {
    _writes = _writes.catchError((Object _) {}).then((_) => operation());
    return _writes;
  }

  void _log(String type, [Map<String, dynamic> extra = const {}]) {
    diagnostic?.call({'event': type, 'phase': state.phase.name, 'occurred_at': DateTime.now().toUtc().toIso8601String(), ...?state.pending?.toJson(), 'attempt': state.attempt, ...extra});
  }

  Future<bool> restore() async {
    final raw = store.read<Map>(pendingKey);
    if (raw == null) return false;
    try {
      await begin(PendingDirectAp.fromJson(raw), restored: true);
      return true;
    } on FormatException {
      await store.remove(pendingKey);
      return false;
    } on TypeError {
      await store.remove(pendingKey);
      return false;
    }
  }

  Future<void> begin(PendingDirectAp pending, {bool restored = false}) async {
    if (isClosed || state.active) return;
    PendingDirectAp.fromJson(pending.toJson());
    final generation = ++_generation;
    _initialized = false;
    activeChanged?.call(true);
    emit(DirectApHandoffState(phase: DirectApHandoffPhase.waitingForPhoneApJoin, pending: pending));
    _log(restored ? 'direct_ap_pending_restored' : 'direct_ap_ready');
    try {
      await _persist(() => store.write(pendingKey, pending.toJson()));
      if (isClosed || generation != _generation) return;
      _initialized = true;
      unawaited(continueVerification());
    } catch (_) {
      if (!isClosed && generation == _generation) _emit(DirectApHandoffPhase.failure, message: '无法保存待完成连接，请返回后重试。');
    }
  }

  Future<void> continueVerification() {
    if (isClosed || !_initialized || !state.active || state.phase == DirectApHandoffPhase.directApConnected || !state.canContinue) return Future<void>.value();
    if (_running != null) {
      _wakeRetry();
      return _running!;
    }
    final generation = _generation;
    final future = _run(generation);
    _running = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_running, future)) _running = null;
      }),
    );
    return future;
  }

  void lifecycleChanged({required bool resumed}) {
    _backgrounded = !resumed;
    if (!state.active) return;
    _log(resumed ? 'direct_ap_app_resumed' : 'direct_ap_app_backgrounded');
    if (resumed && _automaticContinuationAllowed) unawaited(continueVerification());
  }

  void networkChanged() {
    if (state.active) {
      _log('direct_ap_network_changed');
      if (_automaticContinuationAllowed) unawaited(continueVerification());
    }
  }

  bool get _automaticContinuationAllowed => state.phase == DirectApHandoffPhase.waitingForPhoneApJoin || state.phase == DirectApHandoffPhase.verifyingDirectApHttp;

  Future<void> _run(int generation) async {
    final pending = state.pending!;
    final stopwatch = Stopwatch()..start();
    final token = CancelToken();
    _cancel = token;
    _emit(DirectApHandoffPhase.waitingForPhoneApJoin, remaining: window.inSeconds);
    final deadline = Timer(window, () {
      token.cancel('Direct AP join deadline');
      _wakeRetry();
    });
    _deadlineTimer = deadline;
    final countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed && generation == _generation) _emit(state.phase, remaining: ((window - stopwatch.elapsed).inMilliseconds / 1000).ceil().clamp(0, window.inSeconds));
    });
    _countdown = countdown;
    try {
      while (!isClosed && generation == _generation && !token.isCancelled && stopwatch.elapsed < window) {
        if (_backgrounded) {
          await _wait(retryUnit);
          continue;
        }
        _emit(DirectApHandoffPhase.verifyingDirectApHttp, attempt: state.attempt + 1);
        _log('direct_ap_http_attempt');
        try {
          await Future.any<void>([verify(pending, token), token.whenCancel.then<void>((error) => throw error)]);
          if (isClosed || generation != _generation) return;
          if (token.isCancelled) throw token.cancelError!;
          await _persist(() => store.remove(pendingKey));
          if (isClosed || generation != _generation || token.isCancelled) return;
          activeChanged?.call(false);
          _emit(DirectApHandoffPhase.directApConnected);
          _log('direct_ap_http_verified', {'device_id_verified': true});
          return;
        } catch (error) {
          if (isClosed || generation != _generation || token.isCancelled) break;
          final transient = isTransientDirectApError(error);
          final classification = directApErrorKind(error);
          _log('direct_ap_http_error', {'classification': classification, 'transient': transient, 'first_error': state.firstError ?? classification});
          if (!transient) {
            _emit(DirectApHandoffPhase.failure, message: directApErrorMessage(error), firstError: classification);
            return;
          }
          _emit(DirectApHandoffPhase.waitingForPhoneApJoin, message: '尚未连接到盒子热点。请在 WLAN 设置中连接后返回。', firstError: classification);
          _log('direct_ap_waiting_for_phone');
        }
        await _wait(retryUnit * state.attempt.clamp(1, 3));
      }
      if (!isClosed && generation == _generation) {
        _emit(DirectApHandoffPhase.directApJoinTimeout, remaining: 0, message: '等待手机连接热点超时，可连接后继续验证，无需重新配对。');
        _log('direct_ap_join_timeout');
      }
    } finally {
      deadline.cancel();
      countdown.cancel();
      if (generation == _generation) _wakeRetry();
      if (identical(_cancel, token)) _cancel = null;
    }
  }

  Future<void> _wait(Duration duration) {
    _wakeRetry();
    final wake = Completer<void>();
    _wake = wake;
    _retryTimer = Timer(duration, _wakeRetry);
    return wake.future;
  }

  void _wakeRetry() {
    _retryTimer?.cancel();
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void _emit(DirectApHandoffPhase phase, {int? attempt, int? remaining, String? message, String? firstError}) {
    emit(
      DirectApHandoffState(
        phase: phase,
        pending: state.pending,
        attempt: attempt ?? state.attempt,
        remainingSeconds: remaining ?? state.remainingSeconds,
        message: message,
        firstError: state.firstError ?? firstError,
        lastError: firstError ?? state.lastError,
      ),
    );
  }

  Future<void> cancel() async {
    final pending = state.pending;
    ++_generation;
    _cancel?.cancel('User left direct AP connection');
    _running = null;
    _deadlineTimer?.cancel();
    _countdown?.cancel();
    _wakeRetry();
    _log('direct_ap_cancelled');
    _initialized = false;
    activeChanged?.call(false);
    emit(const DirectApHandoffState());
    try {
      await _persist(() => store.remove(pendingKey));
    } catch (_) {
      _log('direct_ap_pending_clear_failed');
    }
    if (pending != null) await onCancel?.call(pending.deviceId);
  }

  @override
  Future<void> close() async {
    ++_generation;
    _cancel?.cancel('Direct AP view disposed');
    _deadlineTimer?.cancel();
    _countdown?.cancel();
    _wakeRetry();
    // Process/view disposal keeps pending metadata for a verified cold restore.
    await _writes.catchError((Object _) {});
    activeChanged?.call(false);
    return super.close();
  }
}

bool isTransientDirectApError(Object error) {
  if (error is TimeoutException || error is SocketException) return true;
  if (error is ApiException) return error.statusCode == null && error.cause is DioException && isTransientDirectApError(error.cause!);
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionError || DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout => true,
      DioExceptionType.unknown => error.error is SocketException,
      _ => false,
    };
  }
  return false;
}

String directApErrorKind(Object error) {
  if (error is ApiException && error.statusCode != null) return 'http_${error.statusCode}';
  if (error is ProvisioningException) return error.code.name;
  if (error is PairingRequiredException) return 'authorization_required';
  if (error is DioException) return error.type.name;
  return error.runtimeType.toString();
}

String directApErrorMessage(Object error) {
  if (error is ProvisioningException && error.code == ProvisioningErrorCode.deviceIdMismatch) return '设备身份不一致，已停止连接。';
  if (error is ProvisioningCredentialSaveException) return '授权已取得，但手机保存失败。可以继续验证以重试保存，不会再次兑换授权。';
  if (error is PairingRequiredException ||
      error is ProvisioningException &&
          {ProvisioningErrorCode.authorizationRequired, ProvisioningErrorCode.pairingSessionExpired, ProvisioningErrorCode.pairingSessionUsed, ProvisioningErrorCode.pairingSessionInvalid}.contains(error.code) ||
      error is ApiException && {401, 403}.contains(error.statusCode)) {
    return '盒子可达，但授权已失效。请重新安全授权，无需重新启动热点。';
  }
  return '盒子验证未通过，已停止自动重试。请查看连接诊断或返回。';
}
