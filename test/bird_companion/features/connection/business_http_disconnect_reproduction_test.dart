import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with the loopback-only Python delay fixture. Neither Wi-Fi disconnect
// nor DioException is injected: Dio must time out an actual HTTP request.
void main() {
  final address = Platform.environment['BIRDBOX_DISCONNECT_FIXTURE'];
  test('repeated real HTTP business timeouts no longer downgrade a reachable box', () async {
    final uri = Uri.parse(address!);
    expect(uri.host, '127.0.0.1');
    final current = _Experiment(uri);
    addTearDown(current.dispose);
    await current.initialize();
    await Future.wait([
      current.runSlow('current-1', '2e1d9387-56f8-4108-9089-28aba4715670'),
      current.runHealthyControls(),
    ]);
    await current.runSlow('current-2', '2e1d9387-56f8-4108-9089-28aba4715672');
    expect(current.repository.reconnects, 0);
    expect(current.probeOutcomes, ['reachable', 'reachable']);
    expect(current.phases, everyElement(DeviceSessionPhase.connected));
  }, timeout: const Timeout(Duration(seconds: 55)), skip: address == null ? 'Start serve_disconnect_reproduction.py on loopback first.' : false);

  test('a refused socket and failed independent probe enter recovery and reconnect on return', () async {
    final reserved = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = reserved.port;
    final experiment = _Experiment(Uri.parse('http://127.0.0.1:$port'));
    addTearDown(experiment.dispose);
    await experiment.initialize();
    await reserved.close(force: true);
    final enteringRecovery = experiment.cubit.stream.firstWhere((state) => state.phase == DeviceSessionPhase.reconnecting);
    await expectLater(experiment.client.get('/api/v1/smart-follow-sessions/slow'), throwsA(isA<ApiException>()));
    await enteringRecovery.timeout(const Duration(seconds: 5));
    expect(experiment.probeOutcomes, ['unreachable']);
    final restored = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    addTearDown(() => restored.close(force: true));
    restored.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"data":{"healthy":true,"items":[]}}');
      await request.response.close();
    });
    if (!experiment.cubit.state.isConnected) {
      await experiment.cubit.stream.firstWhere((state) => state.isConnected).timeout(const Duration(seconds: 5));
    }
    expect(experiment.repository.reconnects, greaterThan(0));
  });
}

class _Experiment {
  _Experiment(Uri uri) {
    client.configure(uri);
    client.setSession(accessToken: 'isolated-fixture-only');
    repository = _ProbeRepository(client, uri);
    cubit = DeviceSessionCubit(repository, _Online(), events, refresh,
      connectionFailures: client.connectionFailures,
      probeReachability: client.probeReachability,
      diagnostic: (event) {
        if (event['event'] == 'business_failure_reachability_checked') {
          probeOutcomes.add(event['outcome'] as String);
          probes.add(null);
        }
        if (event['event'] == 'connection_intent_started' || event['event'] == 'connection_committed') {
          debugPrint('SESSION ${event['event']} intent=${event['intent']} generation=${event['generation']}');
        }
      },
    );
    subscription = cubit.stream.listen((state) => phases.add(state.phase));
  }

  final client = ApiClient();
  final events = EventClient();
  final refresh = SessionRefreshCoordinator();
  late final _ProbeRepository repository;
  late final DeviceSessionCubit cubit;
  late final StreamSubscription<DeviceSessionState> subscription;
  final phases = <DeviceSessionPhase>[];
  final probeOutcomes = <String>[];
  final probes = StreamController<void>.broadcast();

  Future<void> initialize() => cubit.setConnectedFromStatus(repository.status);

  Future<void> runHealthyControls() async {
    final watch = Stopwatch()..start();
    await client.get('/api/v1/smart-follow-sessions/field-status-delay',
      headers: {'X-Request-Id': '2e1d9387-56f8-4108-9089-28aba4715673'});
    expect(cubit.state.phase, DeviceSessionPhase.connected);
    debugPrint('CONTROL 6.2 s response: connected at ${watch.elapsedMilliseconds} ms');
    await expectLater(client.get('/api/v1/smart-follow-sessions/http-503'),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'HTTP status', 503)));
    expect(cubit.state.phase, DeviceSessionPhase.connected);
    debugPrint('CONTROL HTTP 503: connected');
  }

  Future<void> runSlow(String label, String id) async {
    final before = phases.length;
    final watch = Stopwatch()..start();
    final checked = probes.stream.first.timeout(const Duration(seconds: 22));
    final pending = client.get('/api/v1/smart-follow-sessions/slow', headers: {'X-Request-Id': id});
    final failed = expectLater(pending, throwsA(isA<ApiException>().having(
      (error) => (error.cause as DioException).type, 'transport error', DioExceptionType.receiveTimeout,
    )));
    // A separate status GET succeeds over the same address while the delayed
    // request is pending, proving this experiment is not a network outage.
    expect((await client.get('/api/v1/device/status'))['healthy'], true);
    await failed;
    final timedOutAt = watch.elapsedMilliseconds;
    await checked;
    expect(phases.skip(before), isNot(contains(DeviceSessionPhase.reconnecting)));
    expect(cubit.state.isConnected, true);
    debugPrint('HTTP $label id=$id timeout_ms=$timedOutAt '
      'phases=${phases.skip(before).map((phase) => phase.name).join(",")} '
      'end_ms=${watch.elapsedMilliseconds}');
  }

  Future<void> dispose() async {
    await subscription.cancel();
    await cubit.close();
    await client.dispose();
    await events.dispose();
    await refresh.dispose();
    await probes.close();
  }
}

class _Online extends ConnectivityMonitor {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
  @override
  Future<bool> get hasNetwork async => true;
}

// Test double for discovery/credentials/WS only. Probe HTTP remains real.
class _ProbeRepository implements ConnectionRepository {
  _ProbeRepository(this.client, Uri uri) : device = DeviceConnection(
    id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
    name: 'loopback-test',
    baseUri: uri,
    networkMode: NetworkMode.infrastructureSta,
    isPaired: true,
  );
  final ApiClient client;
  final DeviceConnection device;
  int reconnects = 0;
  DeviceStatus get status => DeviceStatus(connection: device, card: const CardStatus(inserted: true));

  @override
  Future<DeviceConnection?> savedDevice() async => device;
  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    reconnects++;
    expect((await client.getUri(device.baseUri.resolve('/api/v1/device/status'), cancelToken: cancelToken))['healthy'], true);
    await client.verifyAuthenticatedSession(cancelToken);
    return status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
