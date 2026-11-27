import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/direct_ap_handoff_panel.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key, required this.repository, this.onProvisioningCompleted, this.phoneWifi, this.demoMode = false, this.deviceId, this.recoverBleOnOpen = false});
  final ProvisioningRepository repository;
  final ProvisioningCompletionHandler? onProvisioningCompleted;
  final PhoneWifiPlatform? phoneWifi;
  final bool demoMode;
  final String? deviceId;
  final bool recoverBleOnOpen;
  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> with WidgetsBindingObserver {
  late final NetworkProvisioningCubit _cubit;
  BirdCompanionDependencies? _dependencies;
  DirectApHandoffCubit? _handoff;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  ProvisioningDeviceInfo? _deviceInfo;
  String? _deviceId, _controlError;
  CancelToken? _controlToken;
  int _controlGeneration = 0;
  bool _initialized = false, _bleDisconnected = true, _recovering = false, _confirmingStop = false;
  bool _wasDirect = false, _stopRequested = false, _phoneRecovered = false, _deviceChanged = false, _openingWifiProvisioning = false;

  bool get _demoMode => widget.demoMode || _dependencies?.isEmbeddedDemo == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final dependencies = _dependencies = BirdCompanionScope.maybeOf(context);
    _handoff = _demoMode ? null : dependencies?.createDirectApHandoff();
    _cubit = NetworkProvisioningCubit(
      widget.repository,
      directApHandoff: _handoff,
      reconcileStop: true,
      resolveStaEndpoint: dependencies?.resolveStaEndpoint,
      diagnostic: dependencies?.connectionAttempts.record,
      onIntentStarted: dependencies == null
          ? null
          : (id) {
              final session = dependencies.deviceSessionCubit;
              session.beginNetworkIntent(id);
              if ((_stopRequested || _cubit.state.phase == NetworkProvisioningPhase.stoppingDirectAp) && session.state.device?.id == _deviceId && session.state.isConnected && session.state.device?.networkMode == NetworkMode.directAp) {
                session.disconnected('正在退出盒子直连，旧网络业务连接尚未验证。');
              }
            },
      onIntentEnded: dependencies?.deviceSessionCubit.endNetworkIntent,
    );
    final repository = widget.repository;
    final sessionRepository = repository is ProvisioningSessionRepository ? repository as ProvisioningSessionRepository : null;
    _deviceInfo = sessionRepository?.connectedDeviceInfo;
    _deviceId = widget.deviceId ?? dependencies?.deviceSessionCubit.state.device?.id ?? _deviceInfo?.deviceId;
    _deviceChanged = widget.deviceId != null && dependencies != null && dependencies.deviceSessionCubit.state.device?.id != widget.deviceId;
    if (_deviceInfo?.deviceId != _deviceId) _deviceInfo = null;
    _bleDisconnected = _deviceInfo == null;
    _wasDirect = dependencies?.deviceSessionCubit.state.device?.networkMode == NetworkMode.directAp;
    _subscriptions.add(
      _cubit.stream.listen((state) {
        if (!mounted) return;
        if (state.confirmedMode == ProvisioningNetworkMode.directAp || state.recoveredMode == ProvisioningNetworkMode.directAp) {
          _wasDirect = true;
        }
        setState(() {});
      }),
    );
    final handoff = _handoff;
    if (handoff != null) {
      _subscriptions.add(
        handoff.stream.listen((state) {
          if (!mounted || _deviceChanged) return;
          if (state.phase == DirectApHandoffPhase.directApConnected &&
              state.pending?.deviceId == _deviceId &&
              dependencies?.deviceSessionCubit.state.isConnected == true &&
              dependencies?.deviceSessionCubit.activeAttemptId == state.pending?.attemptId) {
            _phoneRecovered = state.pending!.isSta;
            _cubit.acceptVerifiedHandoff(state.pending!.completion, state.pending!.operationId);
          }
          setState(() {}); // Keep the original settings route after recovery.
        }),
      );
    }
    if (sessionRepository != null) {
      _subscriptions.add(
        sessionRepository.disconnects.listen((_) {
          if (mounted) setState(() => _bleDisconnected = true);
        }),
      );
    }
    if (dependencies != null) {
      _subscriptions.add(dependencies.connectivityMonitor.onTransportChanged.listen((_) => _handoff?.networkChanged()));
      _subscriptions.add(
        dependencies.deviceSessionCubit.stream.listen((state) {
          if (!mounted) return;
          if (_deviceId != null && state.device?.id != _deviceId) {
            _deviceChanged = true;
            _cancelControl();
          }
          setState(() {});
        }),
      );
    }
    final info = _deviceInfo;
    if (info != null) {
      unawaited(_cubit.resumeAfterBleReconnect(info, handoffDirectAp: false, verifyBusiness: false));
    } else if (widget.recoverBleOnOpen && !_deviceChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverControl());
      });
    }
  }

  @override
  void dispose() {
    ++_controlGeneration;
    _controlToken?.cancel('Settings page disposed');
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_handoff?.close());
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _handoff?.lifecycleChanged(resumed: state == AppLifecycleState.resumed);

  Future<void> _recoverControl() async {
    if (_recovering || _deviceChanged || _deviceId == null) return;
    final repository = widget.repository;
    final id = _deviceId!;
    final generation = ++_controlGeneration;
    final token = _controlToken = CancelToken();
    final deadline = Timer(const Duration(seconds: 30), () {
      if (mounted && generation == _controlGeneration) {
        _cancelControl(timedOut: true);
      }
    });
    setState(() {
      _recovering = true;
      _controlError = null;
    });
    try {
      if (repository is! BleControlRecovery) throw const DirectApConfigurationUnavailable();
      final info = await (repository as BleControlRecovery).recoverBleControl(id, token);
      token.throwIfCancellationRequested();
      if (!mounted || generation != _controlGeneration || _deviceChanged || info.deviceId != id) return;
      _deviceInfo = info;
      _bleDisconnected = false;
      await _cubit.resumeAfterBleReconnect(info, handoffDirectAp: false, verifyBusiness: false, cancelToken: token);
      if (!mounted || generation != _controlGeneration || _deviceChanged) return;
      if (_cubit.state.error != null) _controlError = '蓝牙已连接，网络状态读取未完成，请重试刷新。';
    } catch (error) {
      if (mounted && generation == _controlGeneration && !token.isCancelled) {
        final message = UserMessageMapper.fromError(error);
        _controlError = '蓝牙控制恢复未完成：${message.title}。${message.message}';
      }
    } finally {
      deadline.cancel();
      if (mounted && generation == _controlGeneration) {
        setState(() {
          _recovering = false;
          _controlToken = null;
        });
      }
    }
  }

  void _cancelControl({bool timedOut = false}) {
    ++_controlGeneration;
    _controlToken?.cancel(timedOut ? const BleControlRecoveryException(BleControlRecoveryFailure.timeout) : 'User cancelled control recovery');
    _controlToken = null;
    if (mounted) {
      setState(() {
        _recovering = false;
        _controlError = timedOut ? '蓝牙恢复超时，当前网络连接保持原状，请重试。' : '已取消蓝牙恢复，当前网络连接保持原状。';
      });
    }
  }

  Future<void> _stopDirectAp() async {
    if (_confirmingStop || _bleDisconnected || _recovering || _deviceChanged || _cubit.state.phase == NetworkProvisioningPhase.stoppingDirectAp) return;
    _confirmingStop = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('断开盒子直连？'),
          content: const Text('盒子将尝试恢复之前的 Wi-Fi，App 会重新验证业务连接。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('断开并恢复 Wi-Fi')),
          ],
        ),
      );
      if (!mounted || confirmed != true || _deviceChanged || _bleDisconnected) return;
      setState(() {
        _stopRequested = true;
        _phoneRecovered = false;
      });
      await _cubit.stopDirectAp();
    } finally {
      _confirmingStop = false;
    }
  }

  Widget _controlControls() {
    final canRefresh = !_recovering && !_deviceChanged && _deviceId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_bleDisconnected ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_connected_rounded, color: AppColors.forestPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_bleDisconnected ? '蓝牙控制已断开' : '蓝牙控制已连接', style: Theme.of(context).textTheme.bodyMedium)),
              if (!_recovering && !_bleDisconnected) IconButton(tooltip: '刷新蓝牙状态', onPressed: canRefresh ? _recoverControl : null, icon: const Icon(Icons.refresh_rounded, size: 20)),
            ],
          ),
          if (_recovering) ...[
            const Text('正在恢复蓝牙控制…'),
            TextButton(onPressed: _cancelControl, child: const Text('取消蓝牙恢复')),
          ] else if (_bleDisconnected)
            TextButton(onPressed: canRefresh ? _recoverControl : null, child: const Text('恢复当前盒子蓝牙控制')),
          if (_controlError != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_controlError!)),
        ],
      ),
    );
  }

  Widget _connectionCard({required String mode, required String connection, required bool online}) => BirdSettingsCard(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statusLine(Icons.router_outlined, '盒子网络', mode, online: mode != '未连接' && mode != '状态待确认')),
          ],
        ),
        const SizedBox(height: 4),
        _statusLine(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, 'App 业务连接', connection, online: online),
        const Divider(height: 12),
        _controlControls(),
      ],
    ),
  );

  Widget _statusLine(IconData icon, String label, String value, {required bool online}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 18, color: online ? AppColors.success : AppColors.mutedInk),
        const SizedBox(width: 9),
        SizedBox(
          width: 116,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedInk)),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _action(String label, IconData icon, VoidCallback? onTap, {bool last = false}) => BirdSettingsRow(
    title: label,
    leading: Icon(icon, size: 21, color: onTap == null ? AppColors.inkFaint : AppColors.forestPrimary),
    leadingSize: 24,
    titleFontSize: 16,
    titleFontWeight: FontWeight.w600,
    titleColor: onTap == null ? AppColors.inkFaint : AppColors.forestDeep,
    trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.inkFaint),
    minHeight: 56,
    showDivider: !last,
    onTap: onTap,
  );

  Widget _stopSummary() {
    final state = _cubit.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('盒子已停止直连'),
        Text(state.stoppedStaRestored == true ? '盒子已报告恢复旧 Wi-Fi' : '盒子未恢复原 Wi-Fi，可重试或选择其他网络。'),
        Text(_phoneRecovered ? '手机与盒子的业务连接已验证' : '手机业务连接尚未验证'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _cubit.state;
    final handoff = _handoff;
    final terminal = _stopRequested && state.stoppedStaRestored != null;
    final session = _dependencies?.deviceSessionCubit.state;
    final device = session?.device;
    final businessOnline = session?.isConnected == true;
    final currentMode =
        device?.networkMode ??
        (_cubit.state.confirmedMode == ProvisioningNetworkMode.infrastructureSta
            ? NetworkMode.infrastructureSta
            : _cubit.state.confirmedMode == ProvisioningNetworkMode.directAp || _wasDirect
            ? NetworkMode.directAp
            : NetworkMode.unknown);
    final modeLabel = switch (currentMode) {
      NetworkMode.directAp || NetworkMode.hotspot => '盒子热点',
      NetworkMode.infrastructureSta => '路由器 Wi-Fi',
      NetworkMode.lan => '局域网',
      NetworkMode.manual => '手动地址',
      NetworkMode.qr => '扫码连接',
      NetworkMode.none => '未连接',
      NetworkMode.unknown => '状态待确认',
    };
    final connectionDetail = businessOnline
        ? 'App 已连接${device?.name.isNotEmpty == true ? ' · ${device!.name}' : ''}'
        : currentMode == NetworkMode.none
        ? '盒子当前未建立网络连接'
        : currentMode == NetworkMode.unknown
        ? '暂时无法读取盒子的连接方式'
        : session?.device != null
        ? 'App 与盒子的业务连接已中断'
        : '网络方式已知，App 与盒子的业务连接尚未验证';
    Widget body;
    if (_deviceChanged) {
      body = const Center(child: Text('当前设备已切换，请返回后打开新设备的网络设置。'));
    } else if (handoff != null && handoff.state.active && handoff.state.phase != DirectApHandoffPhase.directApConnected) {
      body = Column(
        children: [
          if (terminal) Padding(padding: const EdgeInsets.all(AppSpacing.md), child: _stopSummary()),
          Expanded(
            child: DirectApHandoffPanel(
              cubit: handoff,
              onBack: () async {
                await handoff.cancel();
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      );
    } else if (_deviceInfo != null || _wasDirect || terminal || _stopRequested) {
      body = ListView(
        key: const Key('network-settings-direct-ap'),
        padding: const EdgeInsets.all(AppSpacing.settingsPageHorizontal),
        children: [
          if (terminal) ...[
            BirdSettingsCard(child: _stopSummary()),
            const SizedBox(height: 12),
            BirdSettingsCard(padding: EdgeInsets.zero, child: _controlControls()),
          ] else
            _connectionCard(mode: modeLabel, connection: connectionDetail, online: businessOnline),
          const SizedBox(height: AppSpacing.lg),
          const BirdSettingsSectionLabel('连接 Wi-Fi'),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (!_bleDisconnected && !_recovering && state.phase != NetworkProvisioningPhase.stoppingDirectAp) ...[
                  if (_deviceInfo?.capabilities.wifiManual == true)
                    _action('连接手机当前 Wi-Fi', Icons.wifi_rounded, () => _openWifiProvisioning(WifiSettingsAction.currentPhone)),
                  if (_deviceInfo?.capabilities.wifiManual == true)
                    _action('扫描 Wi-Fi 二维码', Icons.qr_code_scanner_rounded, () => _openWifiProvisioning(WifiSettingsAction.qr)),
                  if (_deviceInfo?.capabilities.wifiScan == true)
                    _action('搜索附近 Wi-Fi', Icons.wifi_find_rounded, () => _openWifiProvisioning(WifiSettingsAction.scan)),
                  if (_deviceInfo?.capabilities.wifiManual == true)
                    _action('手动输入 Wi-Fi', Icons.edit_outlined, () => _openWifiProvisioning(WifiSettingsAction.manual), last: !terminal || _phoneRecovered),
                ],
                if (terminal && !_phoneRecovered)
                  _action('重试验证旧网络', Icons.sync_rounded, _cubit.retryStoppedNetwork, last: true),
              ],
            ),
          ),
          if (!terminal && (currentMode == NetworkMode.directAp || currentMode == NetworkMode.hotspot))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: _bleDisconnected || _recovering || state.phase != NetworkProvisioningPhase.success ? null : _stopDirectAp,
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('停止盒子直连'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.mutedInk, minimumSize: const Size(48, 48)),
                ),
              ),
            ),
          if (state.phase == NetworkProvisioningPhase.stoppingDirectAp) const Text('正在停止盒子直连'),
          if (_stopRequested && state.recoveredMode == ProvisioningNetworkMode.directAp) const Text('停止直连未完成，盒子已恢复直连模式。可刷新蓝牙状态后重试，或选择其他 Wi-Fi。'),
          if (_stopRequested && state.confirmedMode == ProvisioningNetworkMode.directAp) const Text('盒子仍处于直连模式，可重新确认后停止。'),
          if (!terminal && _bleDisconnected) const Text('停止直连需要蓝牙控制，请先恢复当前盒子的蓝牙。'),
          if (state.error != null) const Text('网络操作尚未验证完成，请重试或检查原 Wi-Fi 是否可用。'),
        ],
      );
    } else {
      body = ListView(
        key: const Key('network-settings-ble-reconnect'),
        padding: const EdgeInsets.all(AppSpacing.settingsPageHorizontal),
        children: [
          _connectionCard(mode: modeLabel, connection: '蓝牙控制已断开，恢复后才能读取盒子的网络状态。', online: false),
        ],
      );
    }
    return BlocProvider.value(
      value: _cubit,
      child: BirdSettingsScaffold(title: '网络设置', body: body),
    );
  }

  Future<void> _openWifiProvisioning(WifiSettingsAction action) async {
    final info = _deviceInfo;
    if (info == null || _bleDisconnected || _recovering || _deviceChanged || _openingWifiProvisioning) return;
    _openingWifiProvisioning = true;
    var completing = false;
    final handoff = _handoff;
    try {
      _cubit.openWifiProvisioning(info);
      setState(() {
        _stopRequested = false;
        _phoneRecovered = false;
      });
      final navigator = Navigator.of(context);
      final confirmedMode = await navigator.push<ProvisioningNetworkMode>(
        MaterialPageRoute<ProvisioningNetworkMode>(
          builder: (routeContext) => BlocProvider.value(
            value: _cubit,
            child: StatefulBuilder(
              builder: (routeContext, setRouteState) {
                void back() => Navigator.of(routeContext).maybePop();
                final provisioning = NetworkProvisioningPage(
                  initialAction: action,
                  onBack: back,
                  onCompleted: (baseUri) async {
                    if (completing || _deviceChanged) return;
                    final state = _cubit.state;
                    final mode = state.confirmedMode;
                    final id = state.trustedDeviceId;
                    if (mode == null || id == null) return;
                    setRouteState(() => completing = true);
                    try {
                      if (handoff == null) {
                        await widget.onProvisioningCompleted?.call(ProvisioningCompletion(deviceId: id, baseUri: baseUri, networkMode: mode));
                      }
                      if (routeContext.mounted && ModalRoute.of(routeContext)?.isCurrent == true) {
                        Navigator.of(routeContext).pop(mode);
                      }
                    } catch (error) {
                      if (mounted) _cubit.completionFailed(error);
                    } finally {
                      if (routeContext.mounted) setRouteState(() => completing = false);
                    }
                  },
                  completing: completing,
                  completionLabel: '正在应用网络…',
                  phoneWifi: widget.phoneWifi ?? _dependencies?.phoneWifi,
                  demoMode: _demoMode,
                );
                return PopScope(
                  canPop: !completing,
                  child: BirdSettingsScaffold(
                    title: switch (action) {
                      WifiSettingsAction.currentPhone => '连接手机 Wi-Fi',
                      WifiSettingsAction.qr => '扫码连接 Wi-Fi',
                      WifiSettingsAction.scan => '搜索 Wi-Fi',
                      WifiSettingsAction.manual => '手动连接 Wi-Fi',
                    },
                    onBack: back,
                    body: handoff == null ? provisioning : StreamBuilder<DirectApHandoffState>(
                      stream: handoff.stream,
                      initialData: handoff.state,
                      builder: (_, snapshot) => snapshot.data?.active == true && snapshot.data?.phase != DirectApHandoffPhase.directApConnected
                          ? DirectApHandoffPanel(cubit: handoff, onBack: back)
                          : provisioning,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (confirmedMode != null) _wasDirect = confirmedMode == ProvisioningNetworkMode.directAp;
      if (handoff?.state.active == true) await handoff!.cancel();
      if (!mounted) return;
      _cubit.backToMethodSelection();
      if (!_bleDisconnected && !_deviceChanged) {
        await _cubit.resumeAfterBleReconnect(info, handoffDirectAp: false, verifyBusiness: false);
      }
    } finally {
      if (mounted) _openingWifiProvisioning = false;
    }
  }

}
