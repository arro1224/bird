import 'dart:async';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_device_policy.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_device_card.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter/material.dart';

class SmartFollowConfigurationForm extends StatefulWidget {
  const SmartFollowConfigurationForm({super.key, required this.reader, this.onChanged, this.expectedRecognitionJobId, this.expectedRecognitionPhase});
  final SmartFollowConfigurationReader reader;
  final String? expectedRecognitionJobId;
  final RecognitionEntryPhase? expectedRecognitionPhase;
  final ValueChanged<SmartFollowConfiguredIntent?>? onChanged;

  @override
  State<SmartFollowConfigurationForm> createState() => _SmartFollowConfigurationFormState();
}

class _SmartFollowConfigurationFormState extends State<SmartFollowConfigurationForm> with WidgetsBindingObserver {
  late SmartFollowConfigurationController _controller;
  SmartFollowConfiguredIntent? _lastReported;
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _controller = SmartFollowConfigurationController(widget.reader, expectedRecognitionJobId: widget.expectedRecognitionJobId, expectedRecognitionPhase: widget.expectedRecognitionPhase)..addListener(_changed);
    _subscription = widget.reader.changes?.listen((_) => _controller.invalidate());
    unawaited(_controller.refresh());
  }

  @override
  void didUpdateWidget(covariant SmartFollowConfigurationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reader != widget.reader || oldWidget.expectedRecognitionJobId != widget.expectedRecognitionJobId || oldWidget.expectedRecognitionPhase != widget.expectedRecognitionPhase) {
      final hadConfirmation = _lastReported != null;
      _controller.removeListener(_changed);
      _controller.dispose();
      unawaited(_subscription?.cancel());
      _lastReported = null;
      _attach();
      if (hadConfirmation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.confirmed == null) widget.onChanged?.call(null);
        });
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!identical(_lastReported, _controller.confirmed)) {
      _lastReported = _controller.confirmed;
      widget.onChanged?.call(_lastReported);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A backgrounded configuration is never silently considered confirmed.
    if (state != AppLifecycleState.resumed) _controller.invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller, data = state.snapshot;
    final locked = state.loading || state.confirming;
    return Column(
      key: const Key('smart-follow-configuration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (state.loading) const LinearProgressIndicator(),
        if (data != null) ...[
          Text('相机卡：${data.binding.displayName}（${data.binding.verifiedReadOnly ? '只读' : '只读绑定未确认'}）'),
          Text(data.entry.job == null ? '范围：即将开始的本轮识别' : '范围：当前这一轮识别'),
          const SizedBox(height: 12),
          const Text('选择目标设备', style: TextStyle(fontWeight: FontWeight.bold)),
          if (state.candidates.isEmpty) const Text('没有可用的目标设备。请将可写的 U 盘或移动硬盘接到盒子，再重新检测。'),
          for (final device in state.candidates) ...[
            StorageDeviceCard(device: device, role: '目标设备', selected: state.targetMediaId == device.mediaId, onTap: locked || state.targetBlockReason(device) != null ? null : () => state.selectTarget(device.mediaId)),
            if (CopyDevicePolicy.targetDisabledReason(device, sourceMediaId: data.binding.sourceMediaId) == null) Text(state.targetBlockReason(device) ?? '设备已连接，可写入复制副本。'),
          ],
          if (state.target case final target?) ...[
            Text('当前可用容量：${_bytes(target.freeBytes)} / ${_bytes(target.capacityBytes)}'),
            Text(target.identityStable ? '目标身份：由盒子稳定标识确认' : '目标身份：由盒子降级标识确认，恢复时仍需核验原盘'),
          ],
          const Text('持续跟随尚不能确定全部文件大小。盒子将在每批复制前检查空间；空间不足时保留队列并等待处理。'),
          const SizedBox(height: 12),
          DropdownButtonFormField<PairPolicy>(
            key: ValueKey(('smart-follow-pair-policy', state.pairPolicy)),
            initialValue: state.pairPolicy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '文件类型'),
            items: PairPolicy.values.map((policy) => DropdownMenuItem(value: policy, child: Text(policy.label))).toList(),
            onChanged: locked
                ? null
                : (value) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (value != null) state.selectPairPolicy(value);
                  },
          ),
          const Text('RAW 优先在无 RAW 时保留可用 JPEG/HEIF；两份都复制会分别计入实际文件数。'),
          const SizedBox(height: 12),
          DropdownButtonFormField<ConflictStrategy>(
            key: ValueKey(('smart-follow-conflict-policy', state.conflictStrategy)),
            initialValue: state.conflictStrategy,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '同名文件处理（必选）', hintText: '请明确选择'),
            items: ConflictStrategy.values.map((strategy) => DropdownMenuItem(value: strategy, child: Text(strategy.label))).toList(),
            onChanged: locked
                ? null
                : (value) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (value != null) state.selectConflict(value);
                  },
          ),
          SwitchListTile(
            key: const Key('smart-follow-review-export'),
            contentPadding: EdgeInsets.zero,
            title: const Text('随副本保存识别与审阅信息'),
            subtitle: Text(data.copyCapabilities.reviewExportReady ? '安全支持时优先写入副本，否则保存配套信息；相机卡始终只读。' : '当前盒子未开放随副本保存信息，本次只复制照片。'),
            value: state.reviewExportEnabled,
            onChanged: locked || !data.copyCapabilities.reviewExportReady ? null : state.setReviewExport,
          ),
        ],
        if (state.error != null) Text(UserMessageMapper.fromCopyConfigurationError(state.error!).message),
        if (state.notice != null) Text(state.notice!),
        if (state.blockReason != null) Text(state.blockReason!),
        TextButton(key: const Key('smart-follow-refresh-configuration'), onPressed: locked ? null : state.refresh, child: const Text('重新检测设备')),
        FilledButton(
          key: const Key('smart-follow-confirm-configuration'),
          onPressed: locked || state.blockReason != null ? null : state.confirm,
          child: Text(state.confirming ? '正在核对配置…' : '1. 确认设备与复制策略'),
        ),
        if (state.confirmed case final intent?) ...[
          const SizedBox(height: 8),
          Text('配置已确认：${intent.targetName}；${state.pairPolicy.label}；${state.conflictStrategy!.label}；${intent.request.reviewExportEnabled ? '保存识别与审阅信息' : '仅复制照片'}。下一步开始导入后将自动识别，并自动复制符合条件的照片；现在尚未开始。', key: const Key('smart-follow-configuration-confirmed')),
          OutlinedButton(key: const Key('smart-follow-cancel-configuration'), onPressed: state.invalidate, child: const Text('撤销本次确认')),
        ],
      ],
    );
  }

  static String _bytes(int bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
