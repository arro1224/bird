import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/copy/data/active_copy_job_store.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_recovery.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'direct_ap_handoff_test.dart' show MemoryHandoffStorage, until;

void main() {
  test('handoff deadline ends the global verifying phase and continue verifies the same intent', () async {
    final session = _session(_Repository());
    const id = 'handoff';
    final owner = Object(), late = Completer<void>();
    var calls = 0;
    session.beginNetworkIntent(id);
    final handoff = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      window: const Duration(milliseconds: 45),
      activeChanged: (active) {
        session.setHandoffActive(owner, active);
        if (!active) session.endNetworkIntent(id);
      },
      isIntentCurrent: (pending) => session.acceptsNetworkIntent(pending.attemptId!),
      onVerificationStopped: session.disconnected,
      verify: (pending, token) async {
        final ticket = session.beginEndpointVerification(attemptId: id, deviceId: _device.id, operationId: pending.operationId, token: token);
        if (++calls == 1) await late.future;
        await session.setConnectedFromStatus(_status, attempt: ticket);
      },
    );
    await handoff.begin(PendingDirectAp(deviceId: _device.id, baseUri: _device.baseUri, operationId: 'op', attemptId: id));
    await until(() => handoff.state.phase == DirectApHandoffPhase.directApJoinTimeout);
    expect(session.state.isVerifying, false);
    expect(session.acceptsNetworkIntent(id), true);
    await handoff.continueVerification();
    expect(handoff.state.phase, DirectApHandoffPhase.directApConnected);
    expect(session.state.isConnected, true);
    late.complete();
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, true);
    await handoff.close();
  });

  test('a restored trusted session refreshes the original copy id without creating another task', () async {
    final events = EventClient(), refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(_Repository(), _Network(), events, refresh);
    final store = ActiveCopyJobStore.memory();
    await store.remember(_device.id, 'original-job', CopyJobState.running);
    await store.remember('other-box', 'other-job', CopyJobState.running);
    final repository = _CopyReads();
    final recovery = CopyJobRecovery(
      repository: repository,
      store: store,
      currentDeviceId: () => session.state.device?.id,
      isConnected: () => session.state.isConnected,
      sessionChanges: session.stream.map((_) {}),
      refreshes: refresh.changes.map((_) {}),
    );
    await recovery.recover();
    expect(repository.reads, isEmpty);
    expect(await session.restoreSavedSession(), true);
    for (var i = 0; i < 20 && store.activeForDevice(_device.id).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repository.reads, isNotEmpty);
    expect(repository.reads.toSet(), {'original-job'});
    expect(store.forDevice(_device.id).single.state, CopyJobState.completed);
    expect(store.activeForDevice('other-box').single.jobId, 'other-job');
    recovery.dispose();
    await session.close();
    await events.dispose();
    await refresh.dispose();
    store.dispose();
  });

  test('cold restore accepts a verified response after 5s within the total 20s budget', () async {
    final gate = Completer<DeviceStatus>();
    final repository = _Repository()..pending = gate;
    final events = EventClient(), refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _Network(), events, refresh);
    bool? result;
    unawaited(session.restoreSavedSession().then((value) => result = value));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(result, isNull, reason: '认证尚在总窗口内，不能先宣告断开');
    gate.complete(_status);
    await Future<void>.delayed(Duration.zero);
    expect(result, true);
    expect(session.state.isConnected, true);
    final closing = session.close();
    await Future<void>.delayed(Duration.zero);
    await closing;
    final disposing = events.dispose();
    await Future<void>.delayed(Duration.zero);
    await disposing;
    final refreshing = refresh.dispose();
    await Future<void>.delayed(Duration.zero);
    await refreshing;
  });

  test('saved-device lookup is bounded by the same total deadline', () async {
    final lookup = Completer<DeviceConnection?>();
    final repository = _Repository()..lookup = lookup;
    final events = EventClient(), refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _Network(), events, refresh);
    bool? result;
    unawaited(session.restoreSavedSession(timeout: const Duration(milliseconds: 100)).then((value) => result = value));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(result, false);
    expect(repository.calls, 0);
    lookup.complete(_device);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.isConnected, false);
    final closing = session.close();
    await Future<void>.delayed(Duration.zero);
    await closing;
    final disposing = events.dispose();
    await Future<void>.delayed(Duration.zero);
    await disposing;
    final refreshing = refresh.dispose();
    await Future<void>.delayed(Duration.zero);
    await refreshing;
  });

  test('a new verification does not coalesce into a superseded pending attempt', () async {
    final pending = Completer<DeviceStatus>();
    final repository = _Repository()..pending = pending;
    final events = EventClient(), refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(repository, _Network(), events, refresh);
    addTearDown(() async {
      if (!pending.isCompleted) pending.complete(_status);
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });
    final first = session.verifySavedSession();
    await Future<void>.delayed(Duration.zero);
    session.disconnected('new intent');
    repository.pending = null;
    final second = session.verifySavedSession();
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 2);
    expect(await second, true);
    pending.complete(_status);
    expect(await first, false);
    expect(session.state.isConnected, true);
  });

  test('a transient no-network startup rechecks before declaring offline', () async {
    final network = _Network()..answers.addAll([false, true]);
    final repository = _Repository();
    final session = _session(repository, network: network);
    expect(await session.restoreSavedSession(), true);
    expect(network.reads, 2);
    expect(repository.calls, 1);
  });

  test('first authentication waits for event readiness and retries within one intent', () async {
    final repository = _Repository();
    repository.handler = () async {
      if (repository.calls == 1) throw EventSessionNotReadyException();
      return _status;
    };
    final traces = <Map<String, dynamic>>[];
    final session = _session(repository, diagnostic: traces.add);
    expect(await session.restoreSavedSession(), true);
    expect(repository.calls, 2);
    expect(traces.where((e) => e['event'] == 'connection_intent_started'), hasLength(1));
    expect(traces.where((e) => e['event'] == 'connection_retry_wait'), hasLength(1));
  });

  for (final code in [401, 403]) {
    test('HTTP $code stops even if the server marks the response retryable', () async {
      final repository = _Repository()..handler = () async => throw ApiException(message: 'denied', statusCode: code, retryable: true);
      final session = _session(repository);
      expect(await session.restoreSavedSession(), false);
      expect(repository.calls, 1);
      expect(session.state.isConnected, false);
      expect(session.state.message, contains('授权已失效'));
    });
  }

  test('old deadline and late success cannot downgrade a newer successful intent', () async {
    final pending = Completer<DeviceStatus>();
    final repository = _Repository()..pending = pending;
    final session = _session(repository);
    final first = session.restoreSavedSession(timeout: const Duration(milliseconds: 60));
    await Future<void>.delayed(Duration.zero);
    session.beginNetworkIntent('new-network');
    final token = CancelToken();
    final ticket = session.beginEndpointVerification(attemptId: 'new-network', deviceId: _device.id, operationId: 'op-new', token: token);
    final newStatus = DeviceStatus(
      connection: _device.copyWith(baseUri: Uri.parse('http://192.0.2.20:8080')),
      card: _status.card,
    );
    await session.setConnectedFromStatus(newStatus, attempt: ticket);
    pending.complete(_status);
    expect(await first, false);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(session.state.isConnected, true);
    expect(session.state.device?.baseUri, newStatus.connection.baseUri);
    expect(session.state.attemptId, 'new-network');
  });

  test('closing an old page cannot release a newer handoff owner', () async {
    final repository = _Repository();
    final session = _session(repository);
    final oldOwner = Object(), newOwner = Object();
    session.beginNetworkIntent('old');
    session.setHandoffActive(oldOwner, true);
    session.beginNetworkIntent('new');
    session.setHandoffActive(newOwner, true);
    session.setHandoffActive(oldOwner, false);
    session.endNetworkIntent('old');
    expect(session.acceptsNetworkIntent('new'), true);
    expect(session.provisioningHandoffActive, true);
    expect(await session.verifySavedSession(), false);
    expect(repository.calls, 0);
    session.setHandoffActive(newOwner, false);
    session.endNetworkIntent('new');
    expect(session.provisioningHandoffActive, false);
  });

  test('late authenticated status is rejected after its network intent is replaced', () async {
    final session = _session(_Repository());
    session.beginNetworkIntent('A');
    final ticketA = session.beginEndpointVerification(attemptId: 'A', deviceId: _device.id, operationId: 'op-A', token: CancelToken());
    session.beginNetworkIntent('B');
    final ticketB = session.beginEndpointVerification(attemptId: 'B', deviceId: _device.id, operationId: 'op-B', token: CancelToken());
    await session.setConnectedFromStatus(_status, attempt: ticketB);
    await expectLater(session.setConnectedFromStatus(_status, attempt: ticketA), throwsA(isA<DioException>()));
    expect(session.state.attemptId, 'B');
  });
}

DeviceSessionCubit _session(_Repository repository, {_Network? network, void Function(Map<String, dynamic>)? diagnostic}) {
  final events = EventClient(), refresh = SessionRefreshCoordinator();
  final session = DeviceSessionCubit(repository, network ?? _Network(), events, refresh, retryDelay: const Duration(milliseconds: 5), diagnostic: diagnostic);
  addTearDown(() async {
    await session.close();
    await events.dispose();
    await refresh.dispose();
  });
  return session;
}

final _device = DeviceConnection(id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649', name: '盒子', baseUri: Uri.parse('http://192.0.2.10:8080'), networkMode: NetworkMode.infrastructureSta, isPaired: true);
final _status = DeviceStatus(connection: _device, card: const CardStatus(inserted: true, readable: true));

class _Network extends ConnectivityMonitor {
  final answers = <bool>[];
  int reads = 0;
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
  @override
  Future<bool> get hasNetwork async {
    reads++;
    return answers.isEmpty ? true : answers.removeAt(0);
  }
}

class _Repository implements ConnectionRepository {
  Completer<DeviceStatus>? pending;
  Completer<DeviceConnection?>? lookup;
  int calls = 0;
  Future<DeviceStatus> Function()? handler;
  @override
  Future<DeviceConnection?> savedDevice() async => lookup == null ? _device : await lookup!.future;
  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    calls++;
    if (handler != null) return handler!();
    return pending == null ? _status : await pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CopyReads implements CopyJobRepository {
  final reads = <String>[];
  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    reads.add(copyJobId);
    return CopyJobDetail(copyJobId: copyJobId, state: CopyJobState.completed, stateVersion: 2, eventSeq: 0, allowedActions: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Recovery must only read an existing copy job');
}
