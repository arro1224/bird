import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:flutter/material.dart';

/// 任务详情里的 SmartFollow 摘要卡（E0 接线）。
///
/// 只做两件事：把"这个识别任务正在边识别边复制"显示出来、点进去看运行页。
/// 没有会话时**整块不出现**（普通识别任务不该被塞一张空卡）。
class SmartFollowTaskTile extends StatefulWidget {
  const SmartFollowTaskTile({
    super.key,
    required this.repository,
    required this.recognitionJobId,
    required this.onOpenRun,
    this.recognitionProcessed,
    this.recognitionTotal,
  });

  final SmartFollowRepository repository;
  final String recognitionJobId;

  /// 打开运行页；参数是会话 ID（不是识别任务 ID）。
  final ValueChanged<String> onOpenRun;
  final int? recognitionProcessed;
  final int? recognitionTotal;

  @override
  State<SmartFollowTaskTile> createState() => _SmartFollowTaskTileState();
}

class _SmartFollowTaskTileState extends State<SmartFollowTaskTile> {
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant SmartFollowTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.repository, widget.repository) && oldWidget.recognitionJobId == widget.recognitionJobId) return;
    _resolved = false;
    unawaited(_resolve());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _resolve() async {
    try {
      if (widget.repository.snapshotForJob(widget.recognitionJobId) == null) {
        await widget.repository.refreshForJob(widget.recognitionJobId);
      }
    } catch (_) {
      // 读不到就当作"这个任务没有跟随"：任务详情的其它信息照常可看。
    }
    if (mounted) setState(() => _resolved = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) return const SizedBox.shrink();
    final session = widget.repository.snapshotForJob(widget.recognitionJobId);
    if (session == null) return const SizedBox.shrink();
    final stage = resolveSmartFollowStage(
      session: session,
      recognitionRunning: !session.isFinished,
    );
    final processed = widget.recognitionProcessed;
    final total = widget.recognitionTotal;
    final recognitionPart = processed != null && total != null ? '识别 $processed/$total · ' : '';
    return Card(
      key: const Key('smart-follow-task-tile'),
      child: ListTile(
        leading: Icon(
          switch (stage.tone) {
            SmartFollowStageTone.waiting => Icons.hourglass_top,
            SmartFollowStageTone.failure => Icons.error_outline,
            SmartFollowStageTone.success => Icons.check_circle_outline,
            _ => Icons.sync,
          },
          color: stage.tone == SmartFollowStageTone.failure ? AppColors.danger : AppColors.forestDeep,
        ),
        title: const Text('边识别边复制'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stage.label),
            Text('$recognitionPart已识别 ${session.eligibleCount} 张 · 待复制 ${session.pendingCount} 张 · 已复制 ${session.copiedAssetCount} 张'),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onOpenRun(session.sessionId),
      ),
    );
  }

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    super.dispose();
  }
}
