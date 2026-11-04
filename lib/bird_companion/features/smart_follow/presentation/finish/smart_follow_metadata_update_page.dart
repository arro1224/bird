import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';

class SmartFollowMetadataUpdatePage extends StatefulWidget {
  const SmartFollowMetadataUpdatePage({super.key, required this.controller, required this.onOpenCopy, required this.onOpenPreview, required this.onOpenUpdate, this.refreshSignals, this.pollInterval = const Duration(seconds: 4)});
  final SmartFollowMetadataUpdateController controller;
  final void Function(String) onOpenCopy, onOpenUpdate;
  final VoidCallback onOpenPreview;
  final Stream<void>? refreshSignals;
  final Duration pollInterval;
  @override
  State<SmartFollowMetadataUpdatePage> createState() => _SmartFollowMetadataUpdatePageState();
}

class _SmartFollowMetadataUpdatePageState extends State<SmartFollowMetadataUpdatePage> with WidgetsBindingObserver {
  StreamSubscription<void>? _signals;
  Timer? _timer;
  Future<void>? _refreshing;
  bool _foreground = true, _visible = true;
  int _failures = 0;
  String? _observed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    widget.controller.repository.addListener(_sessionChanged);
    _signals = widget.refreshSignals?.listen((_) {
      if (mounted) setState(() {});
      if (_foreground && _visible) unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    final value = widget.controller.repository.snapshot(widget.controller.sessionId);
    final signature = '${value?.stateVersion}|${value?.activeMetadataUpdateId}|${value?.metadataUpdateAvailable}';
    if (_observed == signature) return;
    _observed = signature;
    if (_foreground && _visible && !widget.controller.busy) unawaited(_refresh());
  }

  Future<void> _refresh() => _refreshing ??= () async {
    _timer?.cancel();
    await widget.controller.refresh();
    if (!mounted) return;
    _failures = widget.controller.error != null || widget.controller.availabilityError != null ? _failures + 1 : 0;
    if (_foreground && _visible && widget.controller.current) {
      final delay = Duration(milliseconds: (widget.pollInterval.inMilliseconds * (1 << _failures.clamp(0, 4))).clamp(1, 60000));
      _timer = Timer(delay, () => unawaited(_refresh()));
    }
  }().whenComplete(() => _refreshing = null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (visible != _visible) {
      _visible = visible;
      _timer?.cancel();
      if (visible && _foreground) unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    if (_foreground && _visible) unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_signals?.cancel());
    widget.controller.removeListener(_changed);
    widget.controller.repository.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller;
    final report = state.current ? state.report : null;
    final update = report?.update;
    final stale = state.error != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('识别信息更新任务'),
        actions: [IconButton(key: const Key('sf-update-refresh'), tooltip: '重新读取', onPressed: state.busy || !state.current ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: !state.current
            ? const Center(child: Text('盒子连接已变化，请重新打开原任务'))
            : state.busy && report == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.error != null) Text(state.error!, key: const Key('sf-update-error')),
                  if (stale && report != null) const Text('以下为上次读取结果；最新状态尚未确认。'),
                  if (state.busy) const LinearProgressIndicator(),
                  if (report == null)
                    OutlinedButton(onPressed: state.busy ? null : _refresh, child: const Text('重新读取原任务'))
                  else ...[
                    Text(
                      report.title,
                      key: const Key('sf-update-title'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text('父任务状态：${metadataUpdateStateLabel(update!.state)}'),
                    if (update.raw['error_message'] is String) Text(update.raw['error_message'] as String),
                    Text('原复制会话：${state.session?.state.label ?? '暂未取得'}（信息更新不改变复制结果）'),
                    if (!update.isTerminal) const Text('由盒子执行信息更新，离开页面不会重新创建或停止任务。'),
                    if (update.isTerminal && !report.complete) const Text('报告待补齐或核对；未提供的数字不会计为零。'),
                    if (report.partial) const Text('部分项目需要处理，已经安全更新的副本保留；不会自动回滚或重复制。'),
                    for (final issue in report.issues) Text(issue),
                    if (update.errorMessage != null) Text('原因：${update.errorMessage}') else if (update.state == 'failed' || (update.count('blocked_count') ?? 0) > 0) const Text('具体失败或受阻原因未提供'),
                    if (update.errorCode != null) Text('原因代码：${update.errorCode}'),
                    _card('父任务统计', [
                      const Text('来源：当前父任务响应。照片、文件和失败/受阻项分别计数。'),
                      _count('涉及更新子任务', update.count('child_job_count'), '批', 'children'),
                      _count('已更新照片', update.count('updated_asset_count'), '张', 'photos'),
                      _count('已更新文件', update.count('updated_file_count'), '个', 'files'),
                      _count('失败项目', update.count('failed_count'), '项', 'failed'),
                      _count('信息不变', update.count('unchanged_count'), '项', 'unchanged'),
                      _count('受阻项目', update.count('blocked_count'), '项', 'blocked'),
                    ]),
                    _card('子任务与原复制批次', [
                      if (report.children.isEmpty) Text(update.childrenProvided && update.count('child_job_count') == 0 ? '没有信息更新子任务' : '子任务报告尚未提供'),
                      for (var i = 0; i < report.children.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('更新子任务 ${i + 1} · ${metadataUpdateStateLabel(report.children[i].state)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              _count('已更新文件', report.children[i].count('updated_file_count'), '个', 'child-$i-files'),
                              _count('失败文件', report.children[i].count('failed_file_count'), '个', 'child-$i-failed'),
                              if (report.children[i].errorMessage != null)
                                Text('原因：${report.children[i].errorMessage}')
                              else if (report.children[i].state == 'failed' || report.children[i].state == 'completed_partial')
                                const Text('具体失败或受阻原因未提供'),
                              if (report.children[i].errorCode != null) Text('原因代码：${report.children[i].errorCode}'),
                              if (report.children[i].copyJobId == null)
                                const Text('原 CopyJob 关联未提供，暂不能打开详情')
                              else
                                OutlinedButton(key: Key('sf-update-copy-$i'), onPressed: stale || state.busy ? null : () => widget.onOpenCopy(report.children[i].copyJobId!), child: const Text('查看对应的原复制批次')),
                            ],
                          ),
                        ),
                      const Text('子信息更新结果使用父任务已提供的数据；原复制批次通过现有 RC3 详情查看。'),
                    ]),
                    if (update.isTerminal)
                      _card('再次检查信息变化', [
                        if (state.availabilityError != null)
                          Text(state.availabilityError!)
                        else if (!state.metadataEnabled)
                          const Text('当前未开放再次更新操作，原报告仍可查看。')
                        else if (state.otherActiveId != null)
                          OutlinedButton(key: const Key('sf-update-other-active'), onPressed: stale || state.busy ? null : () => widget.onOpenUpdate(state.otherActiveId!), child: const Text('查看当前信息更新任务'))
                        else if (state.availability?.available == true)
                          const Text('副本又有更新的识别信息。可重新预览并确认，不会直接写入。')
                        else
                          const Text('目前没有新的可更新信息；稍后产生变化仍会重新提示。'),
                        if (state.canPreview) FilledButton(key: const Key('sf-update-preview-again'), onPressed: widget.onOpenPreview, child: const Text('预览新的信息更新')),
                      ]),
                    if (state.history.isNotEmpty)
                      Card(
                        child: ExpansionTile(
                          key: const Key('sf-update-history'),
                          title: const Text('已知信息更新历史'),
                          children: [
                            for (var i = 0; i < state.history.length; i++)
                              ListTile(
                                title: Text('信息更新任务 ${i + 1}${state.history[i] == state.updateId ? '（当前查看）' : ''}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: stale || state.busy || state.history[i] == state.updateId ? null : () => widget.onOpenUpdate(state.history[i]),
                              ),
                          ],
                        ),
                      ),
                    const Text('本页只读取任务与报告。再次更新必须重新预览并由你确认。'),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.symmetric(vertical: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
  Widget _count(String label, int? value, String unit, String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(label),
        Text(value == null ? '未提供' : '$value $unit', key: Key('sf-update-$key')),
      ],
    ),
  );
}
