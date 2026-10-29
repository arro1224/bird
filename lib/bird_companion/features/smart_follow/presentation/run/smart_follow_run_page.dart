import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:flutter/material.dart';

/// SmartFollow 运行详情页（分工任务书 R1）。
///
/// 三条纪律：
/// - 所有数字直接取自会话快照，页面不做任何 "+1"；
/// - 按钮只来自 `snapshot.allowedActions`，后端没给的动作不渲染；
/// - 会话未到终态时**不显示完成页入口**，避免"复制批次完成 = 整体完成"的误读。
class SmartFollowRunPage extends StatefulWidget {
  const SmartFollowRunPage({
    super.key,
    required this.repository,
    required this.sessionId,
    this.recognitionProcessed,
    this.recognitionTotal,
    this.metadataUpdate,
    this.onOpenChildJobs,
    this.onOpenCompletion,
  });

  final SmartFollowRepository repository;
  final String sessionId;

  /// 识别任务进度（来自 `BirdJobStatus.finished/total_count`）。
  /// 后端是否把它放进事件接口仍是待对账项（问询单第 4 条），所以这里是可选输入。
  final int? recognitionProcessed;
  final int? recognitionTotal;

  /// 正在运行的信息更新父任务；非空且未终态时阶段显示"正在统一保存信息"。
  final SmartFollowMetadataUpdate? metadataUpdate;

  final VoidCallback? onOpenChildJobs;
  final VoidCallback? onOpenCompletion;

  @override
  State<SmartFollowRunPage> createState() => _SmartFollowRunPageState();
}

class _SmartFollowRunPageState extends State<SmartFollowRunPage> {
  bool _busy = false;
  bool _loaded = false;
  Object? _loadError;

  SmartFollowSession? get _session => widget.repository.snapshot(widget.sessionId);

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    unawaited(_refresh(initial: true));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh({bool initial = false}) async {
    try {
      await widget.repository.refresh(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (initial || _session == null) _loadError = error;
      });
      if (!initial) _showError(error);
    }
  }

  Future<void> _act(SmartFollowAction action) async {
    final session = _session;
    if (session == null || _busy) return;
    if (action.destructive) {
      final confirmed = await _confirmDestructive(action);
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.act(widget.sessionId, action);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDestructive(SmartFollowAction action) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('停止跟随？'),
      content: const Text('当前还没复制的照片不会再复制，已经复制成功的副本会保留。识别任务本身不会被取消。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')),
        FilledButton(
          key: const Key('smart-follow-confirm-stop'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action.label),
        ),
      ],
    ),
  );

  void _showError(Object error) {
    final message = UserMessageMapper.fromError(error);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${message.title}：${message.message}')));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (!_loaded && session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('边识别边复制')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError == null ? '会话加载中，请稍候' : UserMessageMapper.fromError(_loadError!).message,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final stage = resolveSmartFollowStage(session: session, metadataUpdate: widget.metadataUpdate);
    return Scaffold(
      appBar: AppBar(
        title: const Text('边识别边复制'),
        actions: [
          IconButton(
            key: const Key('smart-follow-refresh'),
            tooltip: '刷新',
            onPressed: _busy ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StageCard(stage: stage, session: session),
            const SizedBox(height: 12),
            if (widget.recognitionTotal != null && widget.recognitionProcessed != null) ...[
              _RecognitionProgress(processed: widget.recognitionProcessed!, total: widget.recognitionTotal!),
              const SizedBox(height: 12),
            ],
            _CountsCard(session: session),
            const SizedBox(height: 12),
            _ChildJobsCard(session: session, onOpen: widget.onOpenChildJobs),
            if (session.metadataUpdateAvailable) ...[
              const SizedBox(height: 12),
              _MetadataHintCard(session: session),
            ],
            const SizedBox(height: 16),
            _ActionsRow(
              session: session,
              busy: _busy,
              onAct: _act,
              onOpenCompletion: widget.onOpenCompletion,
            ),
            const SizedBox(height: 16),
            const Text('退出 App 不会停止盒子上的识别与复制；回来后会自动恢复进度。', style: TextStyle(color: AppColors.mutedInk)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    super.dispose();
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage, required this.session});

  final SmartFollowStage stage;
  final SmartFollowSession session;

  @override
  Widget build(BuildContext context) {
    final color = switch (stage.tone) {
      SmartFollowStageTone.failure => AppColors.danger,
      SmartFollowStageTone.waiting => const Color(0xFFB26A00),
      SmartFollowStageTone.success => AppColors.forestDeep,
      _ => AppColors.forestDeep,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (stage.tone) {
                    SmartFollowStageTone.waiting => Icons.hourglass_top,
                    SmartFollowStageTone.failure => Icons.error_outline,
                    SmartFollowStageTone.success => Icons.check_circle_outline,
                    _ => Icons.sync,
                  },
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    key: const Key('smart-follow-stage-label'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(stage.hint, style: const TextStyle(color: AppColors.mutedInk)),
            if (session.errorMessage != null && session.errorMessage!.trim().isNotEmpty && stage.tone != SmartFollowStageTone.failure) ...[
              const SizedBox(height: 8),
              Text(session.errorMessage!.trim(), style: TextStyle(color: color)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecognitionProgress extends StatelessWidget {
  const _RecognitionProgress({required this.processed, required this.total});

  final int processed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (processed / total).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('识别 $processed / $total', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio, minHeight: 6),
          ],
        ),
      ),
    );
  }
}

class _CountsCard extends StatelessWidget {
  const _CountsCard({required this.session});

  final SmartFollowSession session;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('进度', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _row('已识别', '${session.eligibleCount} 张', const Key('smart-follow-eligible')),
          _row('待复制', '${session.pendingCount} 张', const Key('smart-follow-pending')),
          _row('已复制照片', '${session.copiedAssetCount} 张', const Key('smart-follow-copied-assets')),
          _row('已复制文件', '${session.copiedFileCount} 个', const Key('smart-follow-copied-files')),
          if (session.failedAssetCount > 0) _row('复制失败', '${session.failedAssetCount} 张', const Key('smart-follow-failed'), danger: true),
        ],
      ),
    ),
  );

  Widget _row(String label, String value, Key key, {bool danger = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.mutedInk))),
        Text(value, key: key, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.danger : null)),
      ],
    ),
  );
}

class _ChildJobsCard extends StatelessWidget {
  const _ChildJobsCard({required this.session, this.onOpen});

  final SmartFollowSession session;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const Key('smart-follow-child-jobs'),
      leading: const Icon(Icons.layers_outlined),
      title: const Text('复制批次'),
      subtitle: Text('已创建 ${session.childJobCount} 批 · 每批创建后清单不再变化'),
      trailing: onOpen == null
          ? null
          : const Icon(Icons.chevron_right),
      onTap: onOpen,
    ),
  );
}

class _MetadataHintCard extends StatelessWidget {
  const _MetadataHintCard({required this.session});

  final SmartFollowSession session;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF6E5),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('识别信息有新的变化，可更新到已复制的 ${session.copiedAssetCount} 张照片上（不会重新复制照片）。'),
    ),
  );
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.session,
    required this.busy,
    required this.onAct,
    this.onOpenCompletion,
  });

  final SmartFollowSession session;
  final bool busy;
  final Future<void> Function(SmartFollowAction action) onAct;
  final VoidCallback? onOpenCompletion;

  @override
  Widget build(BuildContext context) {
    final canFinish = session.isFinished && onOpenCompletion != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canFinish)
          FilledButton(
            key: const Key('smart-follow-open-completion'),
            onPressed: onOpenCompletion,
            child: const Text('查看完成结果'),
          ),
        for (final action in session.allowedActions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              key: Key('smart-follow-action-${action.wire}'),
              onPressed: busy ? null : () => onAct(action),
              child: Text(action.label),
            ),
          ),
      ],
    );
  }
}
