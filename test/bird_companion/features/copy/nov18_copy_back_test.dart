import 'dart:async';

import 'package:aves/bird_companion/core/widgets/tab_back_dispatch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in ['相册', '任务']) {
    testWidgets('$entry: system back returns to config before leaving the nested route', (tester) async {
      final key = GlobalKey<NavigatorState>();
      var confirmation = false;
      var selection = 8;
      await tester.pumpWidget(MaterialApp(home: NavigatorPopHandler<Object?>(
        onPopWithResult: (result) => dispatchTabBack(key.currentState, result),
        child: Navigator(key: key, onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Text(entry))),
      )));
      unawaited(key.currentState!.push(MaterialPageRoute<void>(builder: (_) => StatefulBuilder(builder: (context, update) => PopScope(
        canPop: !confirmation,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) update(() => confirmation = false);
        },
        child: Scaffold(body: TextButton(
          onPressed: () => update(() {
            selection = 8;
            confirmation = true;
          }),
          child: Text(confirmation ? '确认' : '配置：$selection 张'),
        )),
      )))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('配置：8 张'));
      await tester.pumpAndSettle();
      expect(find.text('确认'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('配置：8 张'), findsOneWidget);
      expect(key.currentState!.canPop(), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(entry), findsOneWidget);
    });
  }
}
