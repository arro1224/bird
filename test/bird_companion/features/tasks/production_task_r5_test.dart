import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R5 SD card secondary actions', () {
    testWidgets('missing card opens the settings device detail route', (
      tester,
    ) async {
      final controller = _controller(SdCardReadState.missing);
      addTearDown(controller.dispose);
      int? selectedTab;
      int? routeTab;
      String? routeName;

      await tester.pumpWidget(
        MaterialApp(
          home: BirdShellNavigation(
            selectTab: (value) => selectedTab = value,
            openTabRoute: (index, route, [arguments]) {
              routeTab = index;
              routeName = route;
            },
            setBottomNavigationVisible: (_) {},
            child: SdCardFlowPage(controller: controller),
          ),
        ),
      );

      await tester.ensureVisible(find.text('查看设备状态'));
      await tester.tap(find.text('查看设备状态'));

      expect(selectedTab, isNull);
      expect(routeTab, 2);
      expect(routeName, BirdRoutes.settingsDeviceDetails);
    });

    testWidgets('replace card gives guidance then performs a real rescan', (
      tester,
    ) async {
      final controller = _controller(SdCardReadState.empty);
      addTearDown(controller.dispose);
      var rescans = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SdCardFlowPage(
            controller: controller,
            onRescan: () async => rescans++,
          ),
        ),
      );

      await tester.ensureVisible(find.text('更换存储卡'));
      await tester.tap(find.text('更换存储卡'));
      await tester.pumpAndSettle();

      expect(controller.sdCard.state, SdCardReadState.empty);
      expect(find.textContaining('请拔出当前存储卡'), findsOneWidget);
      await tester.tap(find.text('已更换，重新检测'));
      await tester.pumpAndSettle();

      expect(rescans, 1);
    });

    testWidgets('read failure hides raw error details', (tester) async {
      final controller = _controller(SdCardReadState.readFailed)
        ..replaceSdCard(
          _card(SdCardReadState.readFailed),
          errorCode: 'card_read_failed',
          errorMessage: r'FileSystemException C:\private\card.raw',
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: SdCardFlowPage(controller: controller)),
      );

      await tester.ensureVisible(find.text('查看详细原因'));
      await tester.tap(find.text('查看详细原因'));
      await tester.pumpAndSettle();

      expect(find.text('存储卡读取失败'), findsWidgets);
      expect(find.text('请重新插卡或检查存储卡格式。'), findsOneWidget);
      expect(find.textContaining(r'C:\private'), findsNothing);
    });
  });

  test('task source uses project name while preserving navigation id', () {
    final task = JobStatusViewAdapter.toTaskSummary(
      const BirdJobStatus(
        id: 'job-copy-source',
        type: BirdJobType.copy,
        state: BirdJobState.running,
        sourceProjectId: 'project-42',
        sourceProjectName: '超长的崇明东滩翠鸟观察拍摄批次名称',
      ),
    )!;

    expect(task.sourceBatch, '超长的崇明东滩翠鸟观察拍摄批次名称');
    expect(task.sourceBatchId, 'project-42');
  });

  group('R5 narrow and enlarged text visual guards', () {
    testWidgets('SD details fit 360 width at 1.3x text', (tester) async {
      await _setViewport(tester, const Size(360, 640));
      final controller = _controller(SdCardReadState.detected);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _scaledApp(home: SdCardFlowPage(controller: controller)),
      );
      await tester.pump();

      expect(find.text('扫描时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('result and long manifest fit 426 width at 1.3x text', (
      tester,
    ) async {
      await _setViewport(tester, const Size(426, 760));

      await tester.pumpWidget(
        _scaledApp(
          home: ProductionTaskResultPage(
            report: JobReport(
              jobId: 'job-r5-result',
              result: JobReportResult.partialSuccess,
              totalCount: 120,
              successCount: 118,
              failedCount: 1,
              skippedCount: 1,
              copiedBytes: 987654321,
              manifestId: 'manifest-with-a-very-long-authoritative-server-identifier-20260809',
              startedAt: DateTime.utc(2026, 8, 9, 1),
              finishedAt: DateTime.utc(2026, 8, 9, 1, 5),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('查看复制报告'));
      await tester.tap(find.text('查看复制报告'));
      await tester.pumpAndSettle();

      expect(find.text('复制报告'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

TaskExperienceController _controller(SdCardReadState state) => TaskExperienceController(const DemoTaskExperienceDataSource())..replaceSdCard(_card(state));

SdCardSnapshot _card(SdCardReadState state) => SdCardSnapshot(
  state: state,
  name: 'EXTREMELY-LONG-CAMERA-SD-CARD-NAME',
  photoCount: 12345,
  requiredSpaceGb: 123.4,
  rawCount: 12000,
  jpegCount: 345,
  captureDate: DateTime(2026, 8, 9, 20, 55),
);

Widget _scaledApp({required Widget home}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.3)),
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
