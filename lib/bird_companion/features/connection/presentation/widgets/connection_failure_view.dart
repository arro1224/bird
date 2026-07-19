import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:flutter/material.dart';

class ConnectionFailureView extends StatelessWidget {
  const ConnectionFailureView({
    super.key,
    required this.deviceName,
    required this.message,
    required this.onRetry,
    required this.onScan,
    required this.onChangeMethod,
  });

  final String deviceName;
  final UserMessage message;
  final VoidCallback onRetry;
  final VoidCallback onScan;
  final VoidCallback onChangeMethod;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.pageHorizontal,
      AppSpacing.md,
      AppSpacing.pageHorizontal,
      AppSpacing.xl,
    ),
    children: [
      const SizedBox(height: AppSpacing.sm),
      const Center(
        child: CircleAvatar(
          radius: 44,
          backgroundColor: AppColors.danger,
          foregroundColor: AppColors.cream,
          child: Icon(Icons.close_rounded, size: 54),
        ),
      ),
      const SizedBox(height: AppSpacing.ml),
      Text(
        '未能连接$deviceName',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        message.title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('请按以下步骤检查后重试', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (index, advice) in _advice.indexed) ...[
              if (index > 0) const Divider(height: AppSpacing.lg),
              _FailureGuide(
                number: index + 1,
                icon: advice.icon,
                title: advice.title,
                subtitle: advice.subtitle,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(label: message.actionLabel ?? '重新连接', onPressed: onRetry),
      const SizedBox(height: AppSpacing.sm),
      BirdButton(
        label: '重新扫码',
        onPressed: onScan,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        variant: BirdButtonVariant.outlined,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton.icon(
        onPressed: onChangeMethod,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: const Text('切换连接方式'),
      ),
      const SizedBox(height: AppSpacing.sm),
      BirdCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          title: const Text('详细信息'),
          subtitle: const Text('查看经过处理的错误说明'),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(message.message)),
          ],
        ),
      ),
    ],
  );

  List<_FailureAdvice> get _advice {
    if (message.title.contains('证书') || message.title.contains('身份')) {
      return const [
        _FailureAdvice(
          icon: Icons.verified_user_outlined,
          title: '确认正在连接可信设备',
          subtitle: '只连接您本人持有的拍鸟伴侣盒子',
        ),
        _FailureAdvice(
          icon: Icons.schedule_rounded,
          title: '检查手机与盒子的时间',
          subtitle: '时间差异可能导致证书验证失败',
        ),
        _FailureAdvice(
          icon: Icons.qr_code_scanner_rounded,
          title: '重新扫描设备二维码',
          subtitle: '使用盒子当前显示或机身上的二维码',
        ),
      ];
    }
    if (message.title.contains('拒绝') || message.title.contains('授权')) {
      return const [
        _FailureAdvice(
          icon: Icons.admin_panel_settings_outlined,
          title: '确认盒子允许新设备连接',
          subtitle: '在盒子端确认授权状态后重试',
        ),
        _FailureAdvice(
          icon: Icons.qr_code_scanner_rounded,
          title: '重新读取连接二维码',
          subtitle: '旧二维码可能已经失效',
        ),
        _FailureAdvice(
          icon: Icons.security_rounded,
          title: '检查本地网络权限',
          subtitle: '确保 App 可以访问盒子地址',
        ),
      ];
    }
    return const [
      _FailureAdvice(
        icon: Icons.router_outlined,
        title: '确认盒子已开机并连接网络',
        subtitle: '盒子状态灯应正常亮起',
      ),
      _FailureAdvice(
        icon: Icons.near_me_outlined,
        title: '让手机与盒子保持网络可达',
        subtitle: '建议连接同一 Wi-Fi 后重试',
      ),
      _FailureAdvice(
        icon: Icons.security_rounded,
        title: '检查本地网络权限',
        subtitle: '确保 App 可以访问盒子地址',
      ),
    ];
  }
}

class _FailureAdvice {
  const _FailureAdvice({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FailureGuide extends StatelessWidget {
  const _FailureGuide({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final int number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.brandLight,
        foregroundColor: AppColors.brand,
        child: Text('$number'),
      ),
      const SizedBox(width: AppSpacing.sm),
      Icon(icon, color: AppColors.brand, size: 30),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
