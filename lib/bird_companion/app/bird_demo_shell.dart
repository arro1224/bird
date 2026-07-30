import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/settings/presentation/settings_showcase_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/copy_content_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/sd_card_flow_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_result_page.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:flutter/material.dart';

typedef BirdDemoSettingsBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback onOpenTask,
      VoidCallback onOpenAlbum,
    );

class BirdDemoShell extends StatefulWidget {
  const BirdDemoShell({
    super.key,
    required this.taskController,
    this.settingsPage,
    this.settingsPageBuilder,
  }) : assert(settingsPage == null || settingsPageBuilder == null);

  final TaskExperienceController taskController;
  final Widget? settingsPage;
  final BirdDemoSettingsBuilder? settingsPageBuilder;

  @override
  State<BirdDemoShell> createState() => _BirdDemoShellState();
}

class _BirdDemoShellState extends State<BirdDemoShell> {
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        const _AlbumPlaceholder(),
        _TaskTabNavigator(
          key: ValueKey(widget.taskController),
          controller: widget.taskController,
          onOpenAlbum: () => setState(() => _selectedIndex = 0),
        ),
        _settingsRoot(),
      ],
    ),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? AppColors.forestPrimary : AppColors.mutedInk,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      child: NavigationBar(
        height: 82,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
        backgroundColor: AppColors.surface.withValues(alpha: .96),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded, color: AppColors.forestPrimary),
            label: '相册',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded, color: AppColors.forestPrimary),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices_rounded, color: AppColors.forestPrimary),
            label: '设备',
          ),
        ],
      ),
    ),
  );

  Widget _settingsRoot() => ListenableBuilder(
    listenable: widget.taskController,
    builder: (context, _) {
      final task = widget.taskController.currentTask;
      void openTask() => setState(() => _selectedIndex = 1);
      void openAlbum() => setState(() => _selectedIndex = 0);
      return widget.settingsPageBuilder?.call(context, openTask, openAlbum) ??
          widget.settingsPage ??
          SettingsShowcasePage(
            embedded: true,
            currentBatchTitle: task.sourceBatch ?? '当前批次',
            currentBatchSummary: '${task.total} 张照片 · ${task.pendingReviewCount ?? 0} 张待审',
            currentTaskTitle: task.type.label,
            currentTaskSummary: '${task.processed} / ${task.total} · ${task.progressPercent}%',
            onOpenCurrentBatch: openAlbum,
            onOpenCurrentTask: openTask,
          );
    },
  );
}

class _TaskTabNavigator extends StatelessWidget {
  const _TaskTabNavigator({super.key, required this.controller, required this.onOpenAlbum});
  final TaskExperienceController controller;
  final VoidCallback onOpenAlbum;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (taskContext) => TaskHomePage(
        controller: controller,
        onOpenCurrentTask: () => _openDetail(taskContext),
        onOpenSdCard: () => _openSdCard(taskContext),
        onOpenTask: (taskId) => _openDetail(taskContext, taskId: taskId),
        onStartTask: (type) => _openTaskFlow(taskContext, type),
      ),
    ),
  );

  void _openTaskFlow(BuildContext context, TaskType type) {
    switch (type) {
      case TaskType.importIndex:
        _openSdCard(context);
        return;
      case TaskType.aiAnalysis:
        _openDetail(context, taskId: 'demo-analysis-paused');
        return;
      case TaskType.copy:
        _openCopy(context);
        return;
      case TaskType.sync:
        _openDetail(context, taskId: 'demo-sync-completed');
        return;
    }
  }

  void _openCopy(BuildContext context) => Navigator.of(context).push<void>(_copyRoute());

  MaterialPageRoute<void> _copyRoute() => MaterialPageRoute<void>(
    builder: (copyContext) => CopyContentPage(
      controller: controller,
      onNext: () => Navigator.of(copyContext).push<void>(
        MaterialPageRoute<void>(
          builder: (confirmContext) => CopyConfirmationPage(
            controller: controller,
            onStart: () {
              const copyTaskId = 'demo-copy-failed';
              controller.startTask(copyTaskId);
              _openDetail(confirmContext, taskId: copyTaskId);
            },
          ),
        ),
      ),
    ),
  );

  void _openSdCard(BuildContext context) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (sdContext) => SdCardFlowPage(
        controller: controller,
        onContinue: () {
          final date = controller.sdCard.captureDate;
          controller.startImportBatch(
            '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} 导入批次',
          );
          Navigator.of(sdContext).pushReplacement<void, void>(_detailRoute());
        },
      ),
    ),
  );

  void _openDetail(BuildContext context, {String? taskId}) => Navigator.of(context).push<void>(
    _detailRoute(taskId: taskId),
  );

  MaterialPageRoute<void> _detailRoute({String? taskId}) => MaterialPageRoute<void>(
    builder: (detailContext) => TaskDetailPage(
      controller: controller,
      taskId: taskId,
      onShowResult: () => _openResult(detailContext),
      onTaskCompleted: (type) => _advanceAfterCompletion(detailContext, type),
    ),
  );

  void _advanceAfterCompletion(BuildContext context, TaskType type) {
    switch (type) {
      case TaskType.importIndex:
        Navigator.of(context).pushReplacement<void, void>(
          _detailRoute(taskId: 'demo-analysis-paused'),
        );
        return;
      case TaskType.aiAnalysis:
        Navigator.of(context).pushAndRemoveUntil<void>(
          _copyRoute(),
          (route) => route.isFirst,
        );
        return;
      case TaskType.copy:
        Navigator.of(context).pushAndRemoveUntil<void>(
          _resultRoute(),
          (route) => route.isFirst,
        );
        return;
      case TaskType.sync:
        return;
    }
  }

  void _openResult(BuildContext context) => Navigator.of(context).push<void>(_resultRoute());

  MaterialPageRoute<void> _resultRoute() => MaterialPageRoute<void>(
    builder: (resultContext) => TaskResultPage(
      controller: controller,
      onOpenAlbum: () {
        Navigator.of(resultContext).popUntil((route) => route.isFirst);
        onOpenAlbum();
      },
    ),
  );
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.paper,
    child: SafeArea(
      child: Center(
        child: Text(
          '相册',
          style: TextStyle(
            color: AppColors.forestDeep,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
