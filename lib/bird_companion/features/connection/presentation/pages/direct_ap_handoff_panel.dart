import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
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
    final failed = state.phase == DirectApHandoffPhase.failure || state.phase == DirectApHandoffPhase.directApJoinTimeout;
    final title = switch (state.phase) {
      DirectApHandoffPhase.joiningPhoneAp => '正在请求连接盒子热点',
      DirectApHandoffPhase.verifyingDirectApHttp => '正在验证盒子',
      DirectApHandoffPhase.directApJoinTimeout => '等待连接超时',
      DirectApHandoffPhase.failure => '盒子验证未完成',
      DirectApHandoffPhase.directApConnected => '盒子已连接',
      _ => pending.isSta ? '等待 Wi-Fi 连接验证' : '等待手机连接盒子热点',
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
          Text(
            pending.isSta
                ? '请让手机与盒子连接同一 Wi-Fi。App 会验证设备身份、授权和实时连接后自动进入首页。'
                : cubit.manualRescue
                ? '正在验证手工连接的盒子，身份与授权确认后即可继续使用。'
                : 'App 正在自动连接 ${pending.ssid ?? '盒子热点'}。如系统弹窗，请确认加入。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            pending.isSta
                ? '无需再次配对或重复提交密码。返回前台后会继续检查连接。'
                : cubit.manualRescue
                ? '请保持当前 Wi-Fi 连接，App 会继续检查盒子的业务访问。'
                : '无需查找热点或输入盒子密码。系统入网完成后还会验证设备身份、授权和实时连接。',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('剩余等待时间：${state.remainingSeconds} 秒 · 已验证 ${state.attempt} 次', textAlign: TextAlign.center),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(state.message!),
            ),
          if (!pending.isSta && failed) const Text('如果本手机正在开热点且无法加入盒子热点，请按系统提示关闭手机热点后重试。'),
          if (state.phase == DirectApHandoffPhase.verifyingDirectApHttp || state.phase == DirectApHandoffPhase.joiningPhoneAp) const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          if (pending.isSta || failed)
            BirdButton(
              label: pending.isSta ? '打开 WLAN 设置' : '故障备用：打开 WLAN 设置',
              onPressed: () async {
                try {
                  await _wifi.invokeMethod<void>('openWifiSettings');
                } catch (_) {
                  /* System settings unavailable. */
                }
              },
            ),
          const SizedBox(height: AppSpacing.sm),
          if (failed && state.lastError == 'ProvisioningCredentialSaveException') BirdButton(label: '重试保存并继续验证', onPressed: () => unawaited(cubit.continueVerification())),
          if (failed && cubit.canUseManualRescue) BirdButton(label: '我已手动连接，验证备用连接', onPressed: () => unawaited(cubit.continueAfterManualJoin())),
          if (failed)
            BirdButton(label: '返回连接方式后重试', onPressed: onBack)
          else if (pending.isSta || state.lastError == 'ProvisioningCredentialSaveException')
            BirdButton(label: '继续验证', onPressed: !state.canContinue ? null : () => unawaited(cubit.continueVerification())),
          TextButton(onPressed: onBack, child: const Text('返回连接方式')),
          if (dependencies != null)
            TextButton(
              onPressed: () async {
                final export = await dependencies.bleDiagnosticSnapshotService.capture(pending.attemptId ?? pending.operationId, includeRetainedHistory: true);
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => BleDiagnosticExportDialog(export: export, title: '回传连接诊断', files: dependencies.bleDiagnosticFilePlatform),
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
