import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/direct_ap_handoff_panel.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'direct_ap_handoff_test.dart' show MemoryHandoffStorage, until;
import 'fakes/fake_provisioning_repository.dart';

final info = ProvisioningDeviceInfo.fromJson(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map<String, dynamic>);
final endpoint = Uri.parse('http://10.225.158.210:8080');
const operation = 'op_sta_current';
StaNetworkConfiguration configuration() => StaNetworkConfiguration(
  provisioningMethod: ProvisioningMethod.bleManual,
  selectionMethod: WifiSelectionMethod.manual,
  ssid: 'test-network',
  security: WifiSecurity.wpa2Personal,
  password: 'not-for-logging',
  hidden: false,
  networkKind: StaNetworkKind.otherPhoneHotspot,
);
ProvisioningNetworkStatus status({String op = operation, NetworkOperationState state = NetworkOperationState.staConnected, ProvisioningException? error}) => ProvisioningNetworkStatus(
  activeMode: ProvisioningNetworkMode.infrastructureSta,
  desiredMode: ProvisioningNetworkMode.infrastructureSta,
  operationState: state,
  operationId: op,
  busy: false,
  baseUri: endpoint,
  directAp: const DirectApSnapshot(),
  infrastructureSta: const InfrastructureStaSnapshot(saved: true),
  lastError: error,
  updatedAt: DateTime.now(),
);
ProvisioningEvent ready({String op = operation, String? deviceId}) => ProvisioningEvent(
  type: ProvisioningEventType.staConnected,
  requestId: 'request-current',
  deviceId: deviceId ?? info.deviceId,
  payload: StaConnected(
    operationId: op,
    ssid: 'test-network',
    ipv4: endpoint.host,
    prefixLength: 24,
    gatewayIpv4: '10.225.158.1',
    baseUri: endpoint,
    networkKind: StaNetworkKind.otherPhoneHotspot,
    provisioningMethod: ProvisioningMethod.bleManual,
  ),
);
FakeProvisioningRepository repository({ProvisioningNetworkStatus? snapshot, Object? error}) => FakeProvisioningRepository(
  networkStatus: snapshot,
  networkStatusError: error,
  setStaConfigResult: const CommandAccepted(operationId: operation, desiredMode: ProvisioningNetworkMode.infrastructureSta),
);

void main() {
  test('correlated STA ready hands off without another BLE read; late BLE failure cannot veto verified HTTP', () async {
    final repo = repository(error: StateError('BLE lost'));
    final gate = Completer<void>();
    var calls = 0;
    final handoff = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      verify: (pending, _) {
        ++calls;
        expect(pending.isSta, true);
        expect(pending.deviceId, info.deviceId);
        return gate.future;
      },
    );
    final network = NetworkProvisioningCubit(repo, directApHandoff: handoff);
    addTearDown(repo.dispose);
    addTearDown(handoff.close);
    addTearDown(network.close);
    network.openWifiProvisioning(info);
    await network.submitStaConfiguration(configuration());
    await Future<void>.delayed(Duration.zero);
    final before = repo.calls.where((call) => call == 'getNetworkStatus').length;
    repo.emitEvent(ready());
    await until(() => calls == 1);
    expect(repo.calls.where((call) => call == 'getNetworkStatus').length, before);
    repo.emitError(StateError('disconnect after ready'));
    gate.complete();
    await until(() => handoff.state.phase == DirectApHandoffPhase.directApConnected);
    repo.emitError(StateError('late disconnect'));
    await Future<void>.delayed(Duration.zero);
    expect(network.state.phase, NetworkProvisioningPhase.confirmingNetwork);
    expect(handoff.state.phase, DirectApHandoffPhase.directApConnected);
  });

  test('missing ready notification is recovered from current operation status, not old success', () async {
    final repo = repository(snapshot: status(op: 'old'));
    var calls = 0;
    final handoff = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      verify: (_, _) async {
        ++calls;
      },
    );
    final network = NetworkProvisioningCubit(repo, directApHandoff: handoff, pollInterval: const Duration(milliseconds: 5));
    addTearDown(repo.dispose);
    addTearDown(handoff.close);
    addTearDown(network.close);
    network.openWifiProvisioning(info);
    await network.submitStaConfiguration(configuration());
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(calls, 0);
    repo.emitEvent(ready(op: 'old'));
    repo.emitEvent(ready(deviceId: 'bbx-ffffffffffffffffffffffffffffffff'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
    repo.networkStatus = status();
    await until(() => handoff.state.phase == DirectApHandoffPhase.directApConnected);
    expect(calls, 1);
  });

  test('lost BLE reconciles trusted endpoint once; only HTTP verification completes', () async {
    final repo = repository(error: StateError('disconnected'));
    final gate = Completer<void>();
    var lookups = 0;
    final handoff = DirectApHandoffCubit(store: MemoryHandoffStorage(), verify: (_, _) => gate.future);
    final network = NetworkProvisioningCubit(
      repo,
      directApHandoff: handoff,
      reconciliationWindow: const Duration(milliseconds: 20),
      pollInterval: const Duration(milliseconds: 5),
      resolveStaEndpoint: (id) async {
        expect(id, info.deviceId);
        ++lookups;
        return endpoint;
      },
    );
    addTearDown(repo.dispose);
    addTearDown(handoff.close);
    addTearDown(network.close);
    network.openWifiProvisioning(info);
    await network.submitStaConfiguration(configuration());
    repo.emitError(StateError('BLE disconnected'));
    await until(() => handoff.state.active);
    expect(handoff.state.phase, isNot(DirectApHandoffPhase.directApConnected));
    gate.complete();
    await until(() => handoff.state.phase == DirectApHandoffPhase.directApConnected);
    expect(lookups, 1);
    expect(repo.calls.where((call) => call == 'setStaConfig'), hasLength(1));
  });

  test('same-operation box failure is authoritative; does not reuse old healthy endpoint', () async {
    final repo = repository(
      snapshot: status(
        state: NetworkOperationState.failed,
        error: const ProvisioningException(code: ProvisioningErrorCode.authorizationRequired, retryable: false),
      ),
    );
    var lookups = 0;
    final handoff = DirectApHandoffCubit(store: MemoryHandoffStorage(), verify: (_, _) async => fail('must not connect'));
    final network = NetworkProvisioningCubit(
      repo,
      directApHandoff: handoff,
      reconciliationWindow: const Duration(milliseconds: 15),
      resolveStaEndpoint: (_) async {
        ++lookups;
        return endpoint;
      },
    );
    addTearDown(repo.dispose);
    addTearDown(handoff.close);
    addTearDown(network.close);
    network.openWifiProvisioning(info);
    await network.submitStaConfiguration(configuration());
    await until(() => network.state.phase == NetworkProvisioningPhase.failure);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(lookups, 0);
    expect(handoff.state.active, false);
  });

  test('rapid submit is single flight and a left page ignores late endpoint lookup', () async {
    final repo = repository(error: StateError('BLE lost'));
    final lookup = Completer<Uri?>();
    final handoff = DirectApHandoffCubit(store: MemoryHandoffStorage(), verify: (_, _) async => fail('stale'));
    final network = NetworkProvisioningCubit(repo, directApHandoff: handoff, reconciliationWindow: const Duration(milliseconds: 10), resolveStaEndpoint: (_) => lookup.future);
    addTearDown(repo.dispose);
    addTearDown(handoff.close);
    addTearDown(network.close);
    network.openWifiProvisioning(info);
    await Future.wait([network.submitStaConfiguration(configuration()), network.submitStaConfiguration(configuration())]);
    expect(repo.calls.where((call) => call == 'setStaConfig'), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    network.backToMethodSelection();
    lookup.complete(endpoint);
    await Future<void>.delayed(Duration.zero);
    expect(handoff.state.active, false);
  });

  test('STA pending mode restores after process death and contains no STA SSID/password', () async {
    final store = MemoryHandoffStorage();
    final first = DirectApHandoffCubit(store: store, verify: (_, _) => Completer<void>().future);
    await first.begin(PendingDirectAp(deviceId: info.deviceId, baseUri: endpoint, operationId: operation, networkMode: ProvisioningNetworkMode.infrastructureSta, ssid: 'private-ssid', attemptId: 'persisted-attempt'));
    await first.close();
    final raw = jsonEncode(store.values);
    expect(raw, isNot(contains('private-ssid')));
    expect(raw, isNot(contains('not-for-logging')));
    final restored = DirectApHandoffCubit(
      store: store,
      verify: (pending, _) async {
        expect(pending.isSta, true);
        expect(pending.attemptId, 'persisted-attempt');
      },
    );
    addTearDown(restored.close);
    expect(await restored.restore(), true);
    await until(() => restored.state.phase == DirectApHandoffPhase.directApConnected);
  });

  testWidgets('STA handoff shows shared WLAN guidance, not box hotspot password UI', (tester) async {
    final handoff = DirectApHandoffCubit(store: MemoryHandoffStorage(), verify: (_, _) => Completer<void>().future);
    await handoff.begin(PendingDirectAp(deviceId: info.deviceId, baseUri: endpoint, operationId: operation, networkMode: ProvisioningNetworkMode.infrastructureSta));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectApHandoffPanel(cubit: handoff, onBack: () {}),
        ),
      ),
    );
    expect(find.textContaining('请让手机与盒子连接同一 Wi-Fi'), findsOneWidget);
    expect(find.text('查看盒子热点密码'), findsNothing);
    await handoff.close();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('network failure exports evidence in place without starting a new scan', (tester) async {
    final repo = repository();
    final network = NetworkProvisioningCubit(repo);
    addTearDown(() async {
      await network.close();
      await repo.dispose();
    });
    network.openWifiProvisioning(info);
    network.completionFailed(const NetworkOperationFailedException());
    // A terminal timeout from legacy confirmation produces the actual failure view.
    await network.submitStaConfiguration(configuration());
    repo.emitEvent(ready());
    await tester.pump();
    await tester.pump();
    var exports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: network,
            child: NetworkProvisioningPage(
              onBack: () {},
              onExportDiagnostic: () {
                ++exports;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('导出本次连接诊断'));
    expect(exports, 1);
    expect(repo.calls, isNot(contains('discover')));
    await tester.pumpWidget(const SizedBox());
  });
}
