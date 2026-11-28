import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('original analysis detail shows actual import then analysis and retains completed import', (tester) async {
    final controller = _Controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: controller, taskId: 'analysis-1'),
      ),
    );
    expect(find.text('导入/索引'), findsOneWidget);
    expect(find.text('导入与索引 · 进行中'), findsOneWidget);
    expect(find.text('4 / 10 张 · 40%'), findsOneWidget);
    expect(find.text('AI 识别 · 等待导入完成'), findsOneWidget);
    expect(find.textContaining('0 / 0'), findsNothing);
    controller.replaceRepositoryTasks([_import(TaskRunState.completed, 10), _analysis(TaskRunState.running, 3)]);
    await tester.pump();
    expect(find.text('导入与索引 · 已完成'), findsOneWidget);
    expect(find.text('10 / 10 张 · 100%'), findsOneWidget);
    expect(find.text('AI 识别 · 进行中'), findsOneWidget);
    expect(find.text('3 / 10 张 · 30%'), findsOneWidget);
    expect(find.text('AI分析'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fast completion and offline snapshot keep real counts without fake ETA', (tester) async {
    final controller = _Controller()..replaceRepositoryTasks([_import(TaskRunState.completed, 10), _analysis(TaskRunState.completed, 10)]);
    addTearDown(controller.dispose);
    controller.setConnectionState(TaskConnectionState.disconnected);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: controller, taskId: 'analysis-1'),
      ),
    );
    expect(find.text('导入与索引 · 已完成'), findsOneWidget);
    expect(find.text('AI 识别 · 已完成'), findsOneWidget);
    expect(find.textContaining('上次进度快照'), findsWidgets);
    expect(find.text('剩余时间暂不可用'), findsOneWidget);
    expect(find.textContaining('浏览图片由盒子另行准备'), findsOneWidget);
  });

  testWidgets('100 percent import still running is not completed and does not switch to analysis', (tester) async {
    final controller = _Controller()..replaceRepositoryTasks([_import(TaskRunState.running, 10), _analysis(TaskRunState.queued, 0)]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: controller, taskId: 'analysis-1'),
      ),
    );
    expect(find.text('导入/索引'), findsOneWidget);
    expect(find.text('导入与索引 · 等待盒子确认完成'), findsOneWidget);
    expect(find.text('导入与索引 · 已完成'), findsNothing);
  });
}

class _Controller extends TaskExperienceController {
  _Controller() : super(const ProductionTaskExperienceDataSource()) {
    setConnectionState(TaskConnectionState.connected);
    replaceRepositoryTasks([_import(TaskRunState.running, 4), _analysis(TaskRunState.queued, 0)]);
  }
  @override
  ImportAnalysisTaskProgress? importAnalysisProgress(String taskId) => ImportAnalysisTaskProgress(importTask: taskById('import-1'), analysisTask: taskById('analysis-1'));
}

TaskSummary _import(TaskRunState state, int count) =>
    TaskSummary(id: 'import-1', type: TaskType.importIndex, title: '导入', processed: count, total: 10, progressPercent: count * 10, remainingMinutes: null, state: state, updatedAt: DateTime.utc(2026, 11, 28));
TaskSummary _analysis(TaskRunState state, int count) => TaskSummary(
  id: 'analysis-1',
  type: TaskType.aiAnalysis,
  title: 'AI',
  processed: count,
  total: state == TaskRunState.queued ? 0 : 10,
  progressPercent: count * 10,
  remainingMinutes: null,
  state: state,
  workflowStage: state == TaskRunState.queued ? 'waiting_import' : 'analyzing',
  updatedAt: DateTime.utc(2026, 11, 28),
);
