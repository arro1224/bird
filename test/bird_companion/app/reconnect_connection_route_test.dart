import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import '../features/connection/fakes/fake_provisioning_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell route does not collide with the MaterialApp home route', () {
    expect(BirdRoutes.shell, isNot(Navigator.defaultRouteName));
  });

  testWidgets('reconnect entry opens the real connection flow', (tester) async {
    RouteSettings? received;

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          received = settings;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('connection')),
          );
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => openReconnectConnection(context),
              child: const Text('reconnect'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('reconnect'));
    await tester.pumpAndSettle();

    expect(received?.name, BirdRoutes.connection);
    expect(received?.arguments, isA<ConnectionArgs>());
    expect(
      (received?.arguments as ConnectionArgs).entryMode,
      ConnectionEntryMode.addOrSwitch,
    );
  });

  testWidgets('connection route forwards the production provisioning repository', (tester) async {
    final repository = FakeProvisioningRepository(
      devices: [
        ProvisioningDevice(
          scanId: 'scan-route',
          advertisement: BirdBoxAdvertisement(
            localName: 'BirdBox-route',
            serviceUuids: const [],
            rssi: -42,
          ),
        ),
      ],
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
          settings,
          provisioningRepository: repository,
        ),
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.connection),
            child: const Text('connect'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();

    expect(find.text('附近的盒子'), findsOneWidget);
    expect(find.text('BirdBox-route'), findsOneWidget);
  });
}
