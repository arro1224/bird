import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/diagnostics/phone_diagnostic_recorder.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/network/reconnect_policy.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/core/storage/cache_schema_migrator.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/connection_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/disconnect_fault_server.dart';

const slow = '/api/v1/smart-follow-sessions/slow';

void main() {
  late _Harness h;
  setUp(() async {
    h = _Harness();
    await h.open();
  });
  tearDown(() => h.close());

  test('真实HTTP业务超时且health正常：保持连接并关联服务端迟到200', () async {
    h.server.faults[slow] = const DisconnectFault(delay: Duration(milliseconds: 230));
    await expectLater(h.api.get(slow), throwsA(isA<ApiException>()));
    await until(() => h.records.any((e) => e['event'] == 'business_failure_reachability_checked'));
    expect(h.session.state.isConnected, true);
    expect(h.checked.single['outcome'], 'reachable');
    await h.server.settle();
    final business = h.records.singleWhere((e) => e['event'] == 'http_request_finished' && e['timeout'] == true);
    final backend = h.server.records.singleWhere((e) => e['request_id'] == business['request_id']);
    expect(backend['status'], 200);
    expect(backend['elapsed_ms'] as int, greaterThan(business['elapsed_ms'] as int));
    await h.save('business_timeout_reachable');
  });

  test('真实HTTP 503保留业务错误，不启动全局探测', () async {
    h.server.faults[slow] = const DisconnectFault(status: 503);
    await expectLater(h.api.get(slow), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
    expect(h.checked, isEmpty);
    expect(h.session.state.isConnected, true);
    await h.save('business_503');
  });

  test('health返回503仍证明HTTP可达，不代表业务或授权通过', () async {
    h.server.faults[slow] = const DisconnectFault(delay: Duration(milliseconds: 200));
    h.server.faults['/health'] = const DisconnectFault(status: 503);
    await expectLater(h.api.get(slow), throwsException);
    await until(() => h.checked.isNotEmpty);
    expect(h.checked.single['outcome'], 'reachable');
    expect(h.session.state.isConnected, true);
    expect(h.server.records.singleWhere((e) => e['route'] == '/health')['authorization_present'], false);
    await h.save('health_503_reachable');
  });

  test('并发真实超时只做一次health，全部失败与同一检查ID关联', () async {
    final health = Completer<void>();
    h.server.faults['/health'] = DisconnectFault(gate: health.future);
    for (var i = 0; i < 3; i++) {
      h.server.faults['$slow-$i'] = const DisconnectFault(delay: Duration(milliseconds: 220));
    }
    await Future.wait([for (var i = 0; i < 3; i++) expectLater(h.api.get('$slow-$i'), throwsException)]);
    health.complete();
    await until(() => h.checked.isNotEmpty);
    expect(h.checked, hasLength(1));
    final joins = h.records.where((e) => {'business_failure_probe_started', 'business_failure_probe_coalesced'}.contains(e['event'])).toList();
    expect(joins, hasLength(3));
    expect(joins.map((e) => e['cause_request_id']).toSet(), hasLength(3));
    expect(joins.map((e) => e['reachability_check_id']).toSet(), {h.checked.single['reachability_check_id']});
    expect(isUuidV4(h.checked.single['probe_request_id'] as String), true);
    expect(h.server.requests('/health'), 1);
    expect(h.session.state.isConnected, true);
    await h.save('concurrent_failures_one_probe');
  });

  test('真实监听端口关闭会进入恢复，原端口恢复后验证HTTP和WS再连回', () async {
    await h.server.suspend();
    final recovering = h.session.stream.firstWhere((s) => s.phase == DeviceSessionPhase.reconnecting);
    await expectLater(h.api.get(slow), throwsException);
    await recovering.timeout(const Duration(seconds: 5));
    expect(h.checked.single['outcome'], 'unreachable');
    await h.server.resume();
    expect(await h.session.verifySavedSession(timeout: const Duration(seconds: 3)), true);
    expect(h.session.state.isConnected, true);
    expect(h.events.currentState, EventConnectionState.connected);
    expect(h.records.where((e) => e['event'] == 'business_failure_recovery_started').single['reachability_check_id'], h.checked.single['reachability_check_id']);
    await h.save('port_closed_then_restored');
  });

  test('health三秒无响应触发有界恢复，不能据此断言物理网络断开', () async {
    h.server.faults[slow] = const DisconnectFault(delay: Duration(milliseconds: 200));
    h.server.faults['/health'] = const DisconnectFault(delay: Duration(milliseconds: 3300));
    await expectLater(h.api.get(slow), throwsException);
    await until(() => h.checked.isNotEmpty, timeout: const Duration(seconds: 4));
    expect(h.checked.single['outcome'], 'unreachable');
    expect(h.checked.single['elapsed_ms'] as int, inInclusiveRange(2900, 3800));
    await until(() => h.session.state.isConnected);
    await h.save('health_probe_budget_exceeded');
  });

  test('WS单独拒绝并重连：REST可用且不降级全局连接', () async {
    h.server.rejectEvents = true;
    await h.server.closeEvents();
    await until(() => h.server.requests('/api/v1/events') >= 2);
    expect((await h.api.get('/api/v1/projects'))['healthy'], true);
    expect(h.session.state.isConnected, true);
    expect(h.checked, isEmpty);
    h.server.rejectEvents = false;
    await until(() => h.events.currentState == EventConnectionState.connected);
    await h.save('ws_only_then_restored');
  });

  test('WS重试预算耗尽仍保留REST，显式核实可恢复事件连接', () async {
    h.server.rejectEvents = true;
    await h.server.closeEvents();
    await until(() => h.events.currentState == EventConnectionState.disconnected);
    expect((await h.api.get('/api/v1/projects'))['healthy'], true);
    expect(h.session.state.isConnected, true);
    expect(h.checked, isEmpty);
    h.server.rejectEvents = false;
    expect(await h.session.verifySavedSession(timeout: const Duration(seconds: 3)), true);
    expect(h.events.currentState, EventConnectionState.connected);
    await h.save('ws_budget_exhausted_rest_ok');
  });

  for (final status in [401, 403]) {
    test('当前授权$status失效，health可达也不能重新标记已授权', () async {
      // A normal successful status handoff may have no active restore attempt.
      await h.session.setConnectedFromStatus(h.server.status);
      h.server.faults['/api/v1/projects'] = DisconnectFault(status: status);
      await expectLater(h.api.get('/api/v1/projects'), throwsException);
      await until(() => h.session.state.phase == DeviceSessionPhase.disconnected);
      expect(h.records.any((e) => e['event'] == 'connection_authentication_invalidated'), true);
      expect(await h.credentials.read(h.server.deviceId), null);
      expect(h.checked, isEmpty);
      expect(await h.api.probeReachability(h.server.baseUri, CancelToken()), true);
      expect(h.session.state.isConnected, false);
      await h.save('current_authorization_$status');
    });
  }

  test('切换设备会取消旧health，迟到结果不触发新设备恢复', () async {
    final other = DisconnectFaultServer(deviceId: 'bbx-5118b55118b55118b55118b55118b552');
    await other.start();
    addTearDown(other.close);
    final health = Completer<void>();
    h.server.faults[slow] = const DisconnectFault(delay: Duration(milliseconds: 180));
    h.server.faults['/health'] = DisconnectFault(gate: health.future);
    await expectLater(h.api.get(slow), throwsException);
    await until(() => h.records.any((e) => e['event'] == 'business_failure_probe_started'));
    await h.credentials.write(h.credential(other));
    final status = await h.repository.connectExpected(other.baseUri, networkMode: NetworkMode.manual, expectedDeviceId: other.deviceId);
    await h.session.setConnectedFromStatus(status);
    health.complete();
    await h.server.settle();
    expect(h.session.state.device?.id, other.deviceId);
    expect(h.session.state.isConnected, true);
    expect(h.records.any((e) => e['event'] == 'business_failure_probe_cancelled'), true);
    expect(h.records.any((e) => e['event'] == 'business_failure_recovery_started'), false);
    await h.save('old_probe_device_switch');
  });

  test('取消实际HTTP读取不触发全局恢复', () async {
    h.server.faults[slow] = const DisconnectFault(delay: Duration(milliseconds: 180));
    final token = CancelToken();
    final timer = Timer(const Duration(milliseconds: 15), token.cancel);
    await expectLater(h.api.getUri(h.server.baseUri.resolve(slow), cancelToken: token), throwsException);
    timer.cancel();
    expect(h.session.state.isConnected, true);
    expect(h.checked, isEmpty);
    expect(h.records.any((e) => e['event'] == 'http_request_finished' && e['cancelled'] == true), true);
    await h.save('cancelled_request');
  });

  test('模拟OS信号：移动数据仍开但WiFi丢失也进入恢复，WiFi恢复后核实', () async {
    final reconnecting = h.session.stream.firstWhere((s) => s.phase == DeviceSessionPhase.reconnecting);
    h.network.wifi = false;
    h.network.transport.add(null);
    await reconnecting.timeout(const Duration(seconds: 2));
    expect(h.session.state.isConnected, false);
    expect(h.checked, isEmpty);
    h.network.wifi = true;
    h.network.transport.add(null);
    await until(() => h.session.state.isConnected);
    await h.save('simulated_wifi_loss_mobile_remains');
  });

  test('N10 cellular-only OS signal still verifies the same box over real HTTP and WS in foreground', () async {
    final before = h.records.where((row) => row['event'] == 'connection_committed').length;
    h.network.wifi = false;
    h.network.transport.add(null);
    await until(() => h.records.where((row) => row['event'] == 'connection_committed').length > before);
    expect(h.session.state.isConnected, true);
    expect(h.session.state.device?.id, h.server.deviceId);
    expect(h.events.currentState, EventConnectionState.connected);
    final committed = h.records.lastWhere((row) => row['event'] == 'connection_committed');
    expect(committed['http_result'], 'protected_read_ok');
    expect(committed['ws_state'], 'connected');
    expect(committed['network_role'], 'local_link_verified_without_wifi_client');
    await h.save('n10_cellular_label_local_box_verified');
  });
}

Future<void> until(bool Function() ready, {Duration timeout = const Duration(seconds: 3)}) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > timeout) fail('B5 condition did not converge within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Storage implements DiagnosticStorage {
  final data = <String, Object?>{};
  @override
  T? read<T>(String key) => data[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => data[key] = jsonDecode(jsonEncode(value));
  @override
  Future<void> remove(String key) async => data.remove(key);
}

class _Network extends ConnectivityMonitor {
  bool wifi = true;
  final transport = StreamController<void>.broadcast();
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
  @override
  Future<bool> get hasNetwork async => true;
  @override
  Future<bool> get hasWifi async => wifi;
}

class _Harness {
  final server = DisconnectFaultServer();
  final storage = _Storage();
  final credentials = MemorySecureSessionStore();
  final network = _Network();
  final refresh = SessionRefreshCoordinator();
  final api = ApiClient(
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 1), receiveTimeout: const Duration(milliseconds: 80))),
  );
  final events = EventClient(reconnectPolicy: const ReconnectPolicy(maxAttempts: 2, initialDelay: Duration(milliseconds: 30)));
  final records = <Map<String, dynamic>>[];
  late final recorder = PhoneDiagnosticRecorder(storage);
  late final coordinator = SessionCoordinator(api, events, credentials);
  late final repository = ConnectionRepositoryImpl(ConnectionApi(api, PairingApi(api), coordinator), storage, KnownDeviceDiscoverySource(() async => []));
  late final session = DeviceSessionCubit(
    repository,
    network,
    events,
    refresh,
    sessionCoordinator: coordinator,
    connectionFailureDetails: api.connectionFailureDetails,
    probeReachability: api.probeReachability,
    transportChanges: network.transport.stream,
    retryDelay: const Duration(milliseconds: 30),
    diagnostic: record,
  );
  List<Map<String, dynamic>> get checked => records.where((e) => e['event'] == 'business_failure_reachability_checked').toList();
  void record(Map<String, dynamic> event) {
    records.add(Map.from(event));
    recorder.record(event);
  }

  SessionCredential credential(DisconnectFaultServer target) =>
      SessionCredential(deviceId: target.deviceId, baseUri: target.baseUri, accessToken: DisconnectFaultServer.token, expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)), apiVersion: 'v1', clientId: 'b5-loopback-client');
  Future<void> open() async {
    await server.start();
    await credentials.write(credential(server));
    await storage.write(CacheSchemaMigrator.activeDeviceKey, server.status.connection.toJson());
    recorder.context = () => session.diagnosticContext;
    api.httpDiagnostics
      ..record = record
      ..context = () => {...session.diagnosticContext, 'session_generation': api.sessionGeneration, 'page': '/smart-follow-run'};
    events.diagnostic = record;
    expect(await session.verifySavedSession(timeout: const Duration(seconds: 3)), true);
    await server.settle();
  }

  Future<void> save(String name) async {
    await server.settle();
    final phone = await recorder.snapshot();
    expect(jsonEncode(phone), isNot(contains(DisconnectFaultServer.token)));
    final output = Platform.environment['BIRDBOX_B5_EVIDENCE_DIR'];
    if (output == null) return;
    final directory = Directory(output).absolute;
    final buildRoot = Directory('build').absolute.path;
    if (!directory.path.startsWith('$buildRoot${Platform.pathSeparator}')) throw StateError('B5 fixture evidence must stay under project build/');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.phone.json').writeAsString(jsonEncode({'environment': 'loopback_control', 'real_box_evidence': false, 'phone_diagnostics': phone}));
    await File('${directory.path}/$name.backend.jsonl').writeAsString('${server.records.map(jsonEncode).join('\n')}\n');
  }

  Future<void> close() async {
    await session.close();
    await coordinator.dispose();
    await events.dispose();
    await api.dispose();
    await server.close();
    await network.transport.close();
    await refresh.dispose();
    await recorder.dispose();
  }
}
