import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/device_error_detail_page.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/current_job_card.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_alert_banner.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_header.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_metrics_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DeviceStatusPage extends StatelessWidget {
  const DeviceStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          DeviceStatusCubit(BirdCompanionScope.of(context).deviceRepository, BirdCompanionScope.of(context).deviceSessionCubit, BirdCompanionScope.of(context).refreshCoordinator, BirdCompanionScope.of(context).dataChangeBus)..load(),
      child: const _DeviceStatusView(),
    );
  }
}

class _DeviceStatusView extends StatelessWidget {
  const _DeviceStatusView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceStatusCubit, DeviceStatusState>(
      builder: (context, state) {
        if (state.phase == DeviceStatusPhase.loading && state.status == null) return const Center(child: CircularProgressIndicator());
        if (state.status == null) {
          final message = state.error == null ? null : UserMessageMapper.fromError(state.error!);
          return ErrorNotice(
            title: message?.title ?? '无法读取设备状态',
            message: message?.message ?? '请检查与盒子的连接后重试。',
            onRetry: () => context.read<DeviceStatusCubit>().load(),
          );
        }
        final status = state.status!;
        return RefreshIndicator(
          onRefresh: () => context.read<DeviceStatusCubit>().load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              DeviceHeader(status: status),
              const SizedBox(height: AppSpacing.md),
              DeviceAlertBanner(
                status: status,
                onTap: status.hasError ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceErrorDetailPage(status: status))) : null,
              ),
              if (status.hasError || !status.card.inserted || (status.temperatureCelsius ?? 0) >= 70 || (status.batteryPercent ?? 100) <= 15) const SizedBox(height: AppSpacing.md),
              DeviceMetricsGrid(status: status),
              const SizedBox(height: AppSpacing.lg),
              Text('当前任务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              CurrentJobCard(
                job: status.currentJob,
                isControlling: state.isControllingJob,
                onControl: context.read<DeviceStatusCubit>().controlCurrentJob,
                onOpenTaskCenter: () => _openMainTab(context, 2, BirdRoutes.jobCenter),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('快捷入口', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(onPressed: () => _openMainTab(context, 1, BirdRoutes.batches), icon: const Icon(Icons.grid_view_rounded), label: const Text('当前批次')),
                  OutlinedButton.icon(onPressed: () => Navigator.of(context).pushNamed(BirdRoutes.diagnostics), icon: const Icon(Icons.health_and_safety_outlined), label: const Text('诊断与日志')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

void _openMainTab(BuildContext context, int index, String fallbackRoute) {
  final shell = BirdShellNavigation.maybeOf(context);
  if (shell != null) {
    shell.selectTab(index);
  } else {
    Navigator.of(context).pushNamed(fallbackRoute);
  }
}
