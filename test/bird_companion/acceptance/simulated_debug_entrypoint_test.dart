import 'dart:io';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/b7_simulated_demo_page.dart';
import 'package:aves/bird_companion/simulation/simulated_bird_box_debug_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
  final baseUri = Uri.parse('http://127.0.0.1:8787');

  test('debug config accepts only explicit loopback HTTP and rc4 identity', () {
    final config = SimulatedBirdBoxDebugConfig.parse(
      baseUrl: baseUri.toString(),
      deviceId: deviceId,
    );

    expect(config.baseUri, baseUri);
    expect(config.deviceId, deviceId);
    expect(
      () => SimulatedBirdBoxDebugConfig.parse(
        baseUrl: 'https://example.com:8787',
        deviceId: deviceId,
      ),
      throwsFormatException,
    );
    expect(
      () => SimulatedBirdBoxDebugConfig.parse(
        baseUrl: baseUri.toString(),
        deviceId: 'mock-k7-001',
      ),
      throwsFormatException,
    );
  });

  testWidgets('fake BLE completion hands off to the real shell route', (
    tester,
  ) async {
    var healthChecks = 0;
    final repository = B7SimulatedProvisioningRepository(
      baseUri: baseUri,
      deviceId: deviceId,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: B7SimulatedDemoPage(
          repository: repository,
          titlePrefix: '模拟 · ',
          onProvisioningCompleted: (completion) async {
            healthChecks++;
            expect(completion.baseUri, baseUri);
            expect(completion.deviceId, deviceId);
            expect(
              completion.networkMode,
              ProvisioningNetworkMode.directAp,
            );
          },
        ),
        onGenerateRoute: (settings) {
          if (settings.name != BirdRoutes.shell) return null;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(
              body: Text('拍鸟伴侣正式首页'),
            ),
          );
        },
      ),
    );

    await _settleSimulatedEvent(tester);
    expect(find.text('模拟 · 查找盒子'), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
    expect(find.text('BirdBox-B7B7B7B7'), findsOneWidget);

    await tester.tap(find.text('连接此盒子'));
    await _settleSimulatedEvent(tester);
    await tester.tap(find.text('开始配对'));
    await _settleSimulatedEvent(tester);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('安全配对并连接'));
    await _settleSimulatedEvent(tester);
    await tester.tap(find.text('直连盒子'));
    await _settleSimulatedEvent(tester);
    expect(find.text('盒子直连已就绪'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(healthChecks, 1);
    expect(find.text('拍鸟伴侣正式首页'), findsOneWidget);
    expect(find.text('模拟验收结果'), findsNothing);
    expect(find.byType(Banner), findsNothing);
  });

  test('debug repository keeps Direct AP, STA and DPP on the HTTP Mock URL', () async {
    final repository = B7SimulatedProvisioningRepository(
      baseUri: baseUri,
      deviceId: deviceId,
    );
    addTearDown(repository.dispose);
    final events = <ProvisioningEvent>[];
    final subscription = repository.events.listen(events.add);
    addTearDown(subscription.cancel);

    final discovered = await repository.discoverDevices().first;
    final info = await repository.connect(discovered);
    expect(info.deviceId, deviceId);

    await repository.startDirectAp();
    await _waitForEvent(
      events,
      (event) => event.payload is DirectApReady,
    );
    expect(
      events.where((event) => event.payload is DirectApReady).single.payload,
      isA<DirectApReady>().having(
        (value) => value.baseUri,
        'baseUri',
        baseUri,
      ),
    );

    await repository.setStaConfig(
      StaNetworkConfiguration(
        provisioningMethod: ProvisioningMethod.bleManual,
        selectionMethod: WifiSelectionMethod.manual,
        ssid: 'BirdLab-5G',
        security: WifiSecurity.wpa2Personal,
        password: 'synthetic-only',
        hidden: false,
        networkKind: StaNetworkKind.router,
      ),
    );
    await _waitForEvent(
      events,
      (event) => event.payload is StaConnected,
    );
    final sta = events.where((event) => event.payload is StaConnected).map((event) => event.payload as StaConnected).last;
    expect(sta.baseUri, baseUri);
    expect(sta.provisioningMethod, ProvisioningMethod.bleManual);

    await repository.startDppProvisioning();
    await _waitForEvent(
      events,
      (event) => event.payload is DppBootstrapReady,
    );
    await _waitForEvent(
      events,
      (_) => events.where((event) => event.payload is StaConnected).length >= 2,
    );
    expect(
      events.where((event) => event.payload is DppBootstrapReady),
      isNotEmpty,
    );
    final dppSta = events.where((event) => event.payload is StaConnected).map((event) => event.payload as StaConnected).last;
    expect(dppSta.baseUri, baseUri);
    expect(dppSta.provisioningMethod, ProvisioningMethod.androidDpp);
    expect((await repository.getNetworkStatus()).baseUri, baseUri);
  });

  test('entrypoint and AS configuration remain debug-only and isolated', () {
    final entrypoint = File('lib/main_bird_simulated.dart').readAsStringSync();
    final runConfiguration = File(
      '.run/bird-simulated-vivo.run.xml',
    ).readAsStringSync();
    final productionEntrypoint = File('lib/main.dart').readAsStringSync();
    final productionDependencies = File(
      'lib/bird_companion/app/app_dependencies.dart',
    ).readAsStringSync();
    final simulatedApp = File(
      'lib/bird_companion/simulation/simulated_bird_box_debug_app.dart',
    ).readAsStringSync();

    expect(entrypoint, contains('if (!kDebugMode)'));
    expect(entrypoint, contains('SimulatedBirdBoxDebugApp'));
    expect(runConfiguration, contains('main_bird_simulated.dart'));
    expect(runConfiguration, contains('--debug'));
    expect(runConfiguration, contains('BIRD_TEST_BASE_URL'));
    expect(runConfiguration, contains('BIRD_SIMULATED_DEVICE_ID'));
    expect(productionEntrypoint, isNot(contains('simulated')));
    expect(productionDependencies, isNot(contains('B7Simulated')));
    expect(simulatedApp, contains('BirdCompanionDependencies.create'));
    expect(simulatedApp, contains('restoreSavedSession: false'));
    expect(simulatedApp, contains('PairingApi(dependencies.apiClient)'));
    expect(simulatedApp, contains('persist: false'));
    expect(simulatedApp, contains('DeviceStatusApi(dependencies.apiClient)'));
    expect(simulatedApp, contains('BirdAppRouter.onGenerateRoute'));
    expect(simulatedApp, isNot(contains('模拟验收结果')));
  });
}

Future<void> _settleSimulatedEvent(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _waitForEvent(
  List<ProvisioningEvent> events,
  bool Function(ProvisioningEvent event) predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (events.any(predicate)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for the simulated provisioning event.');
}
