import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_cancellation.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/direct_ap_handoff_panel.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key, required this.repository, this.onProvisioningCompleted});
  final ProvisioningRepository repository;
  final ProvisioningCompletionHandler? onProvisioningCompleted;
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
  bool _wasDirect = false, _stopRequested = false, _phoneRecovered = false, _deviceChanged = false, _completing = false;

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
    _handoff = dependencies?.createDirectApHandoff();
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
    _deviceId = _deviceInfo?.deviceId ?? dependencies?.deviceSessionCubit.state.device?.id;
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
        _cancelControl();
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
    } catch (_) {
      if (mounted && generation == _controlGeneration && !token.isCancelled) _controlError = '蓝牙控制恢复未完成，请检查盒子与蓝牙权限后重试。';
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

  void _cancelControl() {
    ++_controlGeneration;
    _controlToken?.cancel('User cancelled control recovery');
    _controlToken = null;
    if (mounted) {
      setState(() {
        _recovering = false;
        _controlError = '已取消蓝牙恢复，当前网络连接保持原状。';
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

  Widget _controlControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_bleDisconnected ? '蓝牙控制已断开' : '蓝牙控制已连接'),
      if (_controlError != null) Text(_controlError!),
      BirdButton(
        label: _recovering
            ? '正在恢复蓝牙控制…'
            : _bleDisconnected
            ? '恢复当前盒子蓝牙控制'
            : '刷新蓝牙状态',
        onPressed: _recovering || _deviceChanged || _deviceId == null ? null : () => unawaited(_recoverControl()),
      ),
      if (_recovering) TextButton(onPressed: _cancelControl, child: const Text('取消蓝牙恢复')),
    ],
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
    final businessOnline = _dependencies?.deviceSessionCubit.state.isConnected == true && _dependencies?.deviceSessionCubit.state.device?.networkMode == NetworkMode.directAp;
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
    } else if (_wasDirect || terminal || _stopRequested) {
      body = ListView(
        key: const Key('network-settings-direct-ap'),
        padding: const EdgeInsets.all(AppSpacing.settingsPageHorizontal),
        children: [
          if (terminal) _stopSummary() else Text(businessOnline ? '盒子直连中' : '盒子直连模式', style: Theme.of(context).textTheme.headlineSmall),
          if (!terminal && !businessOnline) const Text('业务连接待验证；蓝牙控制与 Wi-Fi 业务状态分别显示。'),
          const SizedBox(height: AppSpacing.md),
          _controlControls(),
          const SizedBox(height: AppSpacing.md),
          if (state.phase == NetworkProvisioningPhase.stoppingDirectAp) const Text('正在停止盒子直连'),
          if (_stopRequested && state.recoveredMode == ProvisioningNetworkMode.directAp) const Text('停止直连未完成，盒子已恢复直连模式。可刷新蓝牙状态后重试，或选择其他 Wi-Fi。'),
          if (_stopRequested && state.confirmedMode == ProvisioningNetworkMode.directAp) const Text('盒子仍处于直连模式，可重新确认后停止。'),
          if (!terminal) BirdButton(label: '停止盒子直连', onPressed: _bleDisconnected || _recovering || state.phase != NetworkProvisioningPhase.success ? null : () => unawaited(_stopDirectAp())),
          if (!terminal && _bleDisconnected) const Text('停止直连需要蓝牙控制，请先恢复当前盒子的蓝牙。'),
          if (terminal && !_phoneRecovered) BirdButton(label: '重试验证旧网络', onPressed: () => unawaited(_cubit.retryStoppedNetwork())),
          if (state.error != null) const Text('网络操作尚未验证完成，请重试或检查原 Wi-Fi 是否可用。'),
          if (!_bleDisconnected && state.phase != NetworkProvisioningPhase.stoppingDirectAp) TextButton(onPressed: _showWifiChoices, child: const Text('选择其他 Wi-Fi')),
          TextButton(onPressed: () => unawaited(dependenciesExport()), child: const Text('导出本次连接诊断')),
        ],
      );
    } else if (_bleDisconnected) {
      body = ListView(
        key: const Key('network-settings-ble-reconnect'),
        padding: const EdgeInsets.all(AppSpacing.settingsPageHorizontal),
        children: [
          const Text('需要重新连接蓝牙'),
          const Text('盒子会继续执行已接受的操作，不会把蓝牙断开或热点消失当作成功。'),
          _controlControls(),
        ],
      );
    } else {
      body = NetworkProvisioningPage(onExportDiagnostic: dependenciesExport, onBack: _showWifiChoices, onChangeWifi: _showWifiChoices, completing: _completing, onCompleted: _complete);
    }
    return BlocProvider.value(
      value: _cubit,
      child: BirdSettingsScaffold(title: '网络设置', body: body),
    );
  }

  void _showWifiChoices() {
    final info = _deviceInfo;
    if (info == null || _bleDisconnected || _deviceChanged) return;
    setState(() {
      _wasDirect = false;
      _stopRequested = false;
    });
    _cubit.openWifiProvisioning(info);
  }

  Future<void> _complete(Uri baseUri) async {
    final handler = widget.onProvisioningCompleted;
    final state = _cubit.state;
    if (_completing || handler == null || state.trustedDeviceId == null || state.confirmedMode == null) return;
    setState(() => _completing = true);
    try {
      await handler(ProvisioningCompletion(deviceId: state.trustedDeviceId!, baseUri: baseUri, networkMode: state.confirmedMode!));
      if (mounted) {
        setState(() {
          _phoneRecovered = true;
          _completing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> dependenciesExport() async {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    final export = await dependencies.bleDiagnosticSnapshotService.capture(_cubit.attemptId ?? dependencies.connectionAttempts.activeId, includeRetainedHistory: true);
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => BleDiagnosticExportDialog(export: export, title: '回传连接诊断', files: dependencies.bleDiagnosticFilePlatform),
      );
    }
  }
}
