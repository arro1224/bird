import 'dart:async';

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({
    super.key,
    required this.repository,
    this.onProvisioningCompleted,
  });

  final ProvisioningRepository repository;
  final ProvisioningCompletionHandler? onProvisioningCompleted;

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  late final NetworkProvisioningCubit _cubit =
      NetworkProvisioningCubit(widget.repository);
  StreamSubscription<void>? _disconnectSubscription;
  ProvisioningDeviceInfo? _deviceInfo;
  bool _bleDisconnected = false;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    final sessionRepository = widget.repository is ProvisioningSessionRepository
        ? widget.repository as ProvisioningSessionRepository
        : null;
    _deviceInfo = sessionRepository?.connectedDeviceInfo;
    _bleDisconnected = _deviceInfo == null;
    _disconnectSubscription = sessionRepository?.disconnects.listen((_) {
      if (!mounted) return;
      setState(() => _bleDisconnected = true);
    });
    final info = _deviceInfo;
    if (info != null) {
      unawaited(_cubit.resumeAfterBleReconnect(info));
    }
  }

  @override
  void dispose() {
    unawaited(_disconnectSubscription?.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: _cubit,
    child: BirdSettingsScaffold(
      title: '网络设置',
      body: _bleDisconnected
          ? _BleReconnectNotice(onReconnect: () => openReconnectConnection(context))
          : NetworkProvisioningPage(
              onBack: _showWifiChoices,
              onChangeWifi: _showWifiChoices,
              completing: _completing,
              onCompleted: _complete,
            ),
    ),
  );

  void _showWifiChoices() {
    final info = _deviceInfo;
    if (info == null || _bleDisconnected) return;
    _cubit.openWifiProvisioning(info);
  }

  Future<void> _complete(Uri baseUri) async {
    final handler = widget.onProvisioningCompleted;
    final state = _cubit.state;
    final deviceId = state.trustedDeviceId;
    final mode = state.confirmedMode;
    if (_completing || handler == null || deviceId == null || mode == null) {
      if (mounted && handler == null) Navigator.of(context).pop();
      return;
    }
    setState(() => _completing = true);
    try {
      await handler(
        ProvisioningCompletion(
          deviceId: deviceId,
          baseUri: baseUri,
          networkMode: mode,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _completing = false);
      BirdFeedback.error(context, UserMessageMapper.fromError(error).message);
    }
  }
}

class _BleReconnectNotice extends StatelessWidget {
  const _BleReconnectNotice({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('network-settings-ble-reconnect'),
    padding: const EdgeInsets.all(AppSpacing.settingsPageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      const Icon(
        Icons.bluetooth_disabled_rounded,
        size: 68,
        color: AppColors.warning,
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        '需要重新连接蓝牙',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text(
        '盒子会继续执行已经接受的网络操作。重新连接后，App 将按 operation_id 读取真实终态，不会把蓝牙断开或热点消失当作成功。',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.xl),
      BirdButton(
        label: '重新连接并恢复状态',
        onPressed: onReconnect,
        icon: const Icon(Icons.bluetooth_searching_rounded),
      ),
    ],
  );
}
