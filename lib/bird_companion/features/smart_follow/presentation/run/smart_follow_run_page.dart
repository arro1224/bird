import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_files_page.dart';
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
    this.readRecognition,
    this.isCurrent,
    this.refreshSignals,
    this.pollInterval,
    this.metadataSection,
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
  final Future<BirdJobStatus> Function(String jobId)? readRecognition;
  final bool Function()? isCurrent;
  final Stream<void>? refreshSignals;
  final Duration? pollInterval;
  final Widget? metadataSection;

  @override
  State<SmartFollowRunPage> createState() => _SmartFollowRunPageState();
}

class _SmartFollowRunPageState extends State<SmartFollowRunPage> with WidgetsBindingObserver {
  bool _busy = false;
  bool _loaded = false;
  Object? _loadError;
  BirdJobStatus? _recognition;
  SmartFollowChildJobPage? _children;
  Timer? _timer;
  StreamSubscription<void>? _signals;
  Future<void>? _refreshing;
  bool _foreground = true;
  bool _routeVisible = true;
  int _generation = 0, _failures = 0;
  bool get _current => widget.isCurrent?.call() ?? true;

  SmartFollowSession? get _session => widget.repository.snapshot(widget.sessionId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.addListener(_changed);
    _bindSignals();
    unawaited(_refresh(initial: true));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _bindSignals() {
    unawaited(_signals?.cancel());
    _signals = widget.refreshSignals?.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_foreground && _routeVisible && _current) unawaited(_refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeVisible != visible) {
      _routeVisible = visible;
      _timer?.cancel();
      if (visible && _foreground && _current) unawaited(_refresh());
    }
  }

  @override
  void didUpdateWidget(covariant SmartFollowRunPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository || oldWidget.sessionId != widget.sessionId) {
      oldWidget.repository.removeListener(_changed);
      widget.repository.addListener(_changed);
      ++_generation;
      _refreshing = null;
      _recognition = null;
      _children = null;
      _loaded = false;
      _loadError = null;
      unawaited(_refresh(initial: true));
    }
    if (oldWidget.refreshSignals != widget.refreshSignals) _bindSignals();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && _routeVisible && _current) unawaited(_refresh());
  }

  void _schedule() {
    _timer?.cancel();
    final interval = widget.pollInterval;
    if (!mounted || !_foreground || !_routeVisible || !_current || interval == null || (_session?.canShowCompletion == true && _loadError == null)) return;
    final delay = Duration(milliseconds: (interval.inMilliseconds * (1 << _failures.clamp(0, 4))).clamp(1, 60000));
    _timer = Timer(delay, () {
      if (mounted && _foreground && _routeVisible && _current) unawaited(_refresh());
    });
  }

  Future<void> _refresh({bool initial = false}) {
    if (_refreshing != null) return _refreshing!;
    if (!_foreground || !_routeVisible || !_current) return Future.value();
    final generation = _generation;
    return _refreshing = _read(initial: initial, generation: generation).whenComplete(() {
      if (mounted && generation == _generation) {
        _refreshing = null;
        _schedule();
      }
    });
  }

  Future<void> _read({required bool initial, required int generation}) async {
    try {
      final session = await widget.repository.refresh(widget.sessionId);
      if (!mounted || generation != _generation || !_current) return;
      try {
        final page = session.isContinuous ? null : await widget.repository.childJobs(widget.sessionId);
        if (!mounted || generation != _generation || !_current) return;
        _children = page;
      } catch (_) {
        _children = null;
      }
      final read = widget.readRecognition;
      if (read != null) {
        final job = await read(session.recognitionJobId);
        if (!mounted || generation != _generation || !_current) return;
        if (job.id != session.recognitionJobId || job.type != BirdJobType.analysis) throw StateError('识别任务归属无法确认。');
        if (_recognition?.version == null || job.version == null || job.version! >= _recognition!.version!) _recognition = job;
      }
      setState(() {
        _loaded = true;
        _loadError = null;
        _failures = 0;
      });
    } catch (error) {
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        _loaded = true;
        _loadError = error;
        ++_failures;
      });
    }
  }

  Future<void> _act(SmartFollowAction action) async {
    final session = _session;
    if (session == null || _busy || !_current || _loadError != null) return;
    if (action.destructive) {
      final confirmed = await _confirmDestructive(action);
      if (confirmed != true) return;
    }
    if (!mounted || !_current) return;
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
    if (!_current) {
      return Scaffold(
        appBar: AppBar(title: const Text('边识别边复制')),
        body: const Center(child: Text('盒子连接已变化，请返回原盒子后重新打开任务。')),
      );
    }
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError == null ? '会话加载中，请稍候' : UserMessageMapper.fromError(_loadError!).message, textAlign: TextAlign.center),
                TextButton(key: const Key('smart-follow-refresh'), onPressed: _refresh, child: const Text('重新读取任务')),
              ],
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
            if (_loadError != null) const Text('暂时无法获取最新状态，以下为上次读取结果；正在等待重新读取。', key: Key('smart-follow-stale')),
            _StageCard(stage: stage, session: session),
            const SizedBox(height: 12),
            if (_recognition != null || (widget.readRecognition == null && widget.recognitionTotal != null && widget.recognitionProcessed != null)) ...[
              _RecognitionProgress(processed: _recognition?.finishedCount ?? widget.recognitionProcessed!, total: _recognition?.totalCount ?? widget.recognitionTotal!),
              const SizedBox(height: 12),
            ],
            _CountsCard(session: session),
            const SizedBox(height: 12),
            if (session.isContinuous)
              OutlinedButton.icon(
                key: const Key('smart-follow-files'),
                onPressed: () async {
                  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SmartFollowFilesPage(repository: widget.repository, sessionId: session.sessionId)));
                  if (mounted && _current) unawaited(_refresh());
                },
                icon: const Icon(Icons.list_alt), label: const Text('查看复制文件明细'),
              )
            else if (_children == null)
              _ChildJobsCard(session: session, onOpen: widget.onOpenChildJobs)
            else
              Card(child: ExpansionTile(title: TextButton(key: const Key('smart-follow-child-jobs'), onPressed: widget.onOpenChildJobs, child: Text('已创建 ${session.childJobCount} 批 · 查看复制详情')), children: [
                for (final child in _children!.items)
                  ListTile(
                    title: Text('复制批次 ${child.copyJobId}'),
                    subtitle: Text('${child.state.label} · 已复制 ${child.copiedFileCount} · 同名跳过 ${child.skippedFileCount} · 失败 ${child.failedFileCount} 个文件'),
                    onTap: widget.onOpenChildJobs,
                  ),
                if (_children!.hasMore) TextButton(onPressed: widget.onOpenChildJobs, child: const Text('查看全部复制批次')),
                TextButton(onPressed: widget.onOpenChildJobs, child: const Text('查看复制批次详情')),
              ])),
            if (widget.metadataSection != null)
              widget.metadataSection!
            else if (session.metadataUpdateAvailable) ...[
              const SizedBox(height: 12),
              _MetadataHintCard(session: session),
            ],
            const SizedBox(height: 16),
            _ActionsRow(
              session: session,
              busy: _busy || _loadError != null,
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
    ++_generation;
    _timer?.cancel();
    unawaited(_signals?.cancel());
    WidgetsBinding.instance.removeObserver(this);
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
  Widget build(BuildContext context) {
    if (session.isContinuous) {
      final summary = session.summary;
      const labels = {
        'queued': '排队中', 'copying': '复制中', 'retry_wait': '等待重试',
        'blocked': '受阻待处理', 'copied': '已复制', 'skipped_conflict': '同名跳过',
        'failed': '复制失败', 'not_applicable': '不适用', 'stopped': '已停止未复制',
      };
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('持续复制进度', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(summary?.recognitionProcessed == null || summary?.recognitionTotal == null
              ? '识别进度正在读取'
              : '识别 ${summary!.recognitionProcessed} / ${summary.recognitionTotal}'),
          Text(summary?.eligibleAssetCount == null ? '合格索引项正在读取' : '合格索引项 ${summary!.eligibleAssetCount} 个'),
          const Text('按索引文件记账，未合并 RAW/JPEG 照片。'),
          Text(summary?.plannedFileCount == null ? '文件队列正在准备' : '当前计划 ${summary!.plannedFileCount} 个文件'),
          for (final entry in labels.entries)
            _row(entry.value, summary?.fileCounts.containsKey(entry.key) == true ? '${summary!.fileCounts[entry.key]} 个' : '正在读取', Key('continuous-count-${entry.key}'), danger: entry.key == 'failed'),
        ],
      )));
    }
    return Card(
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
          if (session.raw['skipped_file_count'] is int) _row('同名跳过', '${session.raw['skipped_file_count']} 个', const Key('smart-follow-skipped-files')),
          if (session.notCopiedStoppedCount != null) _row('停止后未复制', '${session.notCopiedStoppedCount} 张', const Key('smart-follow-stopped-count')),
          if (session.notApplicableAssetCount != null) _row('不适用', '${session.notApplicableAssetCount} 张', const Key('smart-follow-not-applicable-count')),
          if (session.failedAssetCount > 0) _row('复制失败', '${session.failedAssetCount} 张', const Key('smart-follow-failed'), danger: true),
        ],
      ),
    ),
    );
  }

  Widget _row(String label, String value, Key key, {bool danger = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.mutedInk)),
        ),
        Text(
          value,
          key: key,
          style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.danger : null),
        ),
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
      trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
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
    final canFinish = session.canShowCompletion && onOpenCompletion != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canFinish)
          FilledButton(
            key: const Key('smart-follow-open-completion'),
            onPressed: busy ? null : onOpenCompletion,
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
