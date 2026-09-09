import 'dart:io';

import 'package:aves/bird_companion/features/tasks/demo/demo_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_destination_resolver.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_sync_job_summary_sheet.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskDestinationResolver', () {
    test('completed import and analysis open their source album', () {
      for (final type in [TaskType.importIndex, TaskType.aiAnalysis]) {
        final destination = TaskDestinationResolver.resolve(
          _task(type: type, sourceBatchId: ' project-42 '),
        );

        expect(destination.kind, TaskDestinationKind.album);
        expect(destination.sourceProjectId, 'project-42');
      }
    });

    test('completed copy opens its authoritative result', () {
      final destination = TaskDestinationResolver.resolve(
        _task(type: TaskType.copy),
      );

      expect(destination.kind, TaskDestinationKind.copyResult);
    });

    test('active, failed and cancelled tasks always keep task detail', () {
      for (final state in TaskRunState.values.where(
        (state) => state != TaskRunState.completed,
      )) {
        for (final type in TaskType.values) {
          expect(
            TaskDestinationResolver.resolve(
              _task(type: type, state: state, sourceBatchId: 'project-42'),
            ).kind,
            TaskDestinationKind.detail,
          );
        }
      }
    });

    test('missing album relation and non-persisted sync result fail safe to detail', () {
      expect(
        TaskDestinationResolver.resolve(
          _task(type: TaskType.aiAnalysis, sourceBatchId: '  '),
        ).kind,
        TaskDestinationKind.detail,
      );
      expect(
        TaskDestinationResolver.resolve(
          _task(type: TaskType.sync, sourceBatchId: 'project-42'),
        ).kind,
        TaskDestinationKind.detail,
      );
    });
  });

  test('production task root executes the resolver destination', () {
    final source = File(
      'lib/bird_companion/features/tasks/presentation/task_experience_root.dart',
    ).readAsStringSync();

    expect(source, contains('TaskDestinationResolver.resolve(refreshedTask)'));
    expect(source, contains('case TaskDestinationKind.album:'));
    expect(source, contains('case TaskDestinationKind.copyResult:'));
    expect(source, contains('case TaskDestinationKind.detail:'));
  });

  testWidgets('task history row identifies source, completion and counts', (
    tester,
  ) async {
    final task = _task(
      type: TaskType.aiAnalysis,
      sourceBatchId: 'project-42',
      sourceBatch: '崇明东滩晨拍',
      processed: 20,
      total: 24,
      finishedAt: DateTime(2026, 9, 8, 14, 5),
    );
    final controller = TaskExperienceController(_SingleTaskDataSource(task));
    controller.selectGroup(TaskGroup.completed);
    addTearDown(controller.dispose);
    String? openedTaskId;

    await tester.pumpWidget(
      MaterialApp(
        home: TaskHomePage(
          controller: controller,
          onOpenTask: (taskId) => openedTaskId = taskId,
        ),
      ),
    );
    final row = find.byKey(const Key('task-record-task-1'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final subtitleText = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .join(' ');
    expect(subtitleText, contains('来源拍摄记录：崇明东滩晨拍'));
    expect(subtitleText, contains('完成于 9月8日 14:05'));
    expect(subtitleText, contains('处理 20/24 张'));

    await tester.tap(row);
    expect(openedTaskId, 'task-1');
  });

  testWidgets('completed sync detail exposes an explicit summary action', (
    tester,
  ) async {
    final task = _task(
      type: TaskType.sync,
      processed: 18,
      total: 20,
      failedCount: 2,
    );
    final controller = TaskExperienceController(_SingleTaskDataSource(task));
    addTearDown(controller.dispose);
    var showCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(
          controller: controller,
          onShowResult: () => showCount++,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('查看同步摘要'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('查看同步摘要'));
    expect(showCount, 1);
  });

  testWidgets('sync summary labels unavailable per-item history without guessing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskSyncJobSummarySheet(
            task: _task(
              type: TaskType.sync,
              processed: 18,
              total: 20,
              failedCount: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.text('同步任务摘要'), findsOneWidget);
    expect(find.text('18 项'), findsOneWidget);
    expect(find.text('20 项'), findsOneWidget);
    expect(find.text('2 项'), findsOneWidget);
    expect(find.textContaining('不推断冲突或待处理项'), findsOneWidget);
  });
}

TaskSummary _task({
  required TaskType type,
  TaskRunState state = TaskRunState.completed,
  String? sourceBatch,
  String? sourceBatchId,
  int processed = 10,
  int total = 10,
  int failedCount = 0,
  DateTime? finishedAt,
}) => TaskSummary(
  id: 'task-1',
  type: type,
  title: type.label,
  processed: processed,
  total: total,
  progressPercent: state == TaskRunState.completed ? 100 : 50,
  remainingMinutes: 0,
  state: state,
  sourceBatch: sourceBatch,
  sourceBatchId: sourceBatchId,
  failedCount: failedCount,
  finishedAt: finishedAt,
  connectionState: TaskConnectionState.connected,
  availableActions: const {TaskAction.exportLog},
);

class _SingleTaskDataSource extends DemoTaskExperienceDataSource {
  const _SingleTaskDataSource(this.task);

  final TaskSummary task;

  @override
  List<TaskSummary> initialTasks() => [task];
}
