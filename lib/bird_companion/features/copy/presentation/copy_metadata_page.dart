import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';

/// Ordinary CopyJob context. Never invents a SmartFollow session or copies files.
class CopyMetadataController extends ChangeNotifier {
  CopyMetadataController({required this.client, required this.storage, required this.copyJobId, required this.deviceKey, required this.currentKey});
  final ApiClient client;
  final DiagnosticStorage storage;
  final String copyJobId, deviceKey;
  final String? Function() currentKey;
  static const headers = {'X-BirdBox-Copy-Revision': '1.0-rc3', 'X-BirdBox-Protocol': 'birdbox-copy-v1'};
  static const exportOptions = {'policy': 'safe_embed_first', 'content_schema': 'birdbox-review-effective-v2'};
  static SmartFollowMetadataUpdate _parent(Map<String, dynamic> raw) => SmartFollowMetadataUpdate.fromJson(Map<String, dynamic>.from(raw['parent_update'] as Map? ?? raw));
  String get _root => ApiEndpoints.copyMetadataRoot(copyJobId);
  String get _slot => 'copy-metadata:$deviceKey:$copyJobId';
  SmartFollowMetadataAvailability? availability;
  SmartFollowMetadataPreview? preview;
  SmartFollowMetadataUpdate? update;
  String? error;
  bool enabled = false, busy = false, disposed = false, partialConsent = false;
  bool get current => !disposed && currentKey() == deviceKey;
  bool get pending => storage.read<Map>(_slot) != null;
  bool get canConfirm =>
      current &&
      !busy &&
      enabled &&
      !pending &&
      preview?.hasUpdatableItems == true &&
      !preview!.isExpired &&
      preview!.knownCounts.containsAll(SmartFollowMetadataPreview.countKeys) &&
      preview!.partialConfirmationKnown &&
      preview!.hasKnownWriteMode &&
      (!preview!.needsPartialConsent || partialConsent);
  void _check() {
    if (!current) throw StateError('请重新连接原盒子并打开原任务');
  }

  void _emit() {
    if (current) notifyListeners();
  }

  Future<void> refresh() async {
    if (busy || !current) return;
    busy = true;
    error = null;
    _emit();
    try {
      final caps = await client.get(ApiEndpoints.copyCapabilities, headers: headers);
      _check();
      enabled = caps['metadata_export_ready'] == true;
      if (!enabled) {
        preview = null;
        return;
      }
      final context = await client.get('$_root/metadata-update-context', headers: headers);
      _check();
      if (context['context_type'] != 'copy_job' || context['copy_job_id'] != copyJobId) throw StateError('复制任务关联不一致，不能更新');
      availability = SmartFollowMetadataAvailability.fromJson(await client.get('$_root/metadata-update-availability', headers: headers));
      _check();
      final saved = storage.read<Map>(_slot);
      final id = context['active_metadata_update_id'] ?? saved?['update_id'] ?? context['latest_metadata_update_id'];
      if (id is String && id.isNotEmpty) {
        final value = SmartFollowMetadataUpdate.fromJson(await client.get(ApiEndpoints.metadataUpdate(id)));
        _check();
        update = value;
        if (value.childrenSettled) await storage.remove(_slot);
      } else if (saved != null) {
        // Unknown create result: replay exactly the persisted body and key.
        final raw = await client.post('$_root/metadata-updates', data: Map<String, dynamic>.from(saved['body'] as Map), headers: headers, idempotencyKey: saved['key'] as String);
        _check();
        update = _parent(raw);
        await storage.write(_slot, {...saved, 'update_id': update!.updateId});
      }
    } catch (e) {
      if (current) error = '读取失败，请重试。原任务与确认记录已保留。';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> prepare() async {
    if (busy || !current || !enabled || pending) return;
    busy = true;
    error = null;
    preview = null;
    partialConsent = false;
    _emit();
    try {
      final raw = await client.post('$_root/metadata-updates/preview', data: <String, dynamic>{'explicit_export_opt_in': true, 'export_options': exportOptions}, headers: headers);
      _check();
      preview = SmartFollowMetadataPreview.fromJson(raw);
    } catch (_) {
      if (current) error = '无法生成预览，请刷新后重试；没有写入照片。';
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> confirm() async {
    if (!canConfirm) return;
    busy = true;
    error = null;
    _emit();
    try {
      final original = preview!;
      final latest = SmartFollowMetadataPreview.fromJson(await client.get(ApiEndpoints.metadataPreview(original.previewId), headers: headers));
      _check();
      if (latest.previewToken != original.previewToken || latest.isExpired || latest.updatableFileCount != original.updatableFileCount || latest.targetMediaId != original.targetMediaId || latest.blockedCount != original.blockedCount) {
        throw StateError('预览已变化');
      }
      final body = {'preview_token': original.previewToken, 'accept_partial': partialConsent, 'explicit_export_opt_in': true, 'export_options': exportOptions};
      final key = 'copy-md-$copyJobId-${original.previewToken}';
      await storage.write(_slot, {'key': key, 'body': body});
      _check();
      final raw = await client.post('$_root/metadata-updates', data: body, headers: headers, idempotencyKey: key);
      _check();
      update = _parent(raw);
      await storage.write(_slot, {'key': key, 'body': body, 'update_id': update!.updateId});
      preview = null;
    } catch (_) {
      if (current) error = pending ? '提交结果待确认，请查询原任务，不要重新创建。' : '预览已变化，请刷新并重新核对。';
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class CopyMetadataPage extends StatefulWidget {
  const CopyMetadataPage({super.key, required this.controller});
  final CopyMetadataController controller;
  @override
  State<CopyMetadataPage> createState() => _CopyMetadataPageState();
}

/// Polls the real ordinary-copy context after completion, including when
/// recognition finishes later. A new result changes the button, not the disk.
class CopyMetadataEntry extends StatefulWidget {
  const CopyMetadataEntry({super.key, required this.createController});
  final CopyMetadataController Function() createController;
  @override
  State<CopyMetadataEntry> createState() => _CopyMetadataEntryState();
}

class _CopyMetadataEntryState extends State<CopyMetadataEntry> with WidgetsBindingObserver {
  late final controller = widget.createController();
  Timer? timer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  Future<void> refresh() async {
    timer?.cancel();
    await controller.refresh();
    if (!mounted) return;
    setState(() {});
    if (foreground && controller.current) timer = Timer(const Duration(seconds: 4), () => unawaited(refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    timer?.cancel();
    if (foreground) unawaited(refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.current || !controller.enabled) return const SizedBox.shrink();
    final available = controller.availability?.available == true;
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.edit_note),
      label: Text(
        controller.pending
            ? '查看正在保存的信息'
            : controller.availability?.blockedAssetCount != 0 && controller.availability != null
            ? '查看信息更新受阻原因'
            : available
            ? '更新识别信息'
            : '查看已保存的副本信息',
      ),
      onPressed: controller.busy
          ? null
          : () async {
              timer?.cancel();
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CopyMetadataPage(controller: widget.createController())));
              if (mounted) await refresh();
            },
    );
  }
}

class _CopyMetadataPageState extends State<CopyMetadataPage> with WidgetsBindingObserver {
  Timer? timer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(changed);
    unawaited(refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    timer?.cancel();
    await widget.controller.refresh();
    if (mounted) setState(() {});
    if (mounted && foreground && widget.controller.current) timer = Timer(const Duration(seconds: 4), () => unawaited(refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      widget.controller.preview = null;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(changed);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = widget.controller.preview, u = widget.controller.update;
    final report = u == null ? null : SmartFollowMetadataUpdateReport(u);
    return Scaffold(
      appBar: AppBar(title: const Text('更新副本识别信息')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('只更新本复制任务的目标副本信息，不重新复制照片，不修改相机卡原片。'),
          const SizedBox(height: 16),
          if (!c.current)
            const Text('请连接原盒子并重新打开任务。')
          else ...[
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null) Text(c.error!),
            if (!c.enabled) const Text('当前盒子未开放安全信息更新。'),
            if (c.availability != null) Text('可更新 ${c.availability!.updatableAssetCount} 张 · 受阻 ${c.availability!.blockedAssetCount} 张'),
            if (u != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report!.title),
                      if (u.raw['error_message'] is String) Text(u.raw['error_message'] as String),
                      Text('已更新 ${u.updatedAssetCount} 张 / ${u.updatedFileCount} 个文件；失败 ${u.failedCount} 个文件'),
                      for (final child in u.childUpdates) Text('原复制任务 ${child.copyJobId}：${metadataUpdateStateLabel(child.state)}'),
                    ],
                  ),
                ),
              ),
            if (p != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('目标盘：${p.targetDisplayName ?? '未提供'}'),
                      Text('更新 ${p.updatableAssetCount} 张 / ${p.updatableFileCount} 个文件；不变 ${p.unchangedCount} 张；受阻 ${p.blockedCount} 张'),
                      Text(p.writeModeLabel),
                      for (final reason in p.blockedReasons) Text(reason),
                      if (p.needsPartialConsent) CheckboxListTile(title: const Text('我确认只更新可安全处理的部分'), value: c.partialConsent, onChanged: c.busy ? null : (v) => setState(() => c.partialConsent = v == true)),
                      FilledButton(onPressed: c.canConfirm ? c.confirm : null, child: const Text('确认更新信息')),
                    ],
                  ),
                ),
              ),
            OutlinedButton(onPressed: c.busy ? null : refresh, child: const Text('刷新 / 查询原任务')),
            if (c.enabled && !c.pending && c.availability?.available == true && (u == null || u.childrenSettled)) FilledButton(onPressed: c.busy ? null : c.prepare, child: const Text('预览更新范围')),
          ],
        ],
      ),
    );
  }
}
