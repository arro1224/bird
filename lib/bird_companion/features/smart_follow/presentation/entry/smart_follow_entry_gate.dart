import 'dart:async';

import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter/material.dart';

/// 入口能力门控（分工任务书 F5）。
///
/// 三态，全部由后端 capability 决定，**不做本地假实现**（App 修改任务书 §4/§10）：
/// - 加载中：默认什么都不显示（`placeholder` 可换骨架）；
/// - 可用：`builder`；
/// - 不可用：给了 `disabledBuilder` 就渲染"当前盒子版本暂不支持…"，否则整块隐藏。
///
/// 旧盒子 404 与 `available=false` 走同一条"不可用"分支，仓储已把 404 归一。
class SmartFollowEntryGate extends StatefulWidget {
  const SmartFollowEntryGate({
    super.key,
    required this.repository,
    required this.builder,
    this.disabledBuilder,
    this.placeholder,
    this.requireMetadataUpdate = false,
  });

  final SmartFollowRepository repository;

  /// 能力就绪时构建入口。
  final Widget Function(BuildContext context, SmartFollowCapabilities capabilities) builder;

  /// 能力未就绪时是否仍显示说明（默认隐藏）。
  final WidgetBuilder? disabledBuilder;

  /// 加载中的占位；默认不占位，避免布局跳动。
  final WidgetBuilder? placeholder;

  /// true 时额外要求信息统一更新能力（用于"更新识别信息"按钮）。
  final bool requireMetadataUpdate;

  @override
  State<SmartFollowEntryGate> createState() => _SmartFollowEntryGateState();
}

class _SmartFollowEntryGateState extends State<SmartFollowEntryGate> {
  SmartFollowCapabilities? _capabilities;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// 换盒子/换仓储（重连、切换设备）时重新读能力，不能沿用上一台盒子的结论。
  @override
  void didUpdateWidget(covariant SmartFollowEntryGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.repository, widget.repository) && oldWidget.requireMetadataUpdate == widget.requireMetadataUpdate) {
      return;
    }
    _capabilities = null;
    _failed = false;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final capabilities = await widget.repository.capabilities();
      if (!mounted) return;
      setState(() {
        _capabilities = capabilities;
        _failed = false;
      });
    } catch (_) {
      // 读能力失败按"不可用"处理：宁可不显示入口，也不让用户点进去必然失败。
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  bool _usable(SmartFollowCapabilities capabilities) =>
      widget.requireMetadataUpdate ? capabilities.canUpdateMetadata : capabilities.canShowEntry;

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    if (capabilities == null) {
      final placeholder = widget.placeholder;
      if (_failed) return const SizedBox.shrink();
      return placeholder == null ? const SizedBox.shrink() : Builder(builder: placeholder);
    }
    if (_usable(capabilities)) return widget.builder(context, capabilities);
    final disabled = widget.disabledBuilder;
    return disabled == null ? const SizedBox.shrink() : Builder(builder: disabled);
  }
}
