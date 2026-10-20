import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/widgets/ble_diagnostic_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DirectApHandoffPanel extends StatelessWidget {
  const DirectApHandoffPanel({super.key, required this.cubit, required this.onBack});
  final DirectApHandoffCubit cubit;
  final VoidCallback onBack;
  static const _wifi = MethodChannel('bird_companion/birdbox_wifi/methods');

  @override
  Widget build(BuildContext context) {
    final state = cubit.state;
    final pending = state.pending!;
    final dependencies = BirdCompanionScope.maybeOf(context);
    final repository = dependencies?.provisioningRepository;
    final title = switch (state.phase) {
      DirectApHandoffPhase.verifyingDirectApHttp => '正在验证盒子',
      DirectApHandoffPhase.directApJoinTimeout => '等待连接超时',
      DirectApHandoffPhase.failure => '盒子验证未完成',
      DirectApHandoffPhase.directApConnected => '盒子已连接',
      _ => '等待手机连接盒子热点',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Icon(Icons.wifi_rounded, size: 72),
          const SizedBox(height: AppSpacing.lg),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Text('盒子热点已就绪，请在手机 WLAN 设置中连接 ${pending.ssid ?? '盒子热点'}。', textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          const Text('若手机提示“此网络无法上网”，请选择保持连接。返回 App 后会继续验证，无需重新配对或启动热点。'),
          if (repository is ProvisioningRepositoryImpl)
            FutureBuilder<String?>(
              future: repository.directApPassphrase(pending.deviceId),
              builder: (_, snapshot) => snapshot.data == null ? const SizedBox.shrink() : ExpansionTile(title: const Text('查看盒子热点密码'), children: [SelectableText(snapshot.data!)]),
            ),
          const SizedBox(height: AppSpacing.md),
          Text('剩余等待时间：${state.remainingSeconds} 秒 · 已验证 ${state.attempt} 次', textAlign: TextAlign.center),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(state.message!),
            ),
          if (state.phase == DirectApHandoffPhase.verifyingDirectApHttp) const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          BirdButton(
            label: '打开 WLAN 设置',
            onPressed: () async {
              try {
                await _wifi.invokeMethod<void>('openWifiSettings');
              } catch (_) {
                /* Manual navigation remains available. */
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          BirdButton(label: '我已连接，继续验证', onPressed: !state.canContinue ? null : () => unawaited(cubit.continueVerification())),
          TextButton(onPressed: onBack, child: const Text('返回连接方式')),
          if (dependencies != null)
            TextButton(
              onPressed: () async {
                final export = await dependencies.bleDiagnosticSnapshotService.capture(pending.operationId);
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => BleDiagnosticExportDialog(export: export, title: '回传直连诊断', files: dependencies.bleDiagnosticFilePlatform),
                  );
                }
              },
              child: const Text('导出本次连接诊断'),
            ),
        ],
      ),
    );
  }
}
