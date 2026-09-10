import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('任务首页保留设计层级并使用需求任务分类', (tester) async {
    final controller = TaskExperienceController(
      const DemoTaskExperienceDataSource(),
    );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(426, 923));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskHomePage(controller: controller),
      ),
    );

    expect(find.byType(TaskNatureBackground), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('当前任务'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('任务列表'), findsOneWidget);
    expect(find.text('导入/索引'), findsWidgets);
    expect(find.text('AI分析'), findsWidgets);
    expect(find.text('复制照片'), findsWidgets);
    expect(find.text('同步'), findsWidgets);
    expect(find.text('2,384 / 3,672 张'), findsOneWidget);
    expect(find.text('65%'), findsWidgets);
    expect(find.byType(TaskDisconnectedNotice), findsNothing);

    for (final forbidden in ['NAS 访问', 'SD 卡照片分拣', '其他任务', '开始新任务']) {
      expect(find.text(forbidden), findsNothing);
    }
  });

  testWidgets('任务筛选和可执行操作保持稳定触控尺寸', (tester) async {
    final controller = TaskExperienceController(
      const DemoTaskExperienceDataSource(),
    );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(426, 923));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskHomePage(controller: controller),
      ),
    );

    final addButton = find.byKey(const Key('task-executable-actions-button'));
    expect(addButton, findsOneWidget);
    expect(tester.getSize(addButton), const Size(48, 48));

    await tester.scrollUntilVisible(
      find.byKey(const Key('task-group-attention')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    for (final group in ['active', 'attention', 'completed']) {
      final control = find.byKey(Key('task-group-$group'));
      expect(control, findsOneWidget);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.byKey(const Key('task-group-attention')));
    await tester.pump();
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('失败 3 项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-group-completed')));
    await tester.pump();
    expect(find.text('已完成'), findsWidgets);
  });

  testWidgets('断开连接说明盒子任务和重连刷新语义', (tester) async {
    final controller = TaskExperienceController(
      const DemoTaskExperienceDataSource(),
    )..setConnectionState(TaskConnectionState.disconnected);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskHomePage(controller: controller),
      ),
    );

    expect(find.byType(TaskDisconnectedNotice), findsOneWidget);
    expect(find.textContaining('盒子任务可能仍在运行'), findsOneWidget);
    expect(find.textContaining('重新连接后刷新'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-executable-actions-button')));
    await tester.pumpAndSettle();
    expect(find.text('当前可执行操作'), findsOneWidget);
    expect(find.text('新建任务'), findsNothing);
  });
}
