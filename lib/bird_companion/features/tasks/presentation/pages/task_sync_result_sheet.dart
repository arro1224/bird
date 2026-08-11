import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:flutter/material.dart';

class TaskSyncResultSheet extends StatelessWidget {
  const TaskSyncResultSheet({
    super.key,
    required this.result,
    this.onOpenConflicts,
  });

  final SyncResult result;
  final VoidCallback? onOpenConflicts;

  int get failedCount => result.failedOperations
      .where(
        (operation) => operation.status != PendingOperationStatus.conflict,
      )
      .length;

  bool get hasOutstandingWork => failedCount > 0 || result.conflictCount > 0 || result.remainingOperations.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .86;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          key: const Key('task-sync-result-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statusHeader(context),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      _ResultRow(
                        key: const Key('task-sync-synced-count'),
                        label: '已同步',
                        value: result.syncedCount,
                      ),
                      _ResultRow(
                        key: const Key('task-sync-failed-count'),
                        label: '失败',
                        value: failedCount,
                      ),
                      _ResultRow(
                        key: const Key('task-sync-conflict-count'),
                        label: '版本冲突',
                        value: result.conflictCount,
                      ),
                      _ResultRow(
                        key: const Key('task-sync-remaining-count'),
                        label: '仍需处理',
                        value: result.remainingOperations.length,
                        divider: false,
                      ),
                    ],
                  ),
                ),
              ),
              if (hasOutstandingWork) ...[
                const SizedBox(height: 14),
                Container(
                  key: const Key('task-sync-outstanding-notice'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.amberLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.conflictCount > 0 ? '冲突项需要在照片详情中选择保留盒子内容，或重新确认本机修改。未完成项会保留，稍后可以再次同步。' : '未完成项会保留在本机，检查连接或数据状态后可以再次同步。',
                          style: const TextStyle(
                            color: AppColors.ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusHeader(BuildContext context) => Semantics(
    container: true,
    header: true,
    label: hasOutstandingWork ? '同步需要处理' : '同步完成',
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: hasOutstandingWork ? AppColors.amberLight : AppColors.forestSoft,
          child: Icon(
            hasOutstandingWork ? Icons.sync_problem_rounded : Icons.cloud_done_outlined,
            size: 28,
            color: hasOutstandingWork ? AppColors.warning : AppColors.forestPrimary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasOutstandingWork ? '同步需要处理' : '同步完成',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.forestDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasOutstandingWork ? '已同步 ${result.syncedCount} 项，仍有 ${result.remainingOperations.length} 项需要处理' : '${result.syncedCount} 项修改已安全同步到盒子',
                style: const TextStyle(
                  color: AppColors.mutedInk,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context) {
    final canOpenConflicts = result.conflictCount > 0 && onOpenConflicts != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            key: canOpenConflicts ? const Key('task-sync-open-conflicts') : const Key('task-sync-close'),
            onPressed: canOpenConflicts ? () => _openConflicts(context) : () => Navigator.of(context).pop(),
            child: Text(
              canOpenConflicts
                  ? '处理冲突'
                  : hasOutstandingWork
                  ? '关闭'
                  : '完成',
            ),
          ),
        ),
        if (canOpenConflicts) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              key: const Key('task-sync-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('稍后处理'),
            ),
          ),
        ],
      ],
    );
  }

  void _openConflicts(BuildContext context) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onOpenConflicts?.call();
    });
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.label,
    required this.value,
    this.divider = true,
  });

  final String label;
  final int value;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.mutedInk),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$value 项',
                style: const TextStyle(
                  color: AppColors.forestDeep,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
}
