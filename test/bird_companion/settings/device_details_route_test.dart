import 'package:aves/bird_companion/app/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('device details route opens the settings device details page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: BirdRoutes.settingsDeviceDetails,
        onGenerateRoute: BirdAppRouter.onGenerateRoute,
        onGenerateInitialRoutes: (initialRoute) => [
          BirdAppRouter.onGenerateRoute(RouteSettings(name: initialRoute)),
        ],
      ),
    );

    await tester.pump();

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.text('BirdAI 3.0.2'), findsOneWidget);
  });
}
