import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_controller.dart';

/// C1 only reads results. Updating saved recognition information requires a
/// separate preview and user confirmation (SF-B5), never a completion callback.
class SmartFollowCompletionPage extends StatefulWidget {
  const SmartFollowCompletionPage({super.key, required this.controller, required this.onOpenRun, required this.onOpenChild, this.refreshSignals, this.metadataSection});
  final SmartFollowCompletionController controller;
  final VoidCallback onOpenRun;
  final void Function(String) onOpenChild;
  final Stream<void>? refreshSignals;
  final Widget? metadataSection;

  @override
  State<SmartFollowCompletionPage> createState() => _SmartFollowCompletionPageState();
}

class _SmartFollowCompletionPageState extends State<SmartFollowCompletionPage> with WidgetsBindingObserver {
  StreamSubscription<void>? _signals;
  bool _foreground = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _signals = widget.refreshSignals?.listen((_) {
      if (mounted) setState(() {});
      if (_foreground && _visible) unawaited(widget.controller.refresh());
    });
    unawaited(widget.controller.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (visible && !_visible && _foreground) unawaited(widget.controller.refresh());
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _visible) unawaited(widget.controller.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_signals?.cancel());
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final current = controller.isCurrent?.call() ?? true;
    final result = current ? controller.result : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('边识别边复制结果'),
        actions: [IconButton(key: const Key('sf-completion-refresh'), tooltip: '刷新结果', onPressed: controller.busy || !current ? null : controller.refresh, icon: const Icon(Icons.refresh))],
      ),
      body: SafeArea(
        child: controller.busy && current
            ? const Center(child: CircularProgressIndicator())
            : result == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(current ? controller.error ?? '结果暂不可用' : '盒子连接已变化，请重新打开原任务'),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: current ? controller.refresh : null, child: const Text('重新读取结果')),
                    ],
                  ),
                ),
              )
            : ListView(padding: const EdgeInsets.all(16), children: _content(result)),
      ),
    );
  }

  List<Widget> _content(SmartFollowCompletionResult result) {
    if (!result.session.isFinished) {
      return [
        const Text('仍在处理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('当前会话尚未结束，请回到运行页查看识别和复制进度。'),
        FilledButton(key: const Key('sf-completion-open-run'), onPressed: widget.onOpenRun, child: const Text('查看运行进度')),
      ];
    }
    final report = result.recognitionReport;
    return [
      Text(
        result.title,
        key: const Key('sf-completion-title'),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text('会话状态：${result.session.state.label}'),
      if (result.sessionCount('eligible_count') == 0 && result.historyComplete && result.children.isEmpty) const Text('本轮没有符合自动复制条件的照片。'),
      if (!result.summaryComplete) const Text('报告待补齐或核对。已取得的会话数据仅代表对应字段，不表示全部成功。'),
      for (final issue in result.issues) Padding(padding: const EdgeInsets.only(top: 8), child: Text(issue)),
      if (result.session.errorMessage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('结束原因：${result.session.errorMessage}')),
      if (result.session.errorCode != null) Text('原因代码：${result.session.errorCode}'),
      _section('本轮识别', [
        Text(
          report != null
              ? '来源：本轮识别任务的终态报告'
              : result.recognition == null || {BirdJobState.completed, BirdJobState.failed, BirdJobState.cancelled}.contains(result.recognition?.state)
              ? '识别报告待补齐'
              : '识别尚未结束（${result.recognition!.state.label}），复制会话结束不会停止识别。',
        ),
        _metric('识别总数', report?.totalCount ?? result.recognition?.totalCount, '张', 'recognition-total'),
        _metric('识别成功', report?.successCount, '张', 'recognition-success'),
        _metric('待确认', null, '张', 'recognition-review'),
        _metric('识别跳过', report?.skippedCount, '张', 'recognition-skipped'),
        _metric('识别失败', report?.failedCount, '张', 'recognition-failed'),
        const Text('识别成功为任务处理结果；符合自动复制条件的照片数另列。待确认分类当前未提供。'),
      ]),
      _section('复制结果', [
        const Text('来源：权威会话（照片与文件分别计数）'),
        _metric('符合复制条件', result.sessionCount('eligible_count'), '张', 'eligible'),
        _metric('已复制照片', result.sessionCount('copied_asset_count'), '张', 'copied-photos'),
        _metric('已复制文件', result.sessionCount('copied_file_count'), '个', 'copied-files'),
        _metric('复制失败照片', result.sessionCount('failed_asset_count'), '张', 'failed-photos'),
        const Divider(),
        Text(result.reportsComplete ? '来源：全部终态复制批次报告；实际字节取复制批次详情' : '全部批次报告尚未齐全，以下汇总暂不展示'),
        _metric('跳过同名文件', result.skippedFiles, '个', 'skipped-files'),
        _metric('覆盖文件', null, '个', 'overwritten-files'),
        _metric('失败文件', result.failedFiles, '个', 'failed-files'),
        _metric('不适用文件', result.notApplicableFiles, '个', 'not-applicable-files'),
        _metric('实际复制字节', result.copiedBytes, 'B', 'copied-bytes'),
        const Text('RAW＋JPEG 可对应多个文件。覆盖统计当前未提供；计划大小、待入队和已分配数量不计入复制成功。'),
      ]),
      _section('识别信息保存', [
        Text(result.informationStatus, key: const Key('sf-completion-information')),
        const Text('来源：各批次冻结配置及终态报告。复制成功不代表识别信息保存成功。'),
        if (widget.metadataSection == null && result.session.metadataUpdateAvailable) const Text('已复制照片的识别信息有变化。后续统一更新需先预览并由你确认。'),
        if (widget.metadataSection == null && result.session.activeMetadataUpdateId != null) const Text('存在识别信息更新任务，其结果需单独确认。'),
        const Text('本页不会自动重写目标盘信息。'),
      ]),
      if (widget.metadataSection != null) widget.metadataSection!,
      Card(
        child: ExpansionTile(
          key: const Key('sf-completion-history'),
          title: Text('复制批次历史（${result.children.length}）'),
          subtitle: Text(result.historyComplete ? '已读取全部分页并去重' : '列表待补齐'),
          children: [
            if (result.children.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(result.historyComplete ? '没有复制批次' : '暂未取得批次')),
            for (var i = 0; i < result.children.length; i++) _child(result.children[i], i),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(onPressed: widget.onOpenRun, child: const Text('查看会话详情')),
    ];
  }

  Widget _child(SmartFollowCompletionChild child, int index) {
    final report = child.report;
    return ListTile(
      key: Key('sf-completion-child-${child.job.copyJobId}'),
      title: Text('批次 ${index + 1} · ${child.detail?.state.label ?? child.job.state.label}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (child.issue != null) Text(child.issue!),
          Text('已复制文件：${report?.copiedFiles ?? '未提供'}；失败：${report?.failedFiles ?? '未提供'}'),
          Text(
            '信息保存：${child.detail?.reviewExportEnabled == false ? '未开启' : 'CSV ${_csv(report?.csvStatus)}；XMP ${report?.xmpCount ?? '未提供'}；嵌入 ${report?.embedSuccessCount ?? '未提供'}；降级 ${report?.embedDegradedCount ?? '未提供'}；导出失败 ${report?.exportFailedCount ?? '未提供'}'}',
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => widget.onOpenChild(child.job.copyJobId),
    );
  }

  String _csv(String? value) => switch (value) {
    'success' => '成功',
    'failed' => '失败',
    null => '未提供',
    _ => '状态待确认',
  };

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(top: 16),
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

  Widget _metric(String label, int? value, String unit, String id) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 16,
      runSpacing: 4,
      children: [
        Text(label),
        Text(
          value == null ? '未提供' : '$value $unit',
          key: Key('sf-completion-$id'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
