import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
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
      final response = await widget.repository.api.get(ApiEndpoints.storageDevices, headers: {'X-BirdBox-Protocol': 'birdbox-copy-v1', 'X-BirdBox-Copy-Revision': '1.0-rc3'});
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

