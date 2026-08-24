import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/provisioning_method_card.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/material.dart';

enum ConnectionMethod { directAp, existingWifi }

/// B1 only selects a method. B3/B4 own the commands that change box network
/// state, so tapping a choice here never starts AP or STA provisioning.
class ConnectionMethodPage extends StatelessWidget {
  const ConnectionMethodPage({
    super.key,
    required this.deviceName,
    required this.onSelected,
    this.capabilities,
  });

  final String deviceName;
  final ValueChanged<ConnectionMethod> onSelected;
  final DeviceCapabilities? capabilities;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.xl,
      AppSpacing.pageHorizontal,
      AppSpacing.xxl,
    ),
    children: [
      const Icon(Icons.route_rounded, size: 56, color: AppColors.brand),
      const SizedBox(height: AppSpacing.md),
      Text(
        '选择连接方式',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '已完成 $deviceName 的安全验证',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      ProvisioningMethodCard(
        icon: Icons.wifi_tethering_rounded,
        title: '直连盒子',
        description: '让手机加入盒子创建的本地网络，适合户外无路由器场景。',
        onTap: capabilities?.directAp == false ? null : () => onSelected(ConnectionMethod.directAp),
        disabledReason: capabilities?.directAp == false ? '此盒子不支持直连模式' : null,
      ),
      const SizedBox(height: AppSpacing.md),
      ProvisioningMethodCard(
        icon: Icons.router_outlined,
        title: '加入现有 Wi-Fi',
        description: '让盒子连接到已知 Wi-Fi，方便同一网络下持续使用。',
        onTap: capabilities?.infrastructureSta == false ? null : () => onSelected(ConnectionMethod.existingWifi),
        disabledReason: capabilities?.infrastructureSta == false ? '此盒子不支持加入现有 Wi-Fi' : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        '选择后将继续下一步设置，当前不会修改盒子网络。',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
      ),
    ],
  );
}
