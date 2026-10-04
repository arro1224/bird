import 'dart:async';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:flutter/material.dart';

class RecognitionOptions extends StatefulWidget {
  const RecognitionOptions({super.key, required this.repository, required this.onChanged});
  final RecognitionRepository repository;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  @override
  State<RecognitionOptions> createState() => _RecognitionOptionsState();
}

class _RecognitionOptionsState extends State<RecognitionOptions> {
  bool available = false;
  bool enabled = false;
  bool loaded = false;
  Object? error;
  List<Map<String, dynamic>> targets = [];
  String? target;
  String policy = 'raw_only';
  String conflict = 'skip';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final caps = await widget.repository.capabilities();
      final canUse = (caps['smart_follow_copy'] as Map?)?['available'] == true;
      if (!canUse) {
        if (mounted) setState(() => loaded = true);
        return;
      }
      final response = await widget.repository.api.get('/api/v1/storage/devices', headers: {'X-BirdBox-Protocol': 'birdbox-copy-v1', 'X-BirdBox-Copy-Revision': '1.0-rc3'});
      final data = response;
      final devices = (data['devices'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => e['can_be_target'] == true).toList();
      if (!mounted) return;
      setState(() {
        available = true;
        loaded = true;
        targets = devices;
        target = devices.isEmpty ? null : devices.first['media_id'] as String;
      });
    } on ApiException catch (caught) {
      if (mounted) {
        setState(() {
          loaded = true;
          if (caught.statusCode != 404) error = caught.message;
        });
      }
    } catch (caught) {
      if (mounted) {
        setState(() {
          loaded = true;
          error = caught;
        });
      }
    }
  }

  void _changed() => widget.onChanged(enabled && target != null ? {'target_media_id': target, 'pair_policy': policy, 'conflict_strategy': conflict} : null);

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    if (error != null) return Text('智能复制选项读取失败：$error');
    if (!available) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('smart-follow-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('识别并智能复制'),
          subtitle: Text(targets.isEmpty ? '请先插入可写的目标盘。当前仅识别。' : '边识别边复制合格照片，原卡保持只读'),
          value: enabled,
          onChanged: targets.isEmpty
              ? null
              : (value) {
                  setState(() => enabled = value);
                  _changed();
                },
        ),
        if (enabled) ...[
          DropdownButtonFormField<String>(
            key: const Key('smart-follow-target'),
            initialValue: target,
            decoration: const InputDecoration(labelText: '复制到'),
            items: targets.map((t) => DropdownMenuItem(value: t['media_id'] as String, child: Text(t['display_name'] as String? ?? '目标盘'))).toList(),
            onChanged: (value) {
              setState(() => target = value);
              _changed();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: policy,
            decoration: const InputDecoration(labelText: '文件类型'),
            items: const [
              DropdownMenuItem(value: 'raw_only', child: Text('RAW 优先，无 RAW 时复制 JPEG')),
              DropdownMenuItem(value: 'jpeg_only', child: Text('仅 JPEG')),
              DropdownMenuItem(value: 'both', child: Text('RAW 和 JPEG')),
            ],
            onChanged: (value) {
              setState(() => policy = value!);
              _changed();
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: conflict,
            decoration: const InputDecoration(labelText: '遇到同名文件'),
            items: const [
              DropdownMenuItem(value: 'skip', child: Text('跳过')),
              DropdownMenuItem(value: 'keep_both', child: Text('保留两份')),
              DropdownMenuItem(value: 'overwrite', child: Text('覆盖目标盘文件')),
            ],
            onChanged: (value) {
              setState(() => conflict = value!);
              _changed();
            },
          ),
        ],
      ],
    );
  }
}

class RecognitionChoice {
  const RecognitionChoice(this.config);
  final Map<String, dynamic>? config;
}

Future<RecognitionChoice?> chooseRecognitionMode(BuildContext context, RecognitionRepository repo) async {
  Map<String, dynamic> caps;
  try {
    caps = await repo.capabilities();
  } on ApiException catch (error) {
    if (error.statusCode == 404) return const RecognitionChoice(null);
    rethrow;
  }
  if (!context.mounted) return null;
  if ((caps['smart_follow_copy'] as Map?)?['available'] != true) return const RecognitionChoice(null);
  Map<String, dynamic>? selected;
  return showDialog<RecognitionChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('开始识别'),
      content: SingleChildScrollView(
        child: RecognitionOptions(repository: repo, onChanged: (value) => selected = value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, RecognitionChoice(selected)), child: const Text('开始识别')),
      ],
    ),
  );
}

class RecognitionPanel extends StatefulWidget {
  const RecognitionPanel({super.key, required this.repository, required this.jobId});
  final RecognitionRepository repository;
  final String jobId;
  @override
  State<RecognitionPanel> createState() => _RecognitionPanelState();
}

class _RecognitionPanelState extends State<RecognitionPanel> {
  Timer? _timer;
  bool available = false;
  bool canFollow = false;
  bool busy = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    unawaited(_initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      final caps = await widget.repository.capabilities();
      if (!mounted) return;
      available = (caps['incremental_recognition_results'] as Map?)?['available'] == true;
      canFollow = (caps['smart_follow_copy'] as Map?)?['available'] == true;
      if (available) {
        await _refresh();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_refresh()));
      }
      _changed();
    } on ApiException catch (caught) {
      if (caught.statusCode != 404) {
        error = caught.message;
        _changed();
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.repository.sync(widget.jobId);
      error = null;
    } catch (caught) {
      error = caught;
    }
    _changed();
  }

  Future<void> _operate(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      error = null;
    } catch (caught) {
      error = caught;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _enable() async {
    Map<String, dynamic>? selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启智能复制'),
        content: SingleChildScrollView(
          child: RecognitionOptions(repository: widget.repository, onChanged: (value) => selected = value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (selected != null) Navigator.pop(context, true);
            },
            child: const Text('开启'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _operate(() => widget.repository.startFollow(widget.jobId, selected!));
  }

  Future<void> _children(String session) async {
    final children = await widget.repository.childJobs(session);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('复制批次')),
          for (var i = 0; i < children.length; i++)
            ListTile(
              title: Text('第 ${i + 1} 批'),
              subtitle: Text(_label(children[i]['state'] as String, copy: true)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(this.context).pushNamed(BirdRoutes.copyJobDetail, arguments: CopyJobDetailArgs(children[i]['copy_job_id'] as String));
              },
            ),
        ],
      ),
    );
  }

  String _label(String state, {bool copy = false}) => switch (state) {
    'following' => '持续识别并复制合格照片',
    'running' => copy ? '复制中' : '识别进行中',
    'queued' => '排队中',
    'draining' => '识别结束，正在完成复制',
    'waiting_for_source' => '等待原相机卡',
    'waiting_for_target' => '等待原目标盘',
    'completed' => '已完成',
    'completed_partial' || 'completed_with_errors' => '部分完成',
    'recognition_interrupted' => '识别中断，已完成结果保留',
    'reconciliation_error' => '结果对账失败，请查看日志',
    'paused' => '已暂停',
    'failed' => '失败，请查看错误',
    _ => state,
  };

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    final snapshot = widget.repository.snapshot(widget.jobId);
    final follow = snapshot?['smart_follow'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '识别与复制',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.forestDeep),
            ),
            const SizedBox(height: 12),
            Text('已产生结果 ${snapshot?['committed_count'] ?? 0} 张 · 识别失败 ${snapshot?['failed_count'] ?? 0} 张'),
            Text(_label(snapshot?['state'] as String? ?? 'queued')),
            if (canFollow && follow == null && snapshot?['state'] == 'running') FilledButton(onPressed: busy ? null : _enable, child: const Text('开启智能复制')),
            if (follow != null) ...[
              const Divider(height: 24),
              Text(_label(follow['state'] as String)),
              Text('合格 ${follow['eligible_count']} 张 · 待复制 ${follow['pending_count']} 张'),
              Text('复制批次 ${follow['child_job_count']} 个 · 已复制 ${follow['copied_asset_count']} 组照片'),
              TextButton(onPressed: busy ? null : () => _operate(() => _children(follow['session_id'] as String)), child: const Text('查看复制批次')),
              for (final action in follow['allowed_actions'] as List)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (action == 'finish_current_results') {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('完成当前结果？'),
                                content: const Text('只完成已经识别出的合格照片复制，不继续识别剩余照片。'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('返回')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;
                          }
                          await _operate(() => widget.repository.action(widget.jobId, action as String));
                        },
                  child: Text(action == 'resume_recognition' ? '恢复识别未完成照片' : '完成当前结果'),
                ),
              if (follow['error_message'] != null) Text(follow['error_message'] as String, style: const TextStyle(color: AppColors.danger)),
            ],
            if (error != null) Text('状态更新失败：$error', style: const TextStyle(color: AppColors.danger)),
            const Text('退出 App 不会停止盒子的识别和复制。', style: TextStyle(color: AppColors.mutedInk)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.repository.removeListener(_changed);
    super.dispose();
  }
}
