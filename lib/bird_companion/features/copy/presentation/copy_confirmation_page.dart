import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/widgets/page_back_button.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_confirm_dialog.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_mode_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_target_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CopyConfirmationPage extends StatefulWidget {
  const CopyConfirmationPage({super.key, required this.batchId});

  final String batchId;

  @override
  State<CopyConfirmationPage> createState() => _CopyConfirmationPageState();
}

class _CopyConfirmationPageState extends State<CopyConfirmationPage> {
  BirdCompanionDependencies? _dependencies;
  Future<DeviceStatus?>? _statusFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = BirdCompanionScope.of(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    final preferences = dependencies.settingsStore.read();
    _statusFuture = preferences.lowBatteryReminder ? _readStatus(dependencies) : Future<DeviceStatus?>.value();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies!;
    final preferences = dependencies.settingsStore.read();
    return BlocProvider(
      create: (_) => CopyConfirmationCubit(
        dependencies.copyRepository,
        widget.batchId,
        dependencies.dataChangeBus,
        _copyModeWireValue(preferences.copyMode),
        preferences.selectedStorageId,
        preferences.xmpStrategy != '不导出标记',
        preferences.verifyCopies,
      )..load(),
      child: FutureBuilder<DeviceStatus?>(
        future: _statusFuture,
        builder: (context, snapshot) => _View(
          batchId: widget.batchId,
          lowBatteryPercent: _lowBatteryPercent(snapshot.data),
        ),
      ),
    );
  }

  Future<DeviceStatus?> _readStatus(
    BirdCompanionDependencies dependencies,
  ) async {
    try {
      return await dependencies.deviceRepository.fetchStatus();
    } catch (_) {
      return null;
    }
  }

  int? _lowBatteryPercent(DeviceStatus? status) {
    if (status == null || status.isExternalPower) return null;
    final percent = status.batteryPercent;
    return percent != null && percent <= 15 ? percent : null;
  }
}

class _View extends StatelessWidget {
  const _View({required this.batchId, this.lowBatteryPercent});

  final String batchId;
  final int? lowBatteryPercent;

  @override
  Widget build(BuildContext context) => BlocConsumer<CopyConfirmationCubit, CopyConfirmationState>(
    listener: (context, state) {
      if (state.submitted && state.jobId != null) {
        Navigator.of(context).pushReplacementNamed(
          BirdRoutes.jobDetail,
          arguments: JobDetailArgs(state.jobId!, sourceBatchId: batchId),
        );
      }
    },
    builder: (context, state) {
      final estimate = state.estimate;
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(leading: const BirdPageBackButton(), centerTitle: true, title: const Text('复制照片')),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                if (estimate != null) _ReviewSummary(estimate: estimate),
                const SizedBox(height: 18),
                const _SectionTitle('复制模式'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (final mode in ['keep', 'all', 'dual'])
                          CopyModeCard(
                            mode: mode,
                            selected: state.mode == mode,
                            estimate: state.mode == mode ? estimate : null,
                            onTap: state.loading ? null : () => context.read<CopyConfirmationCubit>().load(mode),
                          ),
                      ],
                    ),
                  ),
                ),
                if (estimate != null) ...[
                  const SizedBox(height: 18),
                  const _SectionTitle('目标存储'),
                  for (final target in estimate.targets)
                    StorageTargetCard(
                      target: target,
                      selected: state.targetId == target.id,
                      onTap: () => context.read<CopyConfirmationCubit>().selectTarget(target.id),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(Icons.description_outlined, color: AppColors.brand),
                      title: const Text('同时保存照片编辑信息', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('方便在其他照片软件中继续使用评分、标签和鸟种信息'),
                      value: state.xmpEnabled,
                      onChanged: state.loading ? null : context.read<CopyConfirmationCubit>().setXmpEnabled,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.amberLight.withValues(alpha: .65), borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: AppColors.pending),
                        SizedBox(width: 8),
                        Expanded(child: Text('复制操作不会修改或删除相机存储卡中的原始照片')),
                      ],
                    ),
                  ),
                ],
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Builder(
                      builder: (_) {
                        final message = UserMessageMapper.fromError(
                          state.error!,
                        );
                        return Text(
                          '${message.title}：${message.message}',
                          style: const TextStyle(color: AppColors.danger),
                        );
                      },
                    ),
                  ),
                if (state.submissionBlockReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(state.submissionBlockReason!, style: const TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: state.loading || state.submissionBlockReason != null || estimate == null
                      ? null
                      : () => showDialog(
                          context: context,
                          builder: (_) => CopyConfirmDialog(
                            fileCount: estimate.fileCount,
                            requiredBytes: estimate.requiredBytes,
                            targetName: state.selectedTarget?.name ?? '目标存储',
                            xmpEnabled: state.xmpEnabled,
                            lowBatteryPercent: lowBatteryPercent,
                            onConfirm: () => context.read<CopyConfirmationCubit>().submit(),
                          ),
                        ),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(state.loading ? '处理中…' : '开始复制 ${estimate?.fileCount ?? 0} 张照片'),
                ),
              ),
            ),
            if (state.loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
          ],
        ),
      );
    },
  );
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.estimate});

  final CopyEstimate estimate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: AppColors.brand),
              SizedBox(width: 8),
              Text(
                '审阅已完成',
                style: TextStyle(fontSize: 21, color: AppColors.brand, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              _Metric(value: '${estimate.fileCount}', label: '本次照片'),
              _Metric(value: '${estimate.pendingCount}', label: '待确认'),
              _Metric(value: _formatBytes(estimate.requiredBytes), label: '预计用量'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.inkMuted)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, color: AppColors.inkMuted, fontWeight: FontWeight.w700),
    ),
  );
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB' : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';

String _copyModeWireValue(String value) => switch (value) {
  'all' => 'all',
  'dualTrack' => 'dual',
  _ => 'keep',
};
