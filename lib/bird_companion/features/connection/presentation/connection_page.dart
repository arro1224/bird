import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/connection_method_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/qr_connection_scanner_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/qr_connection_uri.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_background.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_empty_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_failure_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_progress_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/connection_success_view.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/k7_device_artwork.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/manual_address_form.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/pairing_code_form.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ConnectionPage extends StatelessWidget {
  const ConnectionPage({
    super.key,
    this.entryMode = ConnectionEntryMode.initialSetup,
    this.provisioningRepository,
    this.onProvisioningMethodSelected,
    this.onProvisioningCompleted,
  });

  final ConnectionEntryMode entryMode;
  final ProvisioningRepository? provisioningRepository;
  final ValueChanged<ConnectionMethod>? onProvisioningMethodSelected;
  final ValueChanged<Uri>? onProvisioningCompleted;

  @override
  Widget build(BuildContext context) {
    final provisioning = provisioningRepository;
    if (provisioning != null) {
      return Theme(
        data: AppTheme.light(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => ProvisioningCubit(provisioning)..discover(),
            ),
            BlocProvider(
              create: (_) => NetworkProvisioningCubit(provisioning),
            ),
          ],
          child: _BleConnectionView(
            onMethodSelected: onProvisioningMethodSelected,
            onProvisioningCompleted: onProvisioningCompleted,
          ),
        ),
      );
    }
    return Theme(
      data: AppTheme.light(),
      child: BlocProvider(
        create: (_) => ConnectionCubit(
          BirdCompanionScope.of(context).connectionRepository,
          BirdCompanionScope.of(context).deviceSessionCubit,
          preserveExistingSession: entryMode == ConnectionEntryMode.addOrSwitch,
        )..load(),
        child: _ConnectionView(entryMode: entryMode),
      ),
    );
  }
}

class _BleConnectionView extends StatelessWidget {
  const _BleConnectionView({
    this.onMethodSelected,
    this.onProvisioningCompleted,
  });

  final ValueChanged<ConnectionMethod>? onMethodSelected;
  final ValueChanged<Uri>? onProvisioningCompleted;

  @override
  Widget build(BuildContext context) => BlocBuilder<NetworkProvisioningCubit, NetworkProvisioningState>(
    builder: (context, networkState) {
      if (networkState.phase != NetworkProvisioningPhase.idle) {
        final networkCubit = context.read<NetworkProvisioningCubit>();
        return _scaffold(
          context,
          title: _networkTitle(networkState.phase),
          onBack: networkCubit.backToMethodSelection,
          content: NetworkProvisioningPage(
            onBack: networkCubit.backToMethodSelection,
            onCompleted: onProvisioningCompleted,
          ),
        );
      }
      return BlocBuilder<ProvisioningCubit, ProvisioningState>(
        builder: (context, state) {
          final cubit = context.read<ProvisioningCubit>();
          final error = state.error == null ? null : UserMessageMapper.fromError(state.error!);
          final title = switch (state.phase) {
            ProvisioningPhase.trusted => '验证设备',
            ProvisioningPhase.pairingCode || ProvisioningPhase.authorizing => '设备配对',
            ProvisioningPhase.methodSelection => '连接方式',
            ProvisioningPhase.failure => '连接遇到问题',
            _ => '查找盒子',
          };
          final content = switch (state.phase) {
            ProvisioningPhase.trusted => _TrustedDeviceView(
              deviceName: state.deviceInfo!.deviceName,
              onStartPairing: cubit.openPairing,
            ),
            ProvisioningPhase.pairingCode => PairingCodeForm(
              deviceName: state.deviceInfo!.deviceName,
              codeMode: state.deviceInfo!.pairingCodeMode,
              codeLength: state.deviceInfo!.pairingCodeLength,
              displayAvailable: state.deviceInfo!.displayAvailable,
              onSubmit: cubit.authorizePairing,
              onCancel: cubit.reset,
            ),
            ProvisioningPhase.methodSelection => ConnectionMethodPage(
              deviceName: state.deviceInfo!.deviceName,
              capabilities: state.deviceInfo!.capabilities,
              onSelected: (method) {
                onMethodSelected?.call(method);
                final networkCubit = context.read<NetworkProvisioningCubit>();
                switch (method) {
                  case ConnectionMethod.directAp:
                    unawaited(networkCubit.startDirectAp(state.deviceInfo!));
                    break;
                  case ConnectionMethod.existingWifi:
                    networkCubit.openWifiProvisioning(state.deviceInfo!);
                    break;
                }
              },
            ),
            ProvisioningPhase.connecting || ProvisioningPhase.authorizing => const _BleLoadingView(),
            _ => _BleDiscoveryView(
              devices: state.devices,
              searching: state.phase == ProvisioningPhase.discovering,
              error: error,
              onDiscover: cubit.discover,
              onSelectDevice: cubit.selectDevice,
              onRetry: cubit.retry,
            ),
          };
          return _scaffold(context, title: title, content: content);
        },
      );
    },
  );

  Widget _scaffold(
    BuildContext context, {
    required String title,
    required Widget content,
    VoidCallback? onBack,
  }) => Scaffold(
    backgroundColor: AppColors.paper,
    body: ConnectionBackground(
      child: SafeArea(
        child: Column(
          children: [
            _ConnectionTopBar(
              title: title,
              onHelp: () => _showBleHelp(context),
              onBack: onBack,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    ),
  );

  String _networkTitle(NetworkProvisioningPhase phase) => switch (phase) {
    NetworkProvisioningPhase.choosingWifiMethod ||
    NetworkProvisioningPhase.scanningWifi ||
    NetworkProvisioningPhase.choosingWifiNetwork ||
    NetworkProvisioningPhase.enteringWifiManually ||
    NetworkProvisioningPhase.configuringSta ||
    NetworkProvisioningPhase.preparingDpp => 'Wi-Fi 配网',
    NetworkProvisioningPhase.success => '网络已连接',
    NetworkProvisioningPhase.stopped => '直连已停止',
    NetworkProvisioningPhase.failure => '配网遇到问题',
    _ => '盒子网络设置',
  };

  void _showBleHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BirdSectionTitle(text: '连接帮助'),
              BirdListItem(
                leading: Icon(Icons.bluetooth_searching_rounded),
                title: '靠近盒子',
                subtitle: '请保持手机蓝牙开启，并靠近已开机的盒子。',
              ),
              BirdListItem(
                leading: Icon(Icons.verified_user_outlined),
                title: '完成设备验证',
                subtitle: '仅完成设备信息读取后才会继续配网。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BleDiscoveryView extends StatelessWidget {
  const _BleDiscoveryView({
    required this.devices,
    required this.searching,
    required this.error,
    required this.onDiscover,
    required this.onSelectDevice,
    required this.onRetry,
  });

  final List<ProvisioningDevice> devices;
  final bool searching;
  final UserMessage? error;
  final Future<void> Function() onDiscover;
  final Future<void> Function(ProvisioningDevice) onSelectDevice;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.sm,
      AppSpacing.pageHorizontal,
      AppSpacing.xxl,
    ),
    children: [
      const SizedBox(height: AppSpacing.md),
      const Icon(
        Icons.bluetooth_searching_rounded,
        size: 64,
        color: AppColors.brand,
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        '附近的盒子',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        searching ? '正在通过蓝牙查找附近已开机的盒子…' : '请选择要验证的盒子。名称和信号仅用于帮助识别。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpacing.sm),
        ErrorNotice(
          title: error!.title,
          message: error!.message,
          actionLabel: error!.actionLabel ?? '重试',
          onRetry: onRetry,
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      if (devices.isEmpty && !searching)
        BirdCard(
          child: Column(
            children: [
              const Icon(
                Icons.bluetooth_disabled_rounded,
                size: 38,
                color: AppColors.inkMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('暂未发现盒子', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              const Text('请确认盒子已开机且手机蓝牙权限已允许。', textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              BirdButton(
                label: '重新搜索',
                onPressed: onDiscover,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      for (final device in devices) ...[
        BirdCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.memory_rounded, color: AppColors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      device.advertisement.localName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${device.advertisement.rssi} dBm',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '发现信号，连接后将验证设备信息。',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              BirdButton(
                label: '连接此盒子',
                onPressed: () => onSelectDevice(device),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (!searching && devices.isNotEmpty)
        BirdButton(
          label: '重新搜索',
          onPressed: onDiscover,
          icon: const Icon(Icons.refresh_rounded),
          variant: BirdButtonVariant.outlined,
        ),
      const SizedBox(height: AppSpacing.lg),
      const _PrivacyNote(),
    ],
  );
}

class _TrustedDeviceView extends StatelessWidget {
  const _TrustedDeviceView({
    required this.deviceName,
    required this.onStartPairing,
  });

  final String deviceName;
  final Future<void> Function() onStartPairing;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      const Icon(
        Icons.verified_user_rounded,
        size: 72,
        color: AppColors.success,
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        '设备验证完成',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '已读取 $deviceName 的设备信息。现在可以安全开始配对。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: AppSpacing.xl),
      BirdButton(
        label: '开始配对',
        onPressed: onStartPairing,
        icon: const Icon(Icons.lock_open_rounded),
      ),
    ],
  );
}

class _BleLoadingView extends StatelessWidget {
  const _BleLoadingView();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(dimension: 40, child: CircularProgressIndicator()),
  );
}

class _ConnectionView extends StatefulWidget {
  const _ConnectionView({required this.entryMode});

  final ConnectionEntryMode entryMode;

  @override
  State<_ConnectionView> createState() => _ConnectionViewState();
}

class _ConnectionViewState extends State<_ConnectionView> {
  var _showManualAddress = false;
  var _completedAutomatically = false;
  DeviceConnection? _selectedDevice;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ConnectionCubit, DeviceConnectionState>(
    builder: (context, state) {
      final session = BirdCompanionScope.of(context).deviceSessionCubit.state;
      final searching = state.phase == ConnectionPhase.loading;
      final connecting = state.phase == ConnectionPhase.connecting;
      final error = state.phase == ConnectionPhase.failure && state.error != null ? UserMessageMapper.fromError(state.error!) : null;
      final available = state.discoveredDevices;
      final recent = state.recentDevices;
      final showEmpty = !searching && available.isEmpty;
      final activeDevice = _selectedDevice ?? available.firstOrNull ?? recent.firstOrNull ?? session.device;
      final deviceName = activeDevice?.name ?? '拍鸟伴侣 K7';

      if (connecting) {
        return _stateScaffold(
          title: '正在连接$deviceName',
          showBack: false,
          child: ConnectionProgressView(
            deviceName: deviceName,
            onCancel: context.read<ConnectionCubit>().cancelConnection,
          ),
        );
      }

      if (state.phase == ConnectionPhase.pairing && state.status != null) {
        return _stateScaffold(
          title: '设备配对',
          child: PairingCodeForm(
            deviceName: state.status!.connection.name,
            onSubmit: context.read<ConnectionCubit>().pair,
            onCancel: context.read<ConnectionCubit>().resetPairing,
          ),
        );
      }

      if (state.connectionAttemptFailed && error != null) {
        return _stateScaffold(
          title: '连接失败',
          child: ConnectionFailureView(
            deviceName: deviceName,
            message: error,
            onRetry: context.read<ConnectionCubit>().retry,
            onScan: () => _scanAndConnect(context),
            onChangeMethod: () {
              context.read<ConnectionCubit>().resetAfterFailure();
              setState(() => _showManualAddress = false);
            },
          ),
        );
      }

      if (state.phase == ConnectionPhase.connected && state.status != null) {
        final destination = automaticConnectionDestination(widget.entryMode);
        if (destination != null && !_completedAutomatically) {
          _completedAutomatically = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _finishConnection(destination);
          });
        }
        return _stateScaffold(
          title: '设备已连接',
          showBack: false,
          bottomNavigationBar: BirdBottomNavigation(
            selectedIndex: 0,
            destinations: _connectionDestinations,
            onDestinationSelected: _finishConnection,
          ),
          child: ConnectionSuccessView(
            status: state.status!,
            onOpenGallery: () => _finishConnection(0),
            onOpenDevice: () => _finishConnection(
              2,
              initialRoute: BirdRoutes.settingsDeviceDetails,
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: AppColors.paper,
        body: ConnectionBackground(
          child: SafeArea(
            child: Column(
              children: [
                _ConnectionTopBar(
                  title: '查找设备',
                  onHelp: () => _showHelp(context),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageHorizontal,
                      AppSpacing.xs,
                      AppSpacing.pageHorizontal,
                      AppSpacing.xxl,
                    ),
                    children: [
                      if (session.device != null && !session.isConnected) ...[
                        _ReconnectBanner(
                          onReconnect: () => _connectDevice(context, session.device!),
                        ),
                        const SizedBox(height: AppSpacing.ml),
                      ],
                      if (searching) const _SearchingView(),
                      if (error != null) ...[
                        ErrorNotice(
                          title: error.title,
                          message: error.message,
                          onRetry: () => context.read<ConnectionCubit>().retry(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (available.isNotEmpty) ...[
                        const BirdSectionTitle(text: '可用设备'),
                        for (final device in available)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: DiscoveredDeviceCard(
                              device: device,
                              onConnect: () => _connectDevice(context, device),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      if (showEmpty)
                        ConnectionEmptyView(
                          onRetry: () => context.read<ConnectionCubit>().discover(),
                          onScan: () => _scanAndConnect(context),
                          onManual: _showManualForm,
                        ),
                      if (recent.isNotEmpty) ...[
                        SizedBox(
                          height: showEmpty ? AppSpacing.xl : AppSpacing.sm,
                        ),
                        BirdSectionTitle(
                          text: '最近连接',
                          trailing: Text(
                            '连接时将重新验证状态',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final device in recent)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: DiscoveredDeviceCard(
                              device: device,
                              isRecent: true,
                              onConnect: () => _connectDevice(context, device),
                            ),
                          ),
                      ],
                      if (!showEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        _AlternativeActions(
                          connecting: false,
                          onScan: () => _scanAndConnect(context),
                          onManual: _showManualForm,
                        ),
                      ],
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 180),
                        crossFadeState: _showManualAddress ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: BirdCard(
                            child: ManualAddressForm(
                              isSubmitting: false,
                              initialAddress: session.device?.baseUri,
                              onConnect: (uri) => _connectUri(context, uri, NetworkMode.manual),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _PrivacyNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _showManualForm() => setState(() => _showManualAddress = true);

  Widget _stateScaffold({
    required String title,
    required Widget child,
    bool showBack = true,
    Widget? bottomNavigationBar,
  }) => Scaffold(
    backgroundColor: AppColors.paper,
    bottomNavigationBar: bottomNavigationBar,
    body: ConnectionBackground(
      child: SafeArea(
        child: Column(
          children: [
            _ConnectionTopBar(
              title: title,
              onHelp: () => _showHelp(context),
              showBack: showBack,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );

  Future<void> _connectDevice(
    BuildContext context,
    DeviceConnection device,
  ) async {
    setState(() => _selectedDevice = device);
    await context.read<ConnectionCubit>().connect(
      device.baseUri,
      device.networkMode,
    );
  }

  Future<void> _connectUri(
    BuildContext context,
    Uri uri,
    NetworkMode mode,
  ) async {
    setState(
      () => _selectedDevice = DeviceConnection(
        id: uri.toString(),
        name: '拍鸟伴侣 K7',
        baseUri: uri,
        networkMode: mode,
      ),
    );
    await context.read<ConnectionCubit>().connect(uri, mode);
  }

  Future<void> _scanAndConnect(BuildContext context) async {
    final result = await Navigator.of(context).push<QrConnectionResult>(
      MaterialPageRoute<QrConnectionResult>(
        builder: (_) => const QrConnectionScannerPage(),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result.type == QrConnectionResultType.manual) {
      _showManualForm();
      return;
    }
    final uri = result.uri;
    if (uri != null) {
      await _connectUri(context, uri, NetworkMode.qr);
    }
  }

  void _finishConnection(int shellIndex, {String? initialRoute}) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      BirdRoutes.shell,
      (route) => false,
      arguments: ShellArgs(
        initialIndex: shellIndex,
        initialRoute: initialRoute,
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            AppSpacing.xs,
            AppSpacing.pageHorizontal,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BirdSectionTitle(text: '连接帮助'),
              BirdListItem(
                leading: Icon(Icons.wifi_rounded),
                title: '连接同一网络',
                subtitle: '确保手机和拍鸟伴侣连接到同一个 Wi-Fi。',
              ),
              BirdListItem(
                leading: Icon(Icons.qr_code_scanner_rounded),
                title: '扫描设备二维码',
                subtitle: '扫描盒子上的二维码即可连接。',
              ),
              BirdListItem(
                leading: Icon(Icons.edit_outlined),
                title: '手动输入地址',
                subtitle: '也可以手动输入盒子的连接地址。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reconnect and device-switch entries return to the album immediately after
/// verification. Initial setup retains the explicit success confirmation.
int? automaticConnectionDestination(ConnectionEntryMode entryMode) => entryMode == ConnectionEntryMode.addOrSwitch ? 0 : null;

class _ConnectionTopBar extends StatelessWidget {
  const _ConnectionTopBar({
    required this.title,
    required this.onHelp,
    this.showBack = true,
    this.onBack,
  });

  final String title;
  final VoidCallback onHelp;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showLeading = onBack != null || (canPop && showBack);
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: AppSpacing.minimumTouchTarget,
              child: showLeading
                  ? IconButton(
                      tooltip: '返回',
                      onPressed: onBack ?? () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: '连接帮助',
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

const _connectionDestinations = <NavigationDestination>[
  NavigationDestination(
    icon: Icon(Icons.photo_outlined),
    selectedIcon: Icon(Icons.photo),
    label: '相册',
  ),
  NavigationDestination(
    icon: Icon(Icons.task_outlined),
    selectedIcon: Icon(Icons.task),
    label: '处理进度',
  ),
  NavigationDestination(
    icon: Icon(Icons.person_outline),
    selectedIcon: Icon(Icons.person),
    label: '我的',
  ),
];

class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 210,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final size in [200.0, 154.0, 108.0])
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandSoft.withValues(alpha: .18),
                  ),
                ),
              ),
            const K7DeviceArtwork(size: 150),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '正在搜索同一网络下的设备……',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}

class _AlternativeActions extends StatelessWidget {
  const _AlternativeActions({
    required this.connecting,
    required this.onScan,
    required this.onManual,
  });

  final bool connecting;
  final VoidCallback onScan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      BirdButton(
        label: '扫码连接',
        onPressed: connecting ? null : onScan,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        variant: BirdButtonVariant.outlined,
      ),
      const SizedBox(height: AppSpacing.sm),
      BirdButton(
        label: '手动输入地址',
        onPressed: connecting ? null : onManual,
        icon: const Icon(Icons.edit_outlined),
        variant: BirdButtonVariant.outlined,
      ),
    ],
  );
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({required this.onReconnect});

  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) => BirdCard(
    backgroundColor: AppColors.amberLight,
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(
        Icons.error_outline_rounded,
        color: AppColors.pending,
      ),
      title: const Text('设备连接已中断'),
      subtitle: const Text('可以重新连接最近使用的设备'),
      trailing: TextButton(onPressed: onReconnect, child: const Text('重新连接')),
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.shield_outlined, size: 18, color: AppColors.inkMuted),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          '仅连接可信设备，连接过程不会上传照片',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
        ),
      ),
    ],
  );
}
