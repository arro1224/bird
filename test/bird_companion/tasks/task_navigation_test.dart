import 'package:aves/bird_companion/app/bird_demo_shell.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/copy_content_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('independent shell switches between task and device pages', (
    tester,
  ) async {
    final controller = TaskExperienceController(
      const DemoTaskExperienceDataSource(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BirdDemoShell(taskController: controller),
      ),
    );

    expect(find.text('相册'), findsOneWidget);
    expect(find.text('任务'), findsWidgets);
    expect(find.text('设备'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
    expect(find.byKey(const Key('task-home-page')), findsOneWidget);

    controller.pauseOrResume();
    await tester.tap(find.text('设备'));
    await tester.pump();
    expect(find.byKey(const Key('settings-showcase-page')), findsOneWidget);
    expect(find.text('崇明东滩 7月16日'), findsOneWidget);
    expect(find.text('导入/索引'), findsOneWidget);

    await tester.tap(find.byKey(const Key('device-current-work-task')));
    await tester.pump();
    expect(find.byKey(const Key('task-home-page')), findsOneWidget);
    expect(controller.currentTask.state.name, 'paused');
  });

  testWidgets('task next actions open their concrete flows', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BirdDemoShell(taskController: controller),
      ),
    );

    final copyAction = find.descendant(
      of: find.byType(GridView),
      matching: find.text('复制照片'),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(copyAction);
    await tester.pumpAndSettle();
    expect(find.text('复制范围'), findsOneWidget);
    expect(find.text('仅复制保留照片'), findsOneWidget);
  });

  testWidgets('replacing shell controller rebuilds the nested task navigator', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final firstController = TaskExperienceController(const DemoTaskExperienceDataSource());
    final secondController = TaskExperienceController(const DemoTaskExperienceDataSource())..startImportBatch('替换后的批次');
    addTearDown(firstController.dispose);
    addTearDown(secondController.dispose);
    var useSecond = false;
    late StateSetter setHostState;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return BirdDemoShell(
              taskController: useSecond ? secondController : firstController,
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('task-executable-actions-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('导入/索引')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已检测到存储卡'), findsOneWidget);

    setHostState(() => useSecond = true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-home-page')), findsOneWidget);
    expect(find.text('已检测到存储卡'), findsNothing);
    expect(find.textContaining('替换后的批次'), findsOneWidget);
  });

  testWidgets(
    'BirdDemoShell advances import and analysis directly into copy result',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: BirdDemoShell(taskController: controller),
        ),
      );

      await tester.tap(find.byKey(const Key('task-executable-actions-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(BottomSheet), matching: find.text('导入/索引')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始建立批次'));
      await tester.tap(find.text('开始建立批次'));
      await tester.pumpAndSettle();
      expect(controller.activeBatchId, 'demo-batch-20260716');
      expect(controller.currentTask.sourceBatch, '2026.07.16 导入批次');
      expect(find.byType(TaskDetailPage), findsOneWidget);
      expect(find.text('导入/索引'), findsOneWidget);

      await _tapTaskMenuAction(tester, '演示完成导入');

      expect(controller.taskById('demo-import-running').state, TaskRunState.completed);
      expect(controller.taskById('demo-analysis-paused').state, TaskRunState.queued);
      expect(controller.currentTask.type, TaskType.aiAnalysis);
      expect(find.text('照片复制完成'), findsNothing);
      expect(find.text('开始 AI 分析'), findsOneWidget);

      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('设备')),
      );
      await tester.pump();
      expect(
        find.descendant(of: find.byKey(const Key('device-current-work-task')), matching: find.text('AI分析')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('任务')),
      );
      await tester.pump();
      expect(find.text('开始 AI 分析'), findsOneWidget);

      await tester.ensureVisible(find.text('开始 AI 分析'));
      await tester.tap(find.text('开始 AI 分析'));
      await tester.pump();
      expect(controller.taskById('demo-analysis-paused').state, TaskRunState.running);
      await _tapTaskMenuAction(tester, '演示完成 AI 分析');

      expect(find.byType(CopyContentPage), findsOneWidget);
      expect(find.text('复制范围'), findsOneWidget);
      expect(find.text('演示审阅'), findsNothing);
      expect(find.byKey(const Key('batch-name-field')), findsNothing);

      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('设备')),
      );
      await tester.pump();
      expect(find.byKey(const Key('settings-showcase-page')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('device-current-work-task')), matching: find.text('复制')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('任务')),
      );
      await tester.pump();
      expect(find.text('复制范围'), findsOneWidget);
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('确认复制'), findsOneWidget);
      await tester.ensureVisible(find.text('开始复制'));
      await tester.tap(find.text('开始复制'));
      await tester.pumpAndSettle();

      final runningCopy = controller.taskById('demo-copy-failed');
      expect(runningCopy.state, TaskRunState.running);
      expect(runningCopy.sourceBatch, '2026.07.16 导入批次');
      expect(find.byType(TaskDetailPage), findsOneWidget);
      await _tapTaskMenuAction(tester, '演示完成复制');

      expect(controller.taskById('demo-copy-failed').state, TaskRunState.completed);
      expect(find.byType(TaskResultPage), findsOneWidget);
      expect(find.text('照片复制完成'), findsOneWidget);

      await tester.ensureVisible(find.text('进入相册'));
      await tester.tap(find.text('进入相册'));
      await tester.pumpAndSettle();
      expect(find.text('照片复制完成'), findsNothing);
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('任务')),
      );
      await tester.pump();
      expect(find.byKey(const Key('task-home-page')), findsOneWidget);
      expect(controller.currentTask.type, TaskType.copy);
      expect(controller.currentTask.state, TaskRunState.completed);
      expect(find.text('2,012 / 2,012 张'), findsOneWidget);
      expect(find.text('演示审阅'), findsNothing);
      expect(find.text('确认复制'), findsNothing);
      expect(find.text('照片复制完成'), findsNothing);
    },
  );

  testWidgets('copy setup system back returns to task home without stale setup', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await _pumpShellToCopy(tester, controller);

    await Navigator.maybePop<void>(tester.element(find.text('复制范围')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-home-page')), findsOneWidget);
    expect(find.text('建立批次'), findsNothing);
    expect(find.text('复制范围'), findsNothing);
  });

  testWidgets('copy result system back returns to task home without stale confirmation', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await _pumpShellToCopy(tester, controller);
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始复制'));
    await tester.tap(find.text('开始复制'));
    await tester.pumpAndSettle();
    await _tapTaskMenuAction(tester, '演示完成复制');
    expect(find.text('照片复制完成'), findsOneWidget);

    await Navigator.maybePop<void>(tester.element(find.text('照片复制完成')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-home-page')), findsOneWidget);
    expect(find.text('确认复制'), findsNothing);
    expect(find.text('照片复制完成'), findsNothing);
  });

  _sdCardStateTests();

  testWidgets('detected card can start import without a temporary batch page', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    var continueCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => SdCardFlowPage(
            controller: controller,
            onContinue: () {
              continueCalls++;
              controller.startImportBatch('2026.07.16 导入批次');
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('开始建立批次'));
    await tester.tap(find.text('开始建立批次'));
    await tester.pumpAndSettle();

    expect(continueCalls, 1);
    expect(controller.activeBatchId, 'demo-batch-20260716');
    expect(controller.currentTask.state, TaskRunState.running);
    expect(controller.currentTask.sourceBatch, '2026.07.16 导入批次');
    expect(find.text('复制范围'), findsNothing);
    expect(find.byKey(const Key('batch-name-field')), findsNothing);
  });

  testWidgets('复制任务页面保留设计稿关键内容', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    final pages = <Widget>[
      CopyContentPage(controller: controller),
      CopyConfirmationPage(controller: controller),
      TaskDetailPage(controller: controller),
      TaskResultPage(controller: controller),
    ];
    final expected = ['复制范围', '确认复制', '任务进度', '照片复制完成'];
    for (var i = 0; i < pages.length; i++) {
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: pages[i]));
      expect(find.text(expected[i]), findsOneWidget);
    }
  });

  testWidgets('任务二级页返回按钮固定在左侧', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller),
      ),
    );

    final backButton = find.byKey(const Key('task-page-back-button'));
    expect(backButton, findsOneWidget);
    expect(tester.getTopLeft(backButton).dx, lessThan(40));
  });

  testWidgets('复制内容页使用设计稿中的独立模式卡和外置硬盘视觉', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyContentPage(controller: controller),
      ),
    );

    expect(find.byKey(const Key('copy-mode-card')), findsNWidgets(3));
    final driveIcon = find.byKey(const Key('copy-target-drive-icon'));
    expect(driveIcon, findsOneWidget);
    expect(
      find.descendant(of: driveIcon, matching: find.byType(Transform)),
      findsNothing,
    );
    expect(find.byKey(const Key('copy-recommended-badge')), findsOneWidget);
    expect(tester.getBottomRight(find.text('保存为默认策略')).dy, lessThan(800));
  });

  testWidgets('确认复制页使用安全提示条和文字校验状态', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyConfirmationPage(controller: controller),
      ),
    );

    expect(find.byKey(const Key('copy-safety-notice')), findsOneWidget);
    expect(find.byKey(const Key('copy-verification-status')), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('复制范围'), findsOneWidget);
    expect(find.text('照片数量'), findsOneWidget);
    expect(find.text('预计使用空间'), findsOneWidget);
    expect(find.text('目标存储'), findsOneWidget);
    expect(find.text('XMP'), findsOneWidget);
    expect(find.text('仅保留照片'), findsOneWidget);
    expect(find.text('2,012 张'), findsOneWidget);
    expect(find.text('238.7 GB'), findsOneWidget);
    expect(find.text('Samsung T7 Shield'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
  });

  testWidgets('offline copy target blocks starting the copy task', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource())..setCopyTargetOnline(false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyConfirmationPage(controller: controller),
      ),
    );

    expect(find.text('目标存储已断开，请重新连接后再开始复制'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始复制'));
    expect(startButton.onPressed, isNull);
  });

  testWidgets('任务详情页包含时间线和图标化任务信息', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller),
      ),
    );

    expect(find.byKey(const Key('task-progress-emphasis')), findsOneWidget);
    expect(find.byKey(const Key('task-timeline-connector')), findsNWidgets(3));
    expect(find.byKey(const Key('task-detail-info-icon')), findsNWidgets(4));
    expect(tester.getBottomRight(find.text('取消任务')).dy, lessThan(800));
  });

  testWidgets('任务详情 follows the selected task operational data', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller),
      ),
    );

    expect(find.text('导入/索引'), findsOneWidget);
    expect(find.text('崇明东滩 7月16日'), findsOneWidget);
    expect(find.text('DSC_2384.ARW'), findsOneWidget);
    expect(find.text('42 MB/s'), findsOneWidget);
    expect(find.text('AI 照片分析'), findsNothing);
  });

  testWidgets('queued AI without resume capability does not show start action', (tester) async {
    const demo = DemoTaskExperienceDataSource();
    final tasks = List.of(demo.initialTasks());
    final analysisIndex = tasks.indexWhere((task) => task.type == TaskType.aiAnalysis);
    tasks[analysisIndex] = tasks[analysisIndex].copyWith(
      state: TaskRunState.queued,
      availableActions: const {},
    );
    final controller = TaskExperienceController(_NavigationTestDataSource(tasks));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller, taskId: tasks[analysisIndex].id),
      ),
    );

    expect(find.text('开始 AI 分析'), findsNothing);
  });

  testWidgets('task detail follows global connection truth without advancing progress', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller, taskId: 'demo-copy-failed'),
      ),
    );

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('目标硬盘连接中断'), findsOneWidget);
    expect(find.textContaining('盒子任务可能仍在运行'), findsNothing);
    expect(find.textContaining('正在重新连接盒子'), findsNothing);
    expect(find.text('重试失败项'), findsOneWidget);
    expect(find.text('跳过失败项'), findsOneWidget);
    expect(find.byKey(const Key('task-detail-menu-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-detail-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text('导出日志'), findsOneWidget);
    await tester.tapAt(const Offset(12, 220));
    await tester.pumpAndSettle();
    expect(find.text('暂停任务'), findsNothing);
    expect(controller.taskById('demo-copy-failed').processed, 2009);

    controller.setConnectionState(TaskConnectionState.disconnected);
    await tester.pump();
    expect(find.textContaining('盒子任务可能仍在运行'), findsOneWidget);
    expect(controller.taskById('demo-copy-failed').processed, 2009);

    controller.setConnectionState(TaskConnectionState.reconnecting);
    await tester.pump();
    expect(find.textContaining('盒子任务可能仍在运行'), findsNothing);
    expect(find.textContaining('正在重新连接盒子'), findsOneWidget);
    expect(controller.taskById('demo-copy-failed').processed, 2009);

    controller.setConnectionState(TaskConnectionState.connected);
    await tester.pump();
    expect(find.textContaining('盒子任务可能仍在运行'), findsNothing);
    expect(find.textContaining('正在重新连接盒子'), findsNothing);
    expect(controller.taskById('demo-copy-failed').processed, 2009);
  });

  testWidgets('retrying failed copy removes stale failure detail', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskDetailPage(controller: controller, taskId: 'demo-copy-failed'),
      ),
    );

    expect(find.text('目标硬盘连接中断'), findsOneWidget);
    await tester.ensureVisible(find.text('重试失败项'));
    await tester.tap(find.text('重试失败项'));
    await tester.pump();

    expect(find.text('目标硬盘连接中断'), findsNothing);
    expect(controller.taskById('demo-copy-failed').failedCount, 0);
  });

  testWidgets('任务完成页包含带外环成功标识和复核提示图标', (tester) async {
    final controller = TaskExperienceController(const DemoTaskExperienceDataSource());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TaskResultPage(controller: controller),
      ),
    );

    expect(find.byKey(const Key('task-result-success-badge')), findsOneWidget);
    expect(find.byKey(const Key('task-result-review-icon')), findsOneWidget);
  });
}

Future<void> _tapTaskMenuAction(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(find.byKey(const Key('task-detail-menu-button')));
  await tester.pumpAndSettle();
  expect(find.text(label), findsOneWidget);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _pumpShellToCopy(
  WidgetTester tester,
  TaskExperienceController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: BirdDemoShell(taskController: controller),
    ),
  );
  await tester.tap(find.byKey(const Key('task-executable-actions-button')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text('导入/索引')),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('开始建立批次'));
  await tester.tap(find.text('开始建立批次'));
  await tester.pumpAndSettle();
  await _tapTaskMenuAction(tester, '演示完成导入');
  await tester.ensureVisible(find.text('开始 AI 分析'));
  await tester.tap(find.text('开始 AI 分析'));
  await tester.pump();
  await _tapTaskMenuAction(tester, '演示完成 AI 分析');
  expect(find.byType(CopyContentPage), findsOneWidget);
  expect(find.text('复制范围'), findsOneWidget);
  expect(find.text('演示审阅'), findsNothing);
}

Future<void> _pumpSdState(
  WidgetTester tester,
  SdCardReadState state,
) async {
  final controller = TaskExperienceController(
    const DemoTaskExperienceDataSource(),
  )..setSdState(state);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: SdCardFlowPage(controller: controller),
    ),
  );
}

class _NavigationTestDataSource implements TaskExperienceDataSource {
  const _NavigationTestDataSource(this.tasks);

  final List<TaskSummary> tasks;

  @override
  List<TaskSummary> initialTasks() => List.of(tasks);

  @override
  List<TaskType> executableTaskTypes() => tasks.map((task) => task.type).toList();

  @override
  SdCardSnapshot initialSdCard() => const DemoTaskExperienceDataSource().initialSdCard();

  @override
  CopyEstimate copyEstimate(CopyMode mode) => const DemoTaskExperienceDataSource().copyEstimate(mode);

  @override
  TaskCompletion completion() => const DemoTaskExperienceDataSource().completion();
}

void _sdCardStateTests() {
  final cases = <SdCardReadState, (String, String)>{
    SdCardReadState.detected: ('已检测到存储卡', '开始建立批次'),
    SdCardReadState.missing: ('未检测到存储卡', '重新检测'),
    SdCardReadState.readFailed: ('存储卡读取失败', '重新读取'),
    SdCardReadState.empty: ('存储卡中没有可处理的照片', '重新扫描'),
  };
  for (final entry in cases.entries) {
    testWidgets('SD 卡状态 ${entry.key.name}', (tester) async {
      await _pumpSdState(tester, entry.key);
      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
    });
  }

  testWidgets('检测到存储卡页包含设计稿中的导航和信息层级', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpSdState(tester, SdCardReadState.detected);

    expect(find.byKey(const Key('sd-card-back-button')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('sd-card-back-button'))).dx, lessThan(40));
    expect(find.byKey(const Key('sd-card-detected-hero')), findsOneWidget);
    expect(find.byKey(const Key('sd-card-info-chevron')), findsNWidgets(4));
    expect(tester.getSize(find.text('文件类型')).width, greaterThan(70));
    expect(tester.renderObject<RenderParagraph>(find.text('预计读取空间')).didExceedMaxLines, isFalse);
  });
}
