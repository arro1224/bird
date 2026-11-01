import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_controller.dart';

class SmartFollowMetadataPreviewPage extends StatefulWidget {
  const SmartFollowMetadataPreviewPage({super.key, required this.controller, required this.onOpenUpdate, this.refreshSignals});
  final SmartFollowMetadataController controller;
  final void Function(String) onOpenUpdate;
  final Stream<void>? refreshSignals;
  @override
  State<SmartFollowMetadataPreviewPage> createState() => _SmartFollowMetadataPreviewPageState();
}

class _SmartFollowMetadataPreviewPageState extends State<SmartFollowMetadataPreviewPage> with WidgetsBindingObserver {
  StreamSubscription<void>? _signals;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _signals = widget.refreshSignals?.listen((_) {
      widget.controller.invalidate();
      if (mounted) setState(() {});
    });
    unawaited(widget.controller.prepare());
  }

  void _changed() {
    _expiry?.cancel();
    final deadline = widget.controller.preview?.expiresAt;
    if (deadline != null && deadline.isAfter(widget.controller.now())) _expiry = Timer(deadline.difference(widget.controller.now()), widget.controller.invalidate);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.controller.invalidate();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_signals?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller;
    final preview = state.current ? state.preview : null;
    final active = state.activeUpdateId;
    return Scaffold(
      appBar: AppBar(title: const Text('预览识别信息更新')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!state.current)
              const Text('盒子连接已变化，请重新打开原任务')
            else if (state.busy)
              const Center(
                child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
              )
            else ...[
              if (state.error != null) Text(state.error!, key: const Key('sf-metadata-error')),
              if (active != null) ...[
                Text(state.createdUpdate != null ? '信息更新任务已提交。提交成功不代表信息已全部保存。' : '已有信息更新任务，不会重复创建。'),
                FilledButton(key: const Key('sf-metadata-view-existing'), onPressed: () => widget.onOpenUpdate(active), child: const Text('查看信息更新任务')),
              ] else if (state.outcomeUnknown) ...[
                const Text('上次信息更新结果仍待确认。先查询原任务，不生成新的写入请求。'),
                OutlinedButton(key: const Key('sf-metadata-recover'), onPressed: state.refresh, child: const Text('查询原任务')),
              ] else if (!state.enabled)
                const Text('当前盒子未开放统一信息更新，无法提交。')
              else if (state.availability?.available != true)
                const Text('当前没有可更新的识别信息。'),
              if (preview != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('请核对本次更新范围', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(state.recognitionFinished ? '本轮识别已结束' : '识别仍在进行；这里只保存当前已有信息，以后仍可能需要再次更新。'),
                        const SizedBox(height: 12),
                        Text('目标盘：${CopyJobDeviceSnapshot(mediaId: preview.targetMediaId, displayName: preview.targetDisplayName).presentationLabel ?? '名称未提供'}'),
                        _count('涉及复制批次', preview.count('child_job_count'), '批', 'batches'),
                        _count('可更新照片', preview.count('updatable_asset_count'), '张', 'photos'),
                        _count('可更新文件', preview.count('updatable_file_count'), '个', 'files'),
                        _count('信息不变', preview.count('unchanged_count'), '项', 'unchanged'),
                        _count('受阻项目', preview.count('blocked_count'), '项', 'blocked'),
                        _count('冲突项目', preview.count('conflict_count'), '项', 'conflicts'),
                        _count('预计写入空间', preview.count('estimated_bytes'), 'B', 'bytes'),
                        Text('预计写入方式：${preview.writeModeLabel}'),
                        Text(preview.expiresAt == null ? '有效期：未提供' : '预览有效至：${preview.expiresAt!.toLocal()}'),
                        for (final reason in preview.blockedReasons) Text('受阻原因：$reason'),
                        if (state.previewIssue != null) Text(state.previewIssue!, key: const Key('sf-metadata-preview-issue')),
                        if (preview.needsPartialConsent)
                          CheckboxListTile(
                            key: const Key('sf-metadata-partial-consent'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: state.partialConsent,
                            onChanged: (value) => state.setPartialConsent(value == true),
                            title: const Text('我已了解只能部分更新，同意仅更新安全可更新的副本，跳过受阻和冲突项目。'),
                          ),
                        FilledButton(key: const Key('sf-metadata-confirm'), onPressed: state.canSubmit ? state.confirm : null, child: Text(preview.needsPartialConsent ? '确认部分更新' : '确认更新识别信息')),
                      ],
                    ),
                  ),
                ),
              if (active == null && !state.outcomeUnknown && state.enabled) OutlinedButton(key: const Key('sf-metadata-reload-preview'), onPressed: state.prepare, child: const Text('重新获取预览')),
              const Text('仅更新已复制副本的识别与审阅信息，不重新复制照片。取消或返回不会提交写入任务。'),
              TextButton(key: const Key('sf-metadata-cancel'), onPressed: () => Navigator.of(context).maybePop(), child: Text(active == null ? '取消' : '返回')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int? value, String unit, String id) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(label),
        Text(value == null ? '未提供' : '$value $unit', key: Key('sf-metadata-preview-$id')),
      ],
    ),
  );
}
