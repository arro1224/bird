import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch 3 responsive task home', () {
    testWidgets('compact enlarged layout stacks summary and next actions', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      );
      addTearDown(controller.dispose);
      var sdCardOpenCount = 0;

      await tester.pumpWidget(
        _app(
          textScale: 1.5,
          home: TaskHomePage(
            controller: controller,
            onOpenSdCard: () => sdCardOpenCount++,
          ),
        ),
      );

      final titleRect = tester.getRect(
        find.byKey(const Key('task-current-title')),
      );
      final statusRect = tester.getRect(
        find.byKey(const Key('task-current-status')),
      );
      expect(statusRect.top, greaterThan(titleRect.bottom));

      final importAction = find.byKey(
        const Key('task-action-importIndex'),
      );
      final analysisAction = find.byKey(
        const Key('task-action-aiAnalysis'),
      );
      await tester.scrollUntilVisible(
        importAction,
        260,
        scrollable: _pageScrollable(),
      );
      expect(tester.getSize(importAction).width, closeTo(272, 1));
      expect(
        tester.getTopLeft(analysisAction).dy,
        greaterThan(tester.getBottomLeft(importAction).dy),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(importAction);
      expect(sdCardOpenCount, 1);
    });

    testWidgets('regular phone width preserves the two-column action grid', (
      tester,
    ) async {
      await _setViewport(tester, const Size(390, 700));
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(home: TaskHomePage(controller: controller)),
      );

      final importRect = tester.getRect(
        find.byKey(const Key('task-action-importIndex')),
      );
      final analysisRect = tester.getRect(
        find.byKey(const Key('task-action-aiAnalysis')),
      );
      expect(importRect.top, closeTo(analysisRect.top, 1));
      expect(importRect.right, lessThan(analysisRect.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact task records remain reachable and open by id', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 568));
      final controller = TaskExperienceController(
        const DemoTaskExperienceDataSource(),
      );
      addTearDown(controller.dispose);
      String? openedTaskId;

      await tester.pumpWidget(
        _app(
          textScale: 1.5,
          home: TaskHomePage(
            controller: controller,
            onOpenTask: (taskId) => openedTaskId = taskId,
          ),
        ),
      );

      final attentionFilter = find.byKey(
        const Key('task-group-attention'),
      );
      await tester.scrollUntilVisible(
        attentionFilter,
        260,
        scrollable: _pageScrollable(),
      );
      await tester.tap(attentionFilter);
      await tester.pump();

      final failedTask = find.byKey(
        const Key('task-record-demo-copy-failed'),
      );
      await tester.scrollUntilVisible(
        failedTask,
        260,
        scrollable: _pageScrollable(),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(failedTask);

      expect(openedTaskId, 'demo-copy-failed');
    });
  });
}

Finder _pageScrollable() => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.physics is BouncingScrollPhysics,
);

Widget _app({required Widget home, double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
