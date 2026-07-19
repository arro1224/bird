import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/widgets/error_notice.dart';
import 'package:aves/bird_companion/features/device/presentation/device_status_cubit.dart';
import 'package:aves/bird_companion/features/device/presentation/device_error_detail_page.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/current_job_card.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_alert_banner.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_metrics_grid.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_sheet.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
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

class _DeviceStatusView extends StatefulWidget {
  const _DeviceStatusView();

  @override
  State<_DeviceStatusView> createState() => _DeviceStatusViewState();
}

class _DeviceStatusViewState extends State<_DeviceStatusView> {
  BatchOverview _batchOverview = const BatchOverview();
  bool _overviewLoading = true;
  bool _requestedOverview = false;

  Future<void> _refresh() async {
    await Future.wait([context.read<DeviceStatusCubit>().load(), _loadBatchOverview()]);
  }

  Future<void> _loadBatchOverview() async {
    if (mounted) {
      setState(() => _overviewLoading = true);
    }
    BatchOverview overview;
    try {
      overview = await BirdCompanionScope.of(context).batchRepository.overview();
    } catch (_) {
      overview = const BatchOverview();
    }
    if (mounted) {
      setState(() {
        _batchOverview = overview;
        _overviewLoading = false;
      });
    }
  }

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
        if (!_requestedOverview) {
          _requestedOverview = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadBatchOverview();
          });
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _DeviceHeader(
                deviceName: status.connection.name,
                onSettings: () => _openMainTab(context, 2, BirdRoutes.shell),
              ),
              const SizedBox(height: 18),
              DeviceAlertBanner(
                status: status,
                onTap: status.hasError ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceErrorDetailPage(status: status))) : null,
              ),
              if (status.hasError || !status.card.inserted || (status.temperatureCelsius ?? 0) >= 70 || (status.batteryPercent ?? 100) <= 15) const SizedBox(height: AppSpacing.md),
              DeviceMetricsGrid(
                status: status,
                onTap: () => showDeviceStatusSheet(
                  context,
                  status: status,
                  session: BirdCompanionScope.of(context).deviceSessionCubit.state,
                  onReconnect: () {
                    Navigator.of(context).pop();
                    BirdCompanionScope.of(context).deviceSessionCubit.reconnect();
                  },
                  onOpenDetails: () => Navigator.of(context).pop(),
                  onOpenTask: status.currentJob == null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _openMainTab(context, 1, BirdRoutes.jobCenter);
                        },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              CurrentJobCard(
                job: status.currentJob,
                isControlling: state.isControllingJob,
                onControl: context.read<DeviceStatusCubit>().controlCurrentJob,
                onOpenTaskCenter: () => _openMainTab(context, 1, BirdRoutes.jobCenter),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_overviewLoading)
                const Center(
                  child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                )
              else if (_batchOverview.primary == null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.photo_library_outlined, color: AppColors.brand),
                    title: const Text('暂无当前或最近批次'),
                    subtitle: const Text('新批次开始后会显示在这里'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pushNamed(BirdRoutes.batches),
                  ),
                )
              else
                CurrentBatchCard(
                  batch: _batchOverview.primary!,
                  contextLabel: _batchOverview.primaryIsActive ? '当前批次' : '最近批次',
                  actionLabel: _batchOverview.primaryIsActive ? '进入当前批次' : '查看最近批次',
                  onOpen: () => Navigator.of(context).pushNamed(BirdRoutes.gallery, arguments: GalleryArgs(_batchOverview.primary!.id)),
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _Shortcut(icon: Icons.history_rounded, label: '历史批次', onTap: () => Navigator.of(context).pushNamed(BirdRoutes.batches)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Shortcut(
                      icon: Icons.auto_graph_rounded,
                      label: '智能审阅',
                      onTap: () => Navigator.of(context).pushNamed(BirdRoutes.batches, arguments: BatchOpenMode.review),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Shortcut(icon: Icons.task_alt_rounded, label: '任务中心', onTap: () => _openMainTab(context, 1, BirdRoutes.jobCenter)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Column(
                    children: [
                      _VersionRow(label: '盒子版本', value: status.softwareVersion ?? '—'),
                      const Divider(height: 16),
                      _VersionRow(label: '模型版本', value: status.modelVersion ?? '—'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: const TextStyle(color: AppColors.inkMuted)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.deviceName, required this.onSettings});

  final String deviceName;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('下午好', style: TextStyle(color: AppColors.inkMuted, fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              children: [
                Flexible(
                  child: Text(deviceName, style: Theme.of(context).textTheme.displaySmall, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.circle, color: AppColors.brand, size: 12),
                const SizedBox(width: 6),
                const Text('在线', style: TextStyle(color: AppColors.inkMuted)),
              ],
            ),
          ],
        ),
      ),
      IconButton.filledTonal(
        tooltip: '设备设置',
        onPressed: onSettings,
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        icon: const Icon(Icons.settings_outlined),
      ),
    ],
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 26),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

void _openMainTab(BuildContext context, int index, String fallbackRoute) {
  final shell = BirdShellNavigation.maybeOf(context);
  if (shell != null) {
    shell.selectTab(index);
  } else {
    Navigator.of(context).pushNamed(fallbackRoute);
  }
}
