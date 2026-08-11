import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batch 2 adaptive task headers', () {
    testWidgets('page frame keeps title centered with subtitle and actions', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 520));

      await tester.pumpWidget(
        _scaledApp(
          home: const TaskPageFrame(
            title: '建立批次',
            subtitle: '步骤 1 / 4 · 导入与索引',
            actions: [IconButton(onPressed: null, icon: Icon(Icons.more_horiz))],
            child: Text('页面内容'),
          ),
        ),
      );

      expect(find.byKey(const Key('task-flow-header')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('task-flow-title'))).dx,
        closeTo(160, 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SD scanning header stays separate from back navigation', (
      tester,
    ) async {
      await _setViewport(tester, const Size(320, 480));
      final controller = _controller(SdCardReadState.scanning);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scaledApp(home: SdCardFlowPage(controller: controller)),
      );

      expect(find.text('正在扫描 SD 卡'), findsWidgets);
      expect(
        tester.getCenter(find.byKey(const Key('task-flow-title'))).dx,
        closeTo(160, 1),
      );
      final backRect = tester.getRect(
        find.byKey(const Key('sd-card-back-button')),
      );
      final titleRect = tester.getRect(
        find.byKey(const Key('task-flow-title')),
      );
      expect(backRect.right, lessThan(titleRect.left));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('task detail timeline and information rows fit enlarged text', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    final controller = TaskExperienceController(
      const DemoTaskExperienceDataSource(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _scaledApp(home: TaskDetailPage(controller: controller)),
    );
    await tester.ensureVisible(
      _keyStartingWith('task-detail-info-row-').last,
    );
    await tester.pump();

    expect(_keyStartingWith('task-timeline-step-'), findsNWidgets(4));
    expect(_keyStartingWith('task-detail-info-row-'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}

Finder _keyStartingWith(String prefix) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(prefix);
});

TaskExperienceController _controller(SdCardReadState state) => TaskExperienceController(const DemoTaskExperienceDataSource())
  ..replaceSdCard(
    SdCardSnapshot(
      state: state,
      name: 'EXTREMELY-LONG-CAMERA-SD-CARD-NAME',
      photoCount: 12345,
      requiredSpaceGb: 123.4,
      rawCount: 12000,
      jpegCount: 345,
      captureDate: DateTime(2026, 8, 10, 8, 30),
    ),
  );

Widget _scaledApp({required Widget home}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.5)),
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
