import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_mode_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_target_card.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
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
        builder: (context, snapshot) => CopyConfirmationFlow(
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

enum _CopyFlowStep { content, confirmation }

class CopyConfirmationFlow extends StatefulWidget {
  const CopyConfirmationFlow({
    super.key,
    required this.batchId,
    this.lowBatteryPercent,
    this.onSubmitted,
  });

  final String batchId;
  final int? lowBatteryPercent;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CopyConfirmationFlow> createState() => _CopyConfirmationFlowState();
}

class _CopyConfirmationFlowState extends State<CopyConfirmationFlow> {
  var _step = _CopyFlowStep.content;

  @override
  Widget build(BuildContext context) => BlocConsumer<CopyConfirmationCubit, CopyConfirmationState>(
    listenWhen: (before, after) => before.submitted != after.submitted || before.jobId != after.jobId,
    listener: (context, state) {
      if (!state.submitted || state.jobId == null) return;
      final submitted = widget.onSubmitted;
      if (submitted != null) {
        submitted(state.jobId!);
        return;
      }
      Navigator.of(context).pushReplacementNamed(
        BirdRoutes.jobDetail,
        arguments: JobDetailArgs(
          state.jobId!,
          sourceBatchId: widget.batchId,
        ),
      );
    },
    builder: (context, state) => PopScope(
      canPop: _step == _CopyFlowStep.content,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.loading) {
          setState(() => _step = _CopyFlowStep.content);
        }
      },
      child: _step == _CopyFlowStep.content
          ? CopyContentStep(
              state: state,
              onBack: () => Navigator.maybePop(context),
              onModeSelected: context.read<CopyConfirmationCubit>().load,
              onTargetSelected: context.read<CopyConfirmationCubit>().selectTarget,
              onXmpChanged: context.read<CopyConfirmationCubit>().setXmpEnabled,
              onNext: () => setState(
                () => _step = _CopyFlowStep.confirmation,
              ),
              onSaveDefaults: () => _saveDefaults(context, state),
            )
          : CopyFinalConfirmationStep(
              state: state,
              lowBatteryPercent: widget.lowBatteryPercent,
              onBack: state.loading
                  ? null
                  : () => setState(
                      () => _step = _CopyFlowStep.content,
                    ),
              onSubmit: context.read<CopyConfirmationCubit>().submit,
            ),
    ),
  );

  Future<void> _saveDefaults(
    BuildContext context,
    CopyConfirmationState state,
  ) async {
    final dependencies = BirdCompanionScope.of(context);
    final targetId = state.targetId;
    final current = dependencies.settingsStore.read();
    await dependencies.settingsStore.write(
      current.copyWith(
        copyMode: _copyModeSettingValue(state.mode),
        xmpStrategy: state.xmpEnabled ? '生成同名 XMP（推荐）' : '不导出标记',
        selectedStorageId: targetId,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存为默认复制策略')),
    );
  }
}

class CopyContentStep extends StatelessWidget {
  const CopyContentStep({
    super.key,
    required this.state,
    required this.onBack,
    required this.onModeSelected,
    required this.onTargetSelected,
    required this.onXmpChanged,
    required this.onNext,
    required this.onSaveDefaults,
  });

  final CopyConfirmationState state;
  final VoidCallback onBack;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<String> onTargetSelected;
  final ValueChanged<bool> onXmpChanged;
  final VoidCallback onNext;
  final VoidCallback onSaveDefaults;

  @override
  Widget build(BuildContext context) {
    final estimate = state.estimate;
    final canContinue = !state.loading && estimate != null && state.submissionBlockReason == null;
    return _CopyFlowFrame(
      key: const Key('copy-content-step'),
      title: '复制照片',
      subtitle: '步骤 2 / 3 · 选择复制内容',
      loading: state.loading,
      onBack: onBack,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateMessages(state: state),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('copy-content-next'),
              onPressed: canContinue ? onNext : null,
              child: const Text('下一步'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              key: const Key('copy-save-defaults'),
              onPressed: estimate == null || state.loading ? null : onSaveDefaults,
              child: const Text('保存为默认策略'),
            ),
          ),
        ],
      ),
      children: [
        _SectionCard(
          title: '复制范围',
          child: Column(
            children: [
              for (final mode in const ['keep', 'all', 'dual'])
                CopyModeCard(
                  mode: mode,
                  selected: state.mode == mode,
                  estimate: state.mode == mode ? estimate : null,
                  onTap: state.loading ? null : () => onModeSelected(mode),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SectionTitle('目标存储'),
        if (estimate == null)
          const _LoadingPlaceholder()
        else
          for (final target in estimate.targets)
            StorageTargetCard(
              target: target,
              selected: state.targetId == target.id,
              requiredBytes: estimate.requiredBytes,
              onTap: () => onTargetSelected(target.id),
            ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            key: const Key('copy-xmp-toggle'),
            secondary: const Icon(
              Icons.description_outlined,
              color: AppColors.brand,
            ),
            title: const Text(
              '生成同名 XMP',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('写入评分、标签、鸟种和保留状态'),
            value: state.xmpEnabled,
            onChanged: state.loading ? null : onXmpChanged,
          ),
        ),
      ],
    );
  }
}

class CopyFinalConfirmationStep extends StatelessWidget {
  const CopyFinalConfirmationStep({
    super.key,
    required this.state,
    required this.onBack,
    required this.onSubmit,
    this.lowBatteryPercent,
  });

  final CopyConfirmationState state;
  final VoidCallback? onBack;
  final VoidCallback onSubmit;
  final int? lowBatteryPercent;

  @override
  Widget build(BuildContext context) {
    final estimate = state.estimate;
    final selectedTarget = state.selectedTarget;
    final canSubmit = !state.loading && estimate != null && state.submissionBlockReason == null;
    return _CopyFlowFrame(
      key: const Key('copy-final-confirmation-step'),
      title: '确认复制',
      subtitle: '步骤 3 / 3 · 最后确认',
      loading: state.loading,
      onBack: onBack,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateMessages(state: state),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('copy-final-submit'),
              onPressed: canSubmit ? onSubmit : null,
              child: Text(state.loading ? '正在创建任务…' : '开始复制'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              key: const Key('copy-return-to-edit'),
              onPressed: state.loading ? null : onBack,
              child: const Text('返回修改'),
            ),
          ),
        ],
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                _SummaryRow(
                  icon: Icons.photo_library_outlined,
                  label: '复制范围',
                  value: _copyModeLabel(state.mode),
                ),
                _SummaryRow(
                  icon: Icons.photo_outlined,
                  label: '照片数量',
                  value: estimate == null ? '--' : '${_formatCount(estimate.fileCount)} 张',
                ),
                _SummaryRow(
                  icon: Icons.save_alt_rounded,
                  label: '预计使用空间',
                  value: estimate == null ? '--' : _formatBytes(estimate.requiredBytes),
                ),
                _SummaryRow(
                  icon: Icons.storage_rounded,
                  label: '目标存储',
                  value: selectedTarget?.name ?? '未选择',
                ),
                _SummaryRow(
                  icon: Icons.description_outlined,
                  label: 'XMP',
                  value: state.xmpEnabled ? '已开启' : '未开启',
                  divider: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('copy-production-safety-notice'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandLight.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.brand),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '不会修改或删除相机存储卡中的原始照片。\n复制期间请勿拔出目标存储设备。',
                  style: TextStyle(height: 1.45),
                ),
              ),
            ],
          ),
        ),
        if (lowBatteryPercent != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('copy-low-battery-warning'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.battery_alert_rounded,
                  color: AppColors.pending,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '盒子电量仅剩 $lowBatteryPercent%，建议连接电源后再复制。',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                const _SummaryRow(
                  icon: Icons.schedule_outlined,
                  label: '预计耗时',
                  value: '任务开始后由盒子计算',
                ),
                _SummaryRow(
                  icon: Icons.shield_outlined,
                  label: '复制完成后校验',
                  value: state.verifyAfterCopy ? '开启' : '关闭',
                  divider: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CopyFlowFrame extends StatelessWidget {
  const _CopyFlowFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.footer,
    required this.loading,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget footer;
  final bool loading;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        const Positioned.fill(child: TaskNatureBackground()),
        SafeArea(
          child: Column(
            children: [
              _CopyFlowHeader(
                title: title,
                subtitle: subtitle,
                onBack: onBack,
              ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  children: children,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: footer,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CopyFlowHeader extends StatelessWidget {
  const _CopyFlowHeader({
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final height = (100 + 72 * (textScale - 1)).clamp(100, 160).toDouble();
    return Semantics(
      key: const Key('copy-flow-titlebar'),
      container: true,
      header: true,
      label: '$title，$subtitle',
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: NavigationToolbar(
            leading: SizedBox(
              width: 48,
              child: IconButton(
                key: const Key('copy-flow-back'),
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.forestDeep,
                ),
              ),
            ),
            middle: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: const Key('copy-flow-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.forestDeep,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    key: const Key('copy-flow-subtitle'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.mutedInk,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            trailing: const SizedBox(width: 48),
            centerMiddle: true,
            middleSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.forestDeep,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
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
      style: const TextStyle(
        color: AppColors.forestDeep,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.divider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: AppColors.forestDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
}

class _StateMessages extends StatelessWidget {
  const _StateMessages({required this.state});

  final CopyConfirmationState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (state.error != null) ...[
        const SizedBox(height: 12),
        Text(
          _errorText(state.error!),
          style: const TextStyle(color: AppColors.danger),
        ),
      ],
      if (state.submissionBlockReason != null) ...[
        const SizedBox(height: 12),
        Text(
          state.submissionBlockReason!,
          style: const TextStyle(color: AppColors.danger),
        ),
      ],
    ],
  );

  static String _errorText(Object error) {
    final message = UserMessageMapper.fromError(error);
    return '${message.title}：${message.message}';
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) => const Card(
    child: SizedBox(
      height: 96,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB' : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';

String _formatCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);

String _copyModeLabel(String mode) => switch (mode) {
  'all' => '复制全部照片',
  'dual' => '双轨复制',
  _ => '仅保留照片',
};

String _copyModeWireValue(String value) => switch (value) {
  'all' => 'all',
  'dualTrack' => 'dual',
  _ => 'keep',
};

String _copyModeSettingValue(String value) => switch (value) {
  'all' => 'all',
  'dual' => 'dualTrack',
  _ => 'keptOnly',
};
