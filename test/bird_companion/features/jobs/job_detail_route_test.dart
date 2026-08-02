import 'package:aves/bird_companion/app/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('job detail route rejects a missing job id', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: BirdRoutes.jobDetail,
        onGenerateRoute: BirdAppRouter.onGenerateRoute,
        onGenerateInitialRoutes: (initialRoute) => [
          BirdAppRouter.onGenerateRoute(RouteSettings(name: initialRoute)),
        ],
      ),
    );

    await tester.pump();

    expect(find.text('缺少任务编号'), findsOneWidget);
    expect(find.textContaining('demo-analysis'), findsNothing);
  });
}
