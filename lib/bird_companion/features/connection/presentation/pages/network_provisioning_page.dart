import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/provisioning_method_card.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/sta_network_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class NetworkProvisioningPage extends StatefulWidget {
  const NetworkProvisioningPage({
    super.key,
    required this.onBack,
    this.onCompleted,
  });

  final VoidCallback onBack;
  final ValueChanged<Uri>? onCompleted;

  @override
  State<NetworkProvisioningPage> createState() => _NetworkProvisioningPageState();
}

class _NetworkProvisioningPageState extends State<NetworkProvisioningPage> {
  WifiScanNetwork? _selectedNetwork;

  @override
  Widget build(BuildContext context) => BlocBuilder<NetworkProvisioningCubit, NetworkProvisioningState>(
    builder: (context, state) {
      final cubit = context.read<NetworkProvisioningCubit>();
      if (_selectedNetwork != null && state.phase == NetworkProvisioningPhase.choosingWifiNetwork) {
        return StaNetworkForm(
          selectedNetwork: _selectedNetwork,
          onSubmit: (configuration) {
            _selectedNetwork = null;
            unawaited(cubit.submitStaConfiguration(configuration));
          },
        );
      }
      return switch (state.phase) {
        NetworkProvisioningPhase.choosingWifiMethod => _WifiMethodView(state: state),
        NetworkProvisioningPhase.scanningWifi => const _ProgressView(
          icon: Icons.wifi_find_rounded,
          title: '正在搜索 Wi-Fi',
          message: '盒子正在扫描附近网络，请稍候。',
        ),
        NetworkProvisioningPhase.choosingWifiNetwork => _WifiScanView(
          networks: state.wifiNetworks,
          onSelected: (network) => setState(() => _selectedNetwork = network),
          onRescan: () => unawaited(cubit.scanWifi()),
        ),
        NetworkProvisioningPhase.enteringWifiManually => StaNetworkForm(
          onSubmit: (configuration) => unawaited(cubit.submitStaConfiguration(configuration)),
        ),
        NetworkProvisioningPhase.success => _SuccessView(
          mode: state.confirmedMode,
          baseUri: state.baseUri,
          onCompleted: widget.onCompleted,
          onStopDirectAp: state.confirmedMode == ProvisioningNetworkMode.directAp ? () => unawaited(cubit.stopDirectAp()) : null,
        ),
        NetworkProvisioningPhase.recovered => _RecoveredView(
          mode: state.recoveredMode,
          onBack: widget.onBack,
        ),
        NetworkProvisioningPhase.stopped => _StoppedView(
          onBack: widget.onBack,
        ),
        NetworkProvisioningPhase.failure => _FailureView(
          error: state.error,
          onBack: widget.onBack,
          onRetry: _canRetryDpp(state) ? () => unawaited(cubit.startDppProvisioning()) : null,
        ),
        NetworkProvisioningPhase.dppUnavailable => _MessageView(
          icon: Icons.phonelink_erase_rounded,
          title: '手机暂不支持 DPP 配网',
          message: '请选择搜索 Wi-Fi 或手动输入继续连接。',
          actionLabel: '选择其他方式',
          onAction: cubit.returnToWifiMethodSelection,
        ),
        NetworkProvisioningPhase.methodUnavailable => _UnavailableView(
          onBack: widget.onBack,
        ),
        NetworkProvisioningPhase.cancelled => _CancelledView(
          onBack: widget.onBack,
        ),
        _ => _ProgressView(
          icon: _phaseIcon(state.phase),
          title: _phaseTitle(state.phase),
          message: _operationMessage(state.operationState),
          onCancel: state.canCancel ? () => unawaited(cubit.cancelActiveOperation()) : null,
        ),
      };
    },
  );
}

class _WifiMethodView extends StatelessWidget {
  const _WifiMethodView({required this.state});

  final NetworkProvisioningState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NetworkProvisioningCubit>();
    final capabilities = state.capabilities!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
      children: [
        Text('选择 Wi-Fi 配网方式', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        ProvisioningMethodCard(
          icon: Icons.wifi_find_rounded,
          title: '搜索附近 Wi-Fi',
          description: '让盒子扫描网络，然后从列表中选择。',
          onTap: capabilities.wifiScan ? () => unawaited(cubit.scanWifi()) : null,
          disabledReason: capabilities.wifiScan ? null : '此盒子不支持 Wi-Fi 扫描',
        ),
        const SizedBox(height: AppSpacing.sm),
        ProvisioningMethodCard(
          icon: Icons.edit_rounded,
          title: '手动输入 Wi-Fi',
          description: '输入网络名称、安全类型和密码。',
          onTap: capabilities.wifiManual ? cubit.showManualWifi : null,
          disabledReason: capabilities.wifiManual ? null : '此盒子不支持手动配网',
        ),
        const SizedBox(height: AppSpacing.sm),
        ProvisioningMethodCard(
          icon: Icons.qr_code_2_rounded,
          title: '使用 DPP 安全配网',
          description: '通过 Android 系统界面安全传递网络配置。',
          onTap: capabilities.dppUsableByBox ? () => unawaited(cubit.startDppProvisioning()) : null,
          disabledReason: capabilities.dppUsableByBox ? null : '盒子暂不支持 DPP',
        ),
      ],
    );
  }
}

class _WifiScanView extends StatelessWidget {
  const _WifiScanView({
    required this.networks,
    required this.onSelected,
    required this.onRescan,
  });

  final List<WifiScanNetwork> networks;
  final ValueChanged<WifiScanNetwork> onSelected;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      Text('选择 Wi-Fi', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.md),
      for (final network in networks) ...[
        BirdCard(
          onTap: network.unsupported ? null : () => onSelected(network),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              network.unsupported ? Icons.block_rounded : Icons.wifi_rounded,
              color: network.unsupported ? AppColors.inkMuted : AppColors.brand,
            ),
            title: Text(network.ssid),
            subtitle: Text(
              network.unsupported ? '当前不支持此网络的安全类型' : _securityLabel(network.security),
            ),
            trailing: Text('${network.rssiDbm} dBm'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      BirdButton(
        label: '重新搜索',
        onPressed: onRescan,
        variant: BirdButtonVariant.outlined,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
  );
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({
    required this.icon,
    required this.title,
    required this.message,
    this.onCancel,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      Icon(icon, size: 64, color: AppColors.brand),
      const SizedBox(height: AppSpacing.md),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: AppSpacing.lg),
      const Center(child: CircularProgressIndicator()),
      if (onCancel != null) ...[
        const SizedBox(height: AppSpacing.xl),
        BirdButton(
          label: '取消当前操作',
          onPressed: onCancel,
          variant: BirdButtonVariant.outlined,
        ),
      ],
    ],
  );
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.mode,
    required this.baseUri,
    required this.onCompleted,
    required this.onStopDirectAp,
  });

  final ProvisioningNetworkMode? mode;
  final Uri? baseUri;
  final ValueChanged<Uri>? onCompleted;
  final VoidCallback? onStopDirectAp;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      const Icon(Icons.check_circle_rounded, size: 72, color: AppColors.success),
      const SizedBox(height: AppSpacing.md),
      Text(
        mode == ProvisioningNetworkMode.directAp ? '盒子直连已就绪' : '盒子已加入 Wi-Fi',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text('网络状态已通过盒子再次确认。', textAlign: TextAlign.center),
      const SizedBox(height: AppSpacing.xl),
      BirdButton(
        label: '完成',
        onPressed: baseUri == null || onCompleted == null ? null : () => onCompleted!(baseUri!),
      ),
      if (onStopDirectAp != null) ...[
        const SizedBox(height: AppSpacing.sm),
        BirdButton(
          label: '停止盒子直连',
          onPressed: onStopDirectAp,
          variant: BirdButtonVariant.outlined,
        ),
      ],
    ],
  );
}

class _RecoveredView extends StatelessWidget {
  const _RecoveredView({required this.mode, required this.onBack});
  final ProvisioningNetworkMode? mode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _MessageView(
    icon: Icons.settings_backup_restore_rounded,
    title: '已恢复可用网络',
    message: mode == ProvisioningNetworkMode.directAp ? '盒子已恢复到直连网络，本次目标网络没有连接成功。' : '盒子已恢复到之前可用的网络，本次目标网络没有连接成功。',
    actionLabel: '返回连接方式',
    onAction: onBack,
  );
}

class _StoppedView extends StatelessWidget {
  const _StoppedView({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _MessageView(
    icon: Icons.wifi_tethering_off_rounded,
    title: '盒子直连已停止',
    message: '盒子已退出直连网络，可以重新选择连接方式。',
    actionLabel: '返回连接方式',
    onAction: onBack,
  );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.error, required this.onBack, this.onRetry});
  final Object? error;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = UserMessageMapper.fromError(error ?? const NetworkStatusConfirmationException());
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
      children: [
        ErrorNotice(title: message.title, message: message.message),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          BirdButton(label: '重新尝试 DPP', onPressed: onRetry),
        ],
        const SizedBox(height: AppSpacing.md),
        BirdButton(
          label: '返回连接方式',
          onPressed: onBack,
          variant: BirdButtonVariant.outlined,
        ),
      ],
    );
  }
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => _MessageView(
    icon: Icons.info_outline_rounded,
    title: '盒子不支持此方式',
    message: '请返回后选择盒子当前支持的连接方式。',
    actionLabel: '返回连接方式',
    onAction: onBack,
  );
}

class _CancelledView extends StatelessWidget {
  const _CancelledView({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => _MessageView(
    icon: Icons.cancel_outlined,
    title: '配网已取消',
    message: '当前网络操作已经取消，可以重新选择连接方式。',
    actionLabel: '返回连接方式',
    onAction: onBack,
  );
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      Icon(icon, size: 64, color: AppColors.brand),
      const SizedBox(height: AppSpacing.md),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: AppSpacing.xl),
      BirdButton(label: actionLabel, onPressed: onAction),
    ],
  );
}

IconData _phaseIcon(NetworkProvisioningPhase phase) => switch (phase) {
  NetworkProvisioningPhase.startingDirectAp || NetworkProvisioningPhase.stoppingDirectAp => Icons.wifi_tethering_rounded,
  NetworkProvisioningPhase.preparingDpp => Icons.qr_code_2_rounded,
  _ => Icons.router_outlined,
};

String _phaseTitle(NetworkProvisioningPhase phase) => switch (phase) {
  NetworkProvisioningPhase.startingDirectAp => '正在启动盒子直连',
  NetworkProvisioningPhase.stoppingDirectAp => '正在停止盒子直连',
  NetworkProvisioningPhase.configuringSta => '正在连接 Wi-Fi',
  NetworkProvisioningPhase.preparingDpp => '正在进行 DPP 配网',
  NetworkProvisioningPhase.confirmingNetwork => '正在确认网络状态',
  _ => '正在准备网络',
};

String _operationMessage(NetworkOperationState? state) => switch (state) {
  NetworkOperationState.connectingSta => '盒子正在连接目标网络。',
  NetworkOperationState.obtainingIp => '盒子正在获取网络地址。',
  NetworkOperationState.waitingDppConfigurator => '请在 Android 系统界面中继续。',
  NetworkOperationState.dppAuthenticating => '正在安全验证 DPP 配置。',
  NetworkOperationState.recovering => '连接未完成，盒子正在恢复可用网络。',
  _ => '请保持手机靠近盒子，当前操作完成前不要关闭蓝牙。',
};

String _securityLabel(WifiSecurity security) => switch (security) {
  WifiSecurity.open => '开放网络',
  WifiSecurity.wpa2Personal => 'WPA2',
  WifiSecurity.wpa3Personal => 'WPA3',
  WifiSecurity.wpa2Wpa3Transition => 'WPA2/WPA3',
};

bool _canRetryDpp(NetworkProvisioningState state) => switch (state.error) {
  ProvisioningException(
    code: ProvisioningErrorCode.systemDppFailed || ProvisioningErrorCode.dppTimeout,
  ) =>
    true,
  _ => false,
};
