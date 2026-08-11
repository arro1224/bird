import 'dart:io';

import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/storage/domain/card_scan_result.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_home_capability_resolver.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B11 task design closure', () {
    test('explains every unavailable home action from frozen reads', () {
      final disconnected = _capabilities(
        connected: false,
        authorityReady: true,
        currentProject: _project,
        currentScan: _detectedScan,
      );

      expect(disconnected, hasLength(TaskType.values.length));
      expect(disconnected, everyElement(isA<TaskHomeActionCapability>()));
      expect(disconnected, everyElement(hasDisabledReason('连接盒子后可用')));

      final noProject = _capabilities(
        currentProject: null,
        currentScan: _detectedScan,
      );
      expect(_for(noProject, TaskType.importIndex).enabled, isTrue);
      expect(
        _for(noProject, TaskType.aiAnalysis).disabledReason,
        '当前没有可用批次',
      );
      expect(
        _for(noProject, TaskType.copy).disabledReason,
        '当前没有可用批次',
      );
      expect(
        _for(noProject, TaskType.sync).disabledReason,
        '没有待同步的本地修改',
      );

      final scanning = _capabilities(
        currentProject: _project,
        currentScan: const CardScanResult(state: CardScanState.scanning),
      );
      expect(
        _for(scanning, TaskType.importIndex).disabledReason,
        '正在扫描存储卡，请稍候',
      );

      final busy = _capabilities(
        currentProject: _project,
        currentScan: _detectedScan,
        jobs: [
          BirdJobStatus(
            id: 'job-b11-analysis',
            type: BirdJobType.analysis,
            state: BirdJobState.running,
            sourceProjectId: _project.id,
            availableActions: const ['pause', 'cancel'],
          ),
        ],
      );
      expect(
        _for(busy, TaskType.aiAnalysis).disabledReason,
        '当前批次已有任务正在执行',
      );
      expect(
        _for(busy, TaskType.copy).disabledReason,
        '当前批次已有任务正在执行',
      );

      final pendingSync = _capabilities(
        currentProject: _project,
        currentScan: _detectedScan,
        hasPendingOperations: true,
      );
      expect(_for(pendingSync, TaskType.sync).enabled, isTrue);
    });

    testWidgets(
      '360dp at 1.5x exposes the same four capabilities in grid and sheet',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = _CapabilityController();
        var openedSdCard = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(1.5),
              ),
              child: TaskHomePage(
                controller: controller,
                onOpenSdCard: () => openedSdCard = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final type in TaskType.values) {
          expect(find.byKey(Key('task-action-${type.name}')), findsOneWidget);
        }
        expect(find.text('当前没有可用批次'), findsWidgets);
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const Key('task-executable-actions-button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('当前可执行操作'), findsOneWidget);
        expect(find.text('连接盒子后可用'), findsWidgets);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3));

        await tester.tap(find.text(TaskType.importIndex.label).last);
        await tester.pumpAndSettle();
        expect(openedSdCard, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    test('production routes retain real callbacks and no demo placeholders', () {
      final root = File(
        'lib/bird_companion/features/tasks/presentation/task_experience_root.dart',
      ).readAsStringSync();
      final home = File(
        'lib/bird_companion/features/tasks/presentation/pages/task_home_page.dart',
      ).readAsStringSync();
      final batchSetup = File(
        'lib/bird_companion/features/tasks/presentation/pages/batch_setup_page.dart',
      ).readAsStringSync();
      final detail = File(
        'lib/bird_companion/features/tasks/presentation/pages/task_detail_page.dart',
      ).readAsStringSync();
      final result = File(
        'lib/bird_companion/features/tasks/presentation/pages/production_task_result_page.dart',
      ).readAsStringSync();

      expect(root, contains('RepositoryTaskExperienceController'));
      expect(root, contains('onStartImport:'));
      expect(root, contains('onControl:'));
      expect(root, contains('onExportLog:'));
      expect(root, contains('allowDemoCompletion: false'));
      expect(root, contains('ProductionTaskResultPage'));
      expect(home, isNot(contains('已进入当前可执行流程')));
      expect(batchSetup, isNot(contains('演示模式：导入与索引任务已准备')));
      expect(detail, contains('this.allowDemoCompletion = false'));
      expect(result, contains('盒子未提供权威数量'));
    });
  });
}

Matcher hasDisabledReason(String reason) => isA<TaskHomeActionCapability>()
    .having((item) => item.enabled, 'enabled', isFalse)
    .having((item) => item.disabledReason, 'disabledReason', reason);

TaskHomeActionCapability _for(
  List<TaskHomeActionCapability> capabilities,
  TaskType type,
) => capabilities.singleWhere((item) => item.type == type);

List<TaskHomeActionCapability> _capabilities({
  bool connected = true,
  bool authorityReady = true,
  required BatchSummary? currentProject,
  required CardScanResult? currentScan,
  Iterable<BirdJobStatus> jobs = const [],
  bool hasPendingOperations = false,
}) => TaskHomeCapabilityResolver.resolveCapabilities(
  connected: connected,
  authorityReady: authorityReady,
  deviceStatus: _status,
  currentProject: currentProject,
  currentScan: currentScan,
  jobs: jobs,
  hasPendingOperations: hasPendingOperations,
);

class _CapabilityController extends TaskExperienceController {
  _CapabilityController() : super(const ProductionTaskExperienceDataSource());

  @override
  List<TaskHomeActionCapability> get taskHomeCapabilities => const [
    TaskHomeActionCapability(
      type: TaskType.importIndex,
      enabled: true,
      description: '读取存储卡并建立批次',
    ),
    TaskHomeActionCapability(
      type: TaskType.aiAnalysis,
      enabled: false,
      description: '分析当前批次照片',
      disabledReason: '当前没有可用批次',
    ),
    TaskHomeActionCapability(
      type: TaskType.copy,
      enabled: false,
      description: '确认范围和目标硬盘',
      disabledReason: '当前没有可用批次',
    ),
    TaskHomeActionCapability(
      type: TaskType.sync,
      enabled: false,
      description: '同步批次和审片结果',
      disabledReason: '连接盒子后可用',
    ),
  ];
}

const _detectedScan = CardScanResult(
  state: CardScanState.detected,
  cardId: 'card-b11',
  photoCount: 24,
);

final _status = DeviceStatus(
  connection: DeviceConnection(
    id: 'box-b11',
    name: 'B11 box',
    baseUri: Uri.parse('http://192.168.4.1:8080'),
    networkMode: NetworkMode.manual,
    apiVersion: 'v1',
    isPaired: true,
  ),
  card: const CardStatus(inserted: true, readable: true),
);

final _project = BatchSummary(
  id: 'project-b11',
  name: 'B11 project',
  createdAt: DateTime.utc(2026, 8, 10),
  totalFiles: 24,
  analyzedCount: 24,
  reviewCount: 3,
  keepCount: 12,
  discardCount: 9,
  pendingCopyCount: 12,
  copyState: 'pending',
);
