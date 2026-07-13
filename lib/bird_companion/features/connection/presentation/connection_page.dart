import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/widgets/empty_state.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/qr_connection_scanner_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_method_tabs.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/manual_address_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ConnectionCubit(BirdCompanionScope.of(context).connectionRepository, BirdCompanionScope.of(context).deviceSessionCubit)..load(),
      child: const _ConnectionView(),
    );
  }
}

class _ConnectionView extends StatefulWidget {
  const _ConnectionView();

  @override
  State<_ConnectionView> createState() => _ConnectionViewState();
}

class _ConnectionViewState extends State<_ConnectionView> {
  ConnectionMethod _method = ConnectionMethod.nearby;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConnectionCubit, DeviceConnectionState>(
      listenWhen: (previous, current) => previous.phase != current.phase,
      listener: (context, state) {
        if (state.phase == ConnectionPhase.connected) {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            navigator.pushReplacementNamed(BirdRoutes.shell);
          }
        }
      },
      builder: (context, state) {
        final isConnecting = state.phase == ConnectionPhase.connecting;
        final error = state.phase == ConnectionPhase.failure && state.error != null ? UserMessageMapper.fromError(state.error!) : null;
        return Scaffold(
          appBar: AppBar(leading: const BirdPageBackButton(), title: const Text('连接拍鸟伴侣')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text('连接拍鸟伴侣', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text('发现附近的盒子，开始本地看片', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.lg),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConnectionMethodTabs(value: _method, onChanged: (value) => setState(() => _method = value)),
                ),
                const SizedBox(height: AppSpacing.md),
                if (error != null) ErrorNotice(title: error.title, message: error.message, onRetry: () => context.read<ConnectionCubit>().load()),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _method == ConnectionMethod.manual || _method == ConnectionMethod.hotspot
                      ? ManualAddressForm(
                          key: const ValueKey('manual'),
                          isSubmitting: isConnecting,
                          onConnect: (uri) => context.read<ConnectionCubit>().connect(uri, _method == ConnectionMethod.hotspot ? NetworkMode.hotspot : NetworkMode.manual),
                        )
                      : _method == ConnectionMethod.scan
                      ? _ScanConnectCard(isConnecting: isConnecting)
                      : _NearbyDeviceList(state: state, isConnecting: isConnecting),
                ),
                if (state.recentDevices.isNotEmpty && _method != ConnectionMethod.nearby) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Text('最近连接', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final device in state.recentDevices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: DiscoveredDeviceCard(device: device, onConnect: isConnecting ? () {} : () => context.read<ConnectionCubit>().connect(device.baseUri, device.networkMode)),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NearbyDeviceList extends StatelessWidget {
  const _NearbyDeviceList({required this.state, required this.isConnecting});

  final DeviceConnectionState state;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    final devices = state.discoveredDevices.isNotEmpty ? state.discoveredDevices : state.recentDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: state.phase == ConnectionPhase.loading ? null : () => context.read<ConnectionCubit>().discover(),
          icon: const Icon(Icons.radar_outlined),
          label: Text(state.phase == ConnectionPhase.loading ? '正在搜索…' : '搜索附近盒子'),
        ),
        const SizedBox(height: AppSpacing.md),
        if (devices.isEmpty)
          const EmptyState(icon: Icons.router_outlined, title: '未发现盒子', message: '请确认手机已连接盒子热点或同一局域网，也可以使用手动地址连接。')
        else
          for (final device in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: DiscoveredDeviceCard(device: device, onConnect: isConnecting ? () {} : () => context.read<ConnectionCubit>().connect(device.baseUri, device.networkMode)),
            ),
      ],
    );
  }
}

class _ScanConnectCard extends StatelessWidget {
  const _ScanConnectCard({required this.isConnecting});

  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('扫描盒子屏幕或包装上的连接二维码。二维码应包含本地服务地址，不需要互联网。', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: isConnecting
              ? null
              : () async {
                  final uri = await Navigator.of(context).push<Uri>(MaterialPageRoute(builder: (_) => const QrConnectionScannerPage()));
                  if (uri != null && context.mounted) await context.read<ConnectionCubit>().connect(uri, NetworkMode.qr);
                },
          icon: const Icon(Icons.qr_code_scanner_outlined),
          label: const Text('扫描二维码'),
        ),
      ],
    );
  }
}
