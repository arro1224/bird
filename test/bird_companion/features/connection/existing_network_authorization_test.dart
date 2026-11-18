import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/pairing_code_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nov18_navigation_test_support.dart';
import 'fakes/fake_provisioning_repository.dart';

final _info = ProvisioningDeviceInfo.fromJson(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map<String, dynamic>);
final _device = ProvisioningDevice(
  scanId: 'existing-wifi-box',
  advertisement: BirdBoxAdvertisement(localName: 'BirdBox-existing', serviceUuids: ['6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000'], rssi: -40),
);

class _Repository extends FakeProvisioningRepository implements ProvisioningHttpAuthorizationReadiness {
  _Repository({this.authorized = false})
    : super(
        devices: [_device],
        deviceInfo: _info,
        pairingWindow: const PairingWindow(mode: PairingCodeMode.fixedDev, codeExpiresIn: Duration(minutes: 2), attemptsRemaining: 3),
      );
  bool authorized;
  Completer<bool>? authorizationRead;
  @override
  Future<bool> hasHttpAuthorization(String deviceId) async => authorizationRead == null ? authorized : authorizationRead!.future;
  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    final result = await super.authorizePairing(pairingCode);
    authorized = true;
    return result;
  }
}

class _Session extends B4Session {
  @override
  void beginNetworkIntent(String id) {}
  @override
  void endNetworkIntent(String id) {}
}

class _Monitor extends ConnectivityMonitor {
  @override
  Stream<void> get onTransportChanged => const Stream.empty();
}

class _Dependencies extends B4Dependencies {
  _Dependencies(this.repository);
  final _Repository repository;
  @override
  _Repository get provisioningRepository => repository;
  final _session = _Session();
  @override
  _Session get deviceSessionCubit => _session;
  final _monitor = _Monitor();
  @override
  ConnectivityMonitor get connectivityMonitor => _monitor;
  int verifications = 0;
  @override
  PendingDirectAp? pendingVerifiedBleEndpoint(ProvisioningDeviceInfo info) =>
      PendingDirectAp(deviceId: info.deviceId, baseUri: Uri.parse('http://192.0.2.2:8787'), operationId: 'existing-network', attemptId: 'existing-network-attempt', networkMode: ProvisioningNetworkMode.infrastructureSta);
  @override
  DirectApHandoffCubit createDirectApHandoff() => DirectApHandoffCubit(
    store: cache,
    verify: (_, _) async {
      verifications++;
      throw StateError('Stop after recording the HTTP handoff boundary.');
    },
  );
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Future<_Dependencies> open(WidgetTester tester, _Repository repository) async {
    final deps = _Dependencies(repository);
    await tester.binding.setSurfaceSize(const Size(720, 1280));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await repository.dispose();
      await deps.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: deps,
        child: MaterialApp(home: ConnectionPage(provisioningRepository: repository)),
      ),
    );
    await _pump(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('连接此盒子'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await _pump(tester);
    return deps;
  }

  testWidgets('an already-networked box still shows application pairing when this phone has no authorization', (tester) async {
    final deps = await open(tester, _Repository());
    expect(deps.verifications, 0);
    expect(find.text('开始配对'), findsOneWidget);
    expect(find.text('盒子验证未完成'), findsNothing);
  });

  testWidgets('fresh code authorization resumes the existing endpoint without reconfiguring Wi-Fi', (tester) async {
    final repository = _Repository();
    final deps = await open(tester, repository);
    await tester.tap(find.text('开始配对'));
    await _pump(tester);
    final cubit = tester.element(find.byType(PairingCodeForm)).read<ProvisioningCubit>();
    await cubit.authorizePairing('246810');
    await _pump(tester);
    expect(deps.verifications, 1);
    expect(repository.calls.where((s) => s == 'setStaConfig' || s == 'startDirectAp'), isEmpty);
  });

  testWidgets('a saved usable authorization keeps the existing-network reconnect shortcut', (tester) async {
    final repository = _Repository(authorized: true);
    final deps = await open(tester, repository);
    expect(deps.verifications, 1);
    expect(repository.calls, isNot(contains('authorizePairing')));
  });

  testWidgets('a late authorization lookup cannot resume after leaving the page', (tester) async {
    final gate = Completer<bool>();
    final repository = _Repository()..authorizationRead = gate;
    final deps = await open(tester, repository);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(true);
    await _pump(tester);
    expect(deps.verifications, 0);
  });
}
