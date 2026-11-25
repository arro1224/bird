import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_attempt.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cellular-only transport replaces a cancelled cold restore and recovers in foreground', () async {
    final h = _Harness();
    final oldResponse = Completer<DeviceStatus>();
    h.repository.handler = (call, _) => call == 1 ? oldResponse.future : Future.value(_status);
    final first = h.session.restoreSavedSession();
    await _until(() => h.repository.calls == 1);
    h.network.wifi = false;
    h.network.transport.add(null);
    expect(await first, false);
    await _until(() => h.session.state.isConnected);
    expect(h.repository.calls, 2);
    expect(h.repository.tokens.first.isCancelled, true);
    expect(h.session.state.device?.id, _device.id);
    final replacement = h.diagnostics.lastWhere((row) => row['event'] == 'connection_superseded');
    expect(replacement['cancel_source'], 'transport_changed');
    expect(replacement['successor_action'], 'verify_saved_session');
    expect(replacement['successor_attempt_id'], h.session.state.attemptId);
    oldResponse.complete(_status);
    await Future<void>.delayed(Duration.zero);
    expect(h.session.state.isConnected, true);
  });

  test('a saved local box can be verified without an OS default network', () async {
    final h = _Harness();
    h.network
      ..available = false
      ..wifi = false;
    expect(await h.session.restoreSavedSession(), true);
    expect(h.repository.calls, 1);
    expect(h.session.state.isConnected, true);
  });

  test('an unavailable connectivity hint does not prevent authenticated local verification', () async {
    final h = _Harness();
    h.network.hintError = StateError('OS hint unavailable');
    expect(await h.session.restoreSavedSession(), true);
    expect(h.repository.calls, 1);
  });

  test('network loss replaces the old attempt and a later network event recovers without lifecycle callbacks', () async {
    final h = _Harness();
    h.repository.handler = (_, _) => Completer<DeviceStatus>().future;
    final first = h.session.restoreSavedSession();
    await _until(() => h.repository.calls == 1);
    h.network.events.add(false);
    await _until(() => h.repository.calls == 2);
    expect(await first, false);
    h.repository.handler = null;
    h.network.events.add(true);
    await _until(() => h.session.state.isConnected);
    expect(h.repository.calls, 3);
    expect(h.repository.tokens.take(2).every((token) => token.isCancelled), true);
  });

  test('transport replacements share the original recovery deadline', () async {
    final h = _Harness();
    h.repository.handler = (_, _) => Completer<DeviceStatus>().future;
    final first = h.session.restoreSavedSession(timeout: const Duration(milliseconds: 160));
    await _until(() => h.repository.calls == 1);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      h.network.wifi = i.isOdd;
      h.network.transport.add(null);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await first, false);
    expect(h.session.state.phase, DeviceSessionPhase.disconnected);
    expect(h.session.activeAttemptId, isNull);
    expect(h.repository.tokens.every((token) => token.isCancelled), true);
    expect(h.diagnostics.where((row) => row['event'] == 'connection_deadline'), hasLength(1));
    final calls = h.repository.calls;
    h.network.transport.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.repository.calls, calls, reason: 'an unchanged signal must not restart an exhausted recovery');
  });

  test('repeated identical transport signals coalesce into one pending successor', () async {
    final h = _Harness();
    final pending = Completer<DeviceStatus>();
    h.repository.handler = (_, _) => pending.future;
    unawaited(h.session.restoreSavedSession());
    await _until(() => h.repository.calls == 1);
    h.network.wifi = false;
    h.network.transport.add(null);
    await _until(() => h.repository.calls == 2);
    for (var i = 0; i < 12; i++) {
      h.network.transport.add(null);
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(h.repository.calls, 2);
    pending.complete(_status);
    await _until(() => h.session.state.isConnected);
  });

  test('network handoff ends old recovery without leaving an orphaned spinner', () async {
    final h = _Harness();
    h.repository.handler = (_, _) => Completer<DeviceStatus>().future;
    final first = h.session.restoreSavedSession();
    await _until(() => h.repository.calls == 1);
    h.session.beginNetworkIntent('user-network-change');
    expect(await first, false);
    expect(h.session.state.isVerifying, false);
    expect(h.session.acceptsNetworkIntent('user-network-change'), true);
    expect(h.session.provisioningHandoffActive, true);
    h.session.endNetworkIntent('user-network-change');
    h.network.transport.add(null);
    await Future<void>.delayed(Duration.zero);
    // The next network event may verify the saved box; it must never revive
    // a cancelled system join or keep the released handoff as an owner.
    expect(h.session.provisioningHandoffActive, false);
  });

  test('manual connection supersedes cold restore and rejects its late success', () async {
    final h = _Harness();
    final late = Completer<DeviceStatus>();
    h.repository.handler = (_, _) => late.future;
    final first = h.session.restoreSavedSession();
    await _until(() => h.repository.calls == 1);
    h.session.connecting();
    expect(await first, false);
    expect(h.repository.tokens.single.isCancelled, true);
    late.complete(_status);
    await Future<void>.delayed(Duration.zero);
    expect(h.session.state.phase, DeviceSessionPhase.connecting);
    expect(h.session.activeAttemptId, isNull);
    h.session.disconnected('manual connection cancelled', false, 'user_cancel');
    expect(h.session.state.isVerifying, false);
    expect(h.diagnostics.lastWhere((row) => row['event'] == 'connection_invalidated')['cancel_source'], 'user_cancel');
  });

  test('missing saved metadata ends a seeded recovery state', () async {
    final h = _Harness();
    h.session.seedSavedDevice(_device);
    h.repository.saved = null;
    expect(await h.session.restoreSavedSession(), false);
    expect(h.session.state.isVerifying, false);
    expect(h.session.activeAttemptId, isNull);
    expect(h.session.state.attemptId, isNull);
  });

  test('cancelling the current token ends recovery and permits a fresh explicit retry', () async {
    final h = _Harness();
    h.repository.handler = (_, _) => Completer<DeviceStatus>().future;
    final first = h.session.restoreSavedSession();
    await _until(() => h.repository.calls == 1);
    h.repository.tokens.single.cancel('test cancellation');
    expect(await first, false);
    expect(h.session.state.isVerifying, false);
    expect(h.session.activeAttemptId, isNull);
    h.repository.handler = null;
    expect(await h.session.verifySavedSession(restart: true), true);
    expect(h.repository.calls, 2);
  });

  test('a stale OS transport read cannot undo explicit disconnect and forgetting the device', () async {
    final h = _Harness();
    await h.session.setConnectedFromStatus(_status);
    final hint = Completer<bool>();
    h.network.wifiRead = hint.future;
    h.network.transport.add(null);
    await Future<void>.delayed(Duration.zero);
    h.session.disconnected('user cancelled', true);
    hint.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(h.repository.calls, 0);
    expect(h.session.state.device, isNull);
    expect(h.session.state.isVerifying, false);
  });

  test('OS transport lookup cannot prolong an active recovery deadline', () async {
    final h = _Harness();
    h.repository.handler = (_, _) => Completer<DeviceStatus>().future;
    final first = h.session.restoreSavedSession(timeout: const Duration(milliseconds: 40));
    await _until(() => h.repository.calls == 1);
    final hint = Completer<bool>();
    h.network.wifiRead = hint.future;
    h.network.transport.add(null);
    expect(await first, false);
    expect(h.session.state.isVerifying, false);
    hint.complete(false);
    await Future<void>.delayed(Duration.zero);
  });

  test('an identity mismatch never becomes a connected local link', () async {
    final h = _Harness();
    h.network.wifi = false;
    h.repository.handler = (_, _) async => DeviceStatus(
      connection: DeviceConnection(id: 'other-box', name: 'Other', baseUri: _device.baseUri, networkMode: NetworkMode.infrastructureSta),
      card: const CardStatus(inserted: true),
    );
    expect(await h.session.restoreSavedSession(), false);
    expect(h.session.state.isConnected, false);
    expect(h.session.activeAttemptId, isNull);
  });
}

final _device = DeviceConnection(
  id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
  name: 'N10 test box',
  baseUri: Uri.parse('http://192.0.2.10:8080'),
  networkMode: NetworkMode.infrastructureSta,
  isPaired: true,
);
final _status = DeviceStatus(connection: _device, card: const CardStatus(inserted: true));

Future<void> _until(bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed > const Duration(milliseconds: 600)) fail('foreground recovery did not converge');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Harness {
  _Harness() {
    addTearDown(() async {
      await session.close();
      await network.events.close();
      await network.transport.close();
      await events.dispose();
      await refresh.dispose();
    });
  }

  final network = _Network();
  final repository = _Repository();
  final events = EventClient();
  final refresh = SessionRefreshCoordinator();
  final diagnostics = <Map<String, dynamic>>[];
  late final session = DeviceSessionCubit(
    repository,
    network,
    events,
    refresh,
    transportChanges: network.transport.stream,
    retryDelay: const Duration(milliseconds: 5),
    diagnostic: diagnostics.add,
  );
}

class _Network extends ConnectivityMonitor {
  bool wifi = true, available = true;
  Object? hintError;
  Future<bool>? wifiRead;
  final events = StreamController<bool>.broadcast();
  final transport = StreamController<void>.broadcast();
  @override
  Stream<bool> get onNetworkChanged => events.stream;
  @override
  Future<bool> get hasNetwork async {
    if (hintError != null) throw hintError!;
    return available;
  }

  @override
  Future<bool> get hasWifi async => wifiRead == null ? wifi : await wifiRead!;
}

class _Repository implements ConnectionRepository {
  DeviceConnection? saved = _device;
  Future<DeviceStatus> Function(int, CancelToken)? handler;
  final tokens = <CancelToken>[];
  int calls = 0;
  @override
  Future<DeviceConnection?> savedDevice() async => saved;
  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) {
    final token = cancelToken!;
    tokens.add(token);
    calls++;
    return ConnectionAttempt.runFor(token, 'identity', () => handler?.call(calls, token) ?? Future.value(_status));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
