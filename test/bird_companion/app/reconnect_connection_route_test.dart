import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reconnect entry opens device discovery in add-or-switch mode', (tester) async {
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
      (received!.arguments! as ConnectionArgs).entryMode,
      ConnectionEntryMode.addOrSwitch,
    );
  });
}
