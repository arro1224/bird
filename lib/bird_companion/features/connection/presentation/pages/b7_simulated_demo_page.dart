import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_background.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:flutter/material.dart';

/// A runnable B7 simulated flow for demonstrations and acceptance recordings.
///
/// This widget owns synthetic state only. Production composition never creates
/// it, so it cannot replace the real BLE/Wi-Fi/DPP implementations.
class B7SimulatedDemoPage extends StatefulWidget {
  const B7SimulatedDemoPage({super.key});

  @override
  State<B7SimulatedDemoPage> createState() => _B7SimulatedDemoPageState();
}

enum _DemoStep { discovery, pairing, methods, directAp, complete }

class _B7SimulatedDemoPageState extends State<B7SimulatedDemoPage> {
  _DemoStep _step = _DemoStep.discovery;
  bool _wifiExpanded = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: ConnectionBackground(
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: const Text('B7 模拟配网'),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            Expanded(child: _content()),
          ],
        ),
      ),
    ),
  );

  Widget _content() => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.sm,
      AppSpacing.pageHorizontal,
      AppSpacing.xxl,
    ),
    children: [
      const K7DeviceArtwork(size: 132),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        '模拟设备流程',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.forestDeep),
      ),
      const SizedBox(height: AppSpacing.xs),
      const Text(
        '仅用于 B7 simulated preflight，不代表真实 K7 验收。',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.mutedInk),
      ),
      const SizedBox(height: AppSpacing.lg),
      _progressIndicator(),
      const SizedBox(height: AppSpacing.lg),
      switch (_step) {
        _DemoStep.discovery => _discovery(),
        _DemoStep.pairing => _pairing(),
        _DemoStep.methods => _methods(),
        _DemoStep.directAp => _directAp(),
        _DemoStep.complete => _complete(),
      },
    ],
  );

  Widget _progressIndicator() => Row(
    children: [
      for (final step in _DemoStep.values) ...[
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: step.index <= _step.index ? AppColors.forestPrimary : AppColors.outline,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        if (step != _DemoStep.values.last) const SizedBox(width: 4),
      ],
    ],
  );

  Widget _discovery() => _panel(
    icon: Icons.bluetooth_searching_rounded,
    title: '发现附近盒子',
    message: '模拟 BLE 广播已发现一个可配对设备。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.memory_rounded, color: AppColors.forestPrimary),
          title: Text('BirdBox-7B7B7B7B'),
          subtitle: Text('BLE 信号 · -44 dBm · RC4'),
        ),
        const SizedBox(height: AppSpacing.sm),
        BirdButton(
          label: '读取设备信息',
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: () => setState(() => _step = _DemoStep.pairing),
        ),
      ],
    ),
  );

  Widget _pairing() => _panel(
    icon: Icons.phonelink_lock_rounded,
    title: '设备配对',
    message: '模拟设备信息已确认。输入任意 6 位演示配对码继续。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(
          key: ValueKey('b7-demo-pairing-code'),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: '演示配对码', hintText: '123456'),
        ),
        const SizedBox(height: AppSpacing.sm),
        BirdButton(
          label: '安全配对并连接',
          icon: const Icon(Icons.lock_open_rounded),
          onPressed: () => setState(() => _step = _DemoStep.methods),
        ),
      ],
    ),
  );

  Widget _methods() => _panel(
    icon: Icons.router_outlined,
    title: '选择连接方式',
    message: '蓝牙负责控制，网络连接承载后续数据。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BirdButton(
          label: '直连盒子',
          icon: const Icon(Icons.wifi_tethering_rounded),
          onPressed: () => setState(() => _step = _DemoStep.directAp),
        ),
        const SizedBox(height: AppSpacing.sm),
        BirdButton(
          label: _wifiExpanded ? '收起 Wi-Fi 模拟入口' : '展开 Wi-Fi 模拟入口',
          icon: const Icon(Icons.wifi_rounded),
          variant: BirdButtonVariant.outlined,
          onPressed: () => setState(() => _wifiExpanded = !_wifiExpanded),
        ),
        if (_wifiExpanded) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('搜索 Wi-Fi · 手动输入 · DPP 安全配网', textAlign: TextAlign.center),
        ],
      ],
    ),
  );

  Widget _directAp() => _panel(
    icon: Icons.wifi_tethering_rounded,
    title: '正在启动盒子直连',
    message: '模拟 AP 已创建，正在等待网络状态确认。',
    child: BirdButton(
      label: '确认直连已就绪',
      icon: const Icon(Icons.check_rounded),
      onPressed: () => setState(() => _step = _DemoStep.complete),
    ),
  );

  Widget _complete() => _panel(
    icon: Icons.check_circle_rounded,
    title: '盒子直连已就绪',
    message: '网络状态已通过模拟盒子再次确认。真实 K7 仍为 pending。',
    child: BirdButton(
      label: '重新演示',
      icon: const Icon(Icons.replay_rounded),
      variant: BirdButtonVariant.outlined,
      onPressed: () => setState(() {
        _step = _DemoStep.discovery;
        _wifiExpanded = false;
      }),
    ),
  );

  Widget _panel({required IconData icon, required String title, required String message, required Widget child}) => BirdCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(icon, size: 54, color: AppColors.forestPrimary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}
