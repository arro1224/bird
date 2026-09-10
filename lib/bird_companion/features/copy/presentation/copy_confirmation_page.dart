import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_scope_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_device_card.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 复制流程：入口 → 配置 → 确认 → 创建（birdbox-copy-v1）。
///
/// 批次复制（复制照片 / 相册多选）与摄影资料全量备份共用本页面，通过
/// [initialScope] 与 [batchId] 区分。提交成功后展示结果并返回，任务进度页
/// 在后端交付后接入（阶段 D）。
class CopyConfirmationPage extends StatefulWidget {
  const CopyConfirmationPage({
    super.key,
    required this.batchId,
    this.initialScope,
    this.selectionId,
    this.selectionPhotoCount,
    this.selectionDiscardedCount,
  });

  /// 摄影资料全量备份为 null；批次复制为批次 id。
  final String? batchId;

  /// wire 值：`kept_assets`/`batch_all_assets`/`selected_assets`/
  /// `media_full_backup`；null 时按设置默认范围。
  final String? initialScope;
  final String? selectionId;
  final int? selectionPhotoCount;
  final int? selectionDiscardedCount;

  factory CopyConfirmationPage.fromArgs({required Object? args}) {
    if (args is CopyConfirmationArgs) {
      return CopyConfirmationPage(
        batchId: args.batchId,
        initialScope: args.scope,
        selectionId: args.selectionId,
        selectionPhotoCount: args.selectionPhotoCount,
        selectionDiscardedCount: args.selectionDiscardedCount,
      );
    }
    if (args is String) return CopyConfirmationPage(batchId: args);
    return const CopyConfirmationPage(batchId: null, initialScope: 'media_full_backup');
  }

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
      create: (_) {
        final scope = _initialScope(dependencies);
        return CopyConfigCubit(
          dependencies.copyRepository,
          batchId: widget.batchId,
          scope: scope,
          selectionId: widget.selectionId,
          selectionPhotoCount: widget.selectionPhotoCount,
          selectionDiscardedCount: widget.selectionDiscardedCount,
          preferredTargetMediaId: widget.batchId == null
              ? null
              : preferences.batchTargetPreferences[widget.batchId!.trim()],
          onRememberTarget: widget.batchId == null
              ? null
              : (batchId, mediaId) => dependencies.settingsStore.write(
                    dependencies.settingsStore.read().copyWith(
                      batchTargetPreferences: {
                        ...dependencies.settingsStore.read().batchTargetPreferences,
                        batchId: mediaId,
                      },
                    ),
                  ),
          dataChanges: dependencies.dataChangeBus,
          initialReviewExportEnabled: preferences.reviewExportEnabled,
          initialEmbedReviewMetadata: preferences.embedReviewMetadata,
        )..initialize();
      },
      child: FutureBuilder<DeviceStatus?>(
        future: _statusFuture,
        builder: (context, snapshot) => CopyConfigFlow(
          batchId: widget.batchId,
          lowBatteryPercent: _lowBatteryPercent(snapshot.data),
        ),
      ),
    );
  }

  CopyScope _initialScope(BirdCompanionDependencies dependencies) {
    final wire = widget.initialScope;
    if (wire != null && wire.trim().isNotEmpty) {
      return CopyScope.fromWire(wire);
    }
    final preferences = dependencies.settingsStore.read();
    return preferences.copyMode == 'batchAllAssets'
        ? CopyScope.batchAllAssets
        : CopyScope.keptAssets;
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

/// 成功提交后的反馈。后端交付后在此接入「查看任务进度」跳转（阶段 D）。
class _CopySubmitResult extends StatelessWidget {
  const _CopySubmitResult({required this.batchId, required this.jobId, required this.fullBackup});

  final String? batchId;
  final String jobId;
  final bool fullBackup;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(fullBackup ? '备份任务已创建' : '复制任务已创建'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('任务编号 $jobId'),
        const SizedBox(height: 10),
        Text(
          fullBackup
              ? '盒子将在后台完成摄影资料全量备份。任务进度与结果可在任务中心查看。'
              : '盒子将按确认的范围复制照片。任务进度与结果可在任务中心查看。',
          style: const TextStyle(height: 1.5),
        ),
      ],
    ),
    actions: [
      FilledButton(
        key: const Key('copy-submit-result-close'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('完成'),
      ),
    ],
  );
}

enum _CopyFlowStep { content, confirmation }

class CopyConfigFlow extends StatefulWidget {
  const CopyConfigFlow({
    super.key,
    required this.batchId,
    this.lowBatteryPercent,
    this.onSubmitted,
  });

  final String? batchId;
  final int? lowBatteryPercent;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CopyConfigFlow> createState() => _CopyConfigFlowState();
}

class _CopyConfigFlowState extends State<CopyConfigFlow> {
  var _step = _CopyFlowStep.content;

  @override
  Widget build(BuildContext context) => BlocConsumer<CopyConfigCubit, CopyConfigState>(
    listenWhen: (before, after) =>
        before.submitted != after.submitted || before.createdJob?.copyJobId != after.createdJob?.copyJobId,
    listener: (context, state) {
      if (!state.submitted || state.createdJob == null) return;
      final submitted = widget.onSubmitted;
      if (submitted != null) {
        submitted(state.createdJob!.copyJobId);
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CopySubmitResult(
          batchId: widget.batchId,
          jobId: state.createdJob!.copyJobId,
          fullBackup: state.fullBackup,
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
    },
    builder: (context, state) => PopScope(
      canPop: _step == _CopyFlowStep.content,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.loadingPreview && !state.submitting) {
          setState(() => _step = _CopyFlowStep.content);
        }
      },
      child: _step == _CopyFlowStep.content
          ? CopyContentStep(
              state: state,
              onBack: () => Navigator.maybePop(context),
              onScopeSelected: (scope) =>
                  context.read<CopyConfigCubit>().setScope(scope),
              onSourceSelected: context.read<CopyConfigCubit>().selectSource,
              onTargetSelected: context.read<CopyConfigCubit>().selectTarget,
              onPairPolicySelected: context.read<CopyConfigCubit>().setPairPolicy,
              onConflictSelected: context.read<CopyConfigCubit>().setConflictStrategy,
              onReviewExportChanged: context.read<CopyConfigCubit>().setReviewExportEnabled,
              onEmbedChanged: context.read<CopyConfigCubit>().setEmbedReviewMetadata,
              onSaveDefaults: () => _saveDefaults(context, state),
              onNext: () async {
                final ok = await context.read<CopyConfigCubit>().fetchPreview();
                if (ok && mounted) setState(() => _step = _CopyFlowStep.confirmation);
              },
            )
          : CopyFinalConfirmationStep(
              state: state,
              lowBatteryPercent: widget.lowBatteryPercent,
              onBack: state.loadingPreview || state.submitting
                  ? null
                  : () => setState(() => _step = _CopyFlowStep.content),
              onRefreshPreview: state.submitting
                  ? null
                  : () => context.read<CopyConfigCubit>().fetchPreview(),
              onSubmit: context.read<CopyConfigCubit>().submit,
            ),
    ),
  );

  Future<void> _saveDefaults(
    BuildContext context,
    CopyConfigState state,
  ) async {
    final dependencies = BirdCompanionScope.of(context);
    final current = dependencies.settingsStore.read();
    final scopeValue = switch (state.scope) {
      CopyScope.batchAllAssets => 'batchAllAssets',
      _ => 'keptAssets',
    };
    await dependencies.settingsStore.write(
      current.copyWith(
        copyMode: scopeValue,
        reviewExportEnabled: state.reviewExport.enabled,
        embedReviewMetadata: state.reviewExport.embedIntoSupportedCopy,
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
    required this.onScopeSelected,
    required this.onSourceSelected,
    required this.onTargetSelected,
    required this.onPairPolicySelected,
    required this.onConflictSelected,
    required this.onReviewExportChanged,
    required this.onEmbedChanged,
    required this.onSaveDefaults,
    required this.onNext,
  });

  final CopyConfigState state;
  final VoidCallback onBack;
  final ValueChanged<CopyScope> onScopeSelected;
  final ValueChanged<String> onSourceSelected;
  final ValueChanged<String> onTargetSelected;
  final ValueChanged<PairPolicy> onPairPolicySelected;
  final ValueChanged<ConflictStrategy> onConflictSelected;
  final ValueChanged<bool> onReviewExportChanged;
  final ValueChanged<bool> onEmbedChanged;
  final VoidCallback onSaveDefaults;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final fullBackup = state.fullBackup;
    return _CopyFlowFrame(
      key: const Key('copy-content-step'),
      title: fullBackup ? '摄影资料全量备份' : '复制照片',
      subtitle: fullBackup ? '备份源设备全部摄影资料' : '步骤 1 / 2 · 配置复制',
      loading: state.loadingDevices || state.loadingPreview,
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
              onPressed: state.canFetchPreview ? onNext : null,
              child: const Text('获取预检并继续'),
            ),
          ),
          if (!fullBackup) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                key: const Key('copy-save-defaults'),
                onPressed: state.loadingDevices ? null : onSaveDefaults,
                child: const Text('保存为默认策略'),
              ),
            ),
          ],
        ],
      ),
      children: [
        if (state.scope == CopyScope.selectedAssets) _selectedAssetsNotice(context),
        if (!state.scopeFixed) _scopeSection(context),
        if (!fullBackup) ...[
          const SizedBox(height: 14),
          _pairPolicySection(context),
        ],
        const SizedBox(height: 14),
        _deviceSections(context),
        const SizedBox(height: 14),
        _conflictSection(context),
        const SizedBox(height: 14),
        _reviewExportSection(context),
        const SizedBox(height: 14),
        _previewHint(context),
      ],
    );
  }

  /// 相册多选入口：范围固定为「已选择 N 张」，显示弃选数量提醒（§3.2）。
  Widget _selectedAssetsNotice(BuildContext context) => _SectionCard(
    title: '复制范围',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_library_outlined, color: AppColors.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '已选择 ${state.selectionPhotoCount ?? 0} 张照片',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.forestDeep,
                ),
              ),
            ),
          ],
        ),
        if ((state.selectionDiscardedCount ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            '其中 ${state.selectionDiscardedCount} 张为已弃选照片，复制不会改变其审阅状态。',
            style: const TextStyle(color: AppColors.pending, fontSize: 12.5, height: 1.4),
          ),
        ],
      ],
    ),
  );

  Widget _scopeSection(BuildContext context) => _SectionCard(
    title: '复制范围',
    child: Column(
      children: [
        CopyScopeCard(
          scope: CopyScope.keptAssets,
          title: '复制已保留',
          subtitle: '仅复制本批次标记为保留的照片',
          selected: state.scope == CopyScope.keptAssets,
          recommended: true,
          onTap: state.loadingDevices ? null : () => onScopeSelected(CopyScope.keptAssets),
        ),
        CopyScopeCard(
          scope: CopyScope.batchAllAssets,
          title: '复制本批次全部照片',
          subtitle: '不做筛选，复制这次拍摄中的所有照片',
          selected: state.scope == CopyScope.batchAllAssets,
          onTap: state.loadingDevices ? null : () => onScopeSelected(CopyScope.batchAllAssets),
        ),
      ],
    ),
  );

  Widget _pairPolicySection(BuildContext context) => _SectionCard(
    title: 'RAW + JPEG 策略',
    child: Column(
      children: [
        for (final policy in PairPolicy.values)
          _RadioOption<PairPolicy>(
            value: policy,
            selected: state.pairPolicy == policy,
            title: policy.label,
            subtitle: _pairPolicySubtitle(policy),
            onTap: state.loadingDevices ? null : () => onPairPolicySelected(policy),
          ),
      ],
    ),
  );

  Widget _deviceSections(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('源设备'),
      if (state.loadingDevices)
        const _LoadingPlaceholder()
      else if (state.availableSources.isEmpty)
        const _EmptyDeviceHint('没有可用于复制的源设备')
      else
        for (final device in state.availableSources)
          StorageDeviceCard(
            device: device,
            role: '源设备',
            selected: state.sourceMediaId == device.mediaId,
            onTap: () => onSourceSelected(device.mediaId),
          ),
      const SizedBox(height: 14),
      const _SectionTitle('目标设备'),
      if (state.loadingDevices)
        const _LoadingPlaceholder()
      else if (_targetCandidates(state).isEmpty)
        const _EmptyDeviceHint('没有可用的目标设备，请检查盒子外接存储')
      else
        for (final device in _targetCandidates(state))
          StorageDeviceCard(
            device: device,
            role: '目标设备',
            selected: state.targetMediaId == device.mediaId,
            lastUsedForBatch: _isLastUsedForBatch(device.mediaId, context, state.batchId),
            onTap: () => onTargetSelected(device.mediaId),
          ),
      if (state.targetMediaId == null && state.preferredTargetMediaId != null) ...[
        const SizedBox(height: 4),
        const Text(
          '上次使用的目标设备当前不可用，请重新选择；不会自动切换到其他设备。',
          style: TextStyle(color: AppColors.danger, fontSize: 12.5),
        ),
      ],
    ],
  );

  /// 目标列表包含在线可选设备与「在场但被禁用」的设备，卡片必须显示不可选
  /// 原因，不得仅灰掉选项（§4.3）。
  static List<StorageDeviceSummary> _targetCandidates(CopyConfigState state) {
    final all = state.devices;
    return all
        .where(
          (device) =>
              (device.online && device.canBeTarget) ||
              !device.online ||
              device.targetBlockReasons.isNotEmpty,
        )
        .toList(growable: false);
  }

  static bool _isLastUsedForBatch(
    String mediaId,
    BuildContext context,
    String? batchId,
  ) {
    final id = batchId?.trim();
    if (id == null || id.isEmpty) return false;
    final dependencies = BirdCompanionScope.maybeOf(context);
    if (dependencies == null) return false;
    return dependencies.settingsStore.read().batchTargetPreferences[id] ==
        mediaId;
  }

  Widget _conflictSection(BuildContext context) => _SectionCard(
    title: '同名文件处理（必选）',
    child: Column(
      children: [
        for (final strategy in ConflictStrategy.values)
          _RadioOption<ConflictStrategy>(
            value: strategy,
            selected: state.conflictStrategy == strategy,
            title: strategy.label,
            subtitle: _conflictSubtitle(strategy),
            onTap: () => onConflictSelected(strategy),
          ),
      ],
    ),
  );

  Widget _reviewExportSection(BuildContext context) => _SectionCard(
    title: '随副本保存审阅信息',
    child: Column(
      children: [
        SwitchListTile(
          key: const Key('copy-review-export-toggle'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.description_outlined, color: AppColors.brand),
          title: const Text('保存 XMP 与审阅 CSV', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('在目标盘写入评分、标签、鸟种和保留状态'),
          value: state.reviewExport.enabled,
          onChanged: state.loadingDevices ? null : onReviewExportChanged,
        ),
        if (state.reviewExport.enabled) ...[
          SwitchListTile(
            key: const Key('copy-review-embed-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('支持时写入副本', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('向 JPEG/HEIF/TIFF 副本嵌入标准字段；RAW 只写 sidecar'),
            value: state.reviewExport.embedIntoSupportedCopy,
            onChanged: onEmbedChanged,
          ),
        ],
      ],
    ),
  );

  Widget _previewHint(BuildContext context) => _SectionCard(
    title: '获取预检',
    child: Text(
      state.canFetchPreview
          ? '点击下方按钮获取复制预检：照片数、文件数、预计写入量与目标空间。'
          : _previewRequirementText(),
      style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.5),
    ),
  );

  String _previewRequirementText() {
    if (state.scope == CopyScope.selectedAssets && state.selectionId == null) {
      return '需要先创建选择快照，请返回相册重新发起。';
    }
    if (state.conflictStrategy == null) return '请先选择同名文件处理策略，再获取预检。';
    if (state.sourceMediaId == null || state.targetMediaId == null) {
      return '请先选择源设备与目标设备，再获取预检。';
    }
    return '请选择完整配置后获取预检。';
  }

  static String _pairPolicySubtitle(PairPolicy policy) => switch (policy) {
    PairPolicy.rawOnly => '有 RAW 时复制 RAW，无 RAW 时复制可用成片（默认）',
    PairPolicy.jpegOnly => '仅复制 JPEG/HEIF，无成片时该项记为不适用',
    PairPolicy.both => 'RAW 与 JPEG/HEIF 都复制',
  };

  static String _conflictSubtitle(ConflictStrategy strategy) => switch (strategy) {
    ConflictStrategy.skip => '保留目标盘已有文件，该项记为已跳过',
    ConflictStrategy.overwrite => '先写入临时文件并校验，最后原子替换',
    ConflictStrategy.keepBoth => '文件名加 (1)(2) 后缀，两份都保留',
  };
}

class CopyFinalConfirmationStep extends StatelessWidget {
  const CopyFinalConfirmationStep({
    super.key,
    required this.state,
    required this.onBack,
    required this.onRefreshPreview,
    required this.onSubmit,
    this.lowBatteryPercent,
  });

  final CopyConfigState state;
  final VoidCallback? onBack;
  final VoidCallback? onRefreshPreview;
  final VoidCallback onSubmit;
  final int? lowBatteryPercent;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview;
    final blockReason = state.submissionBlockReason;
    final canSubmit = blockReason == null && !state.loadingPreview && !state.submitting;
    return _CopyFlowFrame(
      key: const Key('copy-final-confirmation-step'),
      title: '确认复制',
      subtitle: '步骤 2 / 2 · 最后确认',
      loading: state.loadingPreview || state.submitting,
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
              child: Text(state.submitting ? '正在创建任务…' : '开始复制'),
            ),
          ),
          if (blockReason != null) ...[
            const SizedBox(height: 8),
            Text(blockReason, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              key: const Key('copy-return-to-edit'),
              onPressed: state.loadingPreview || state.submitting ? null : onBack,
              child: const Text('返回修改'),
            ),
          ),
        ],
      ),
      children: [
        if (preview == null) ...[
          const Card(child: SizedBox(height: 96, child: Center(child: CircularProgressIndicator()))),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _SummaryRow(icon: Icons.photo_library_outlined, label: '复制范围', value: _scopeLabel(state)),
                  _SummaryRow(icon: Icons.sd_card_outlined, label: '源设备', value: preview.source.presentationName),
                  _SummaryRow(icon: Icons.save_alt_rounded, label: '目标设备', value: preview.target.presentationName),
                  _SummaryRow(icon: Icons.photo_outlined, label: '照片数', value: '${_formatCount(preview.logicalPhotoCount)} 张逻辑照片 · ${_formatCount(preview.actualFileCount)} 个文件'),
                  if (state.fullBackup) ...[
                    _SummaryRow(icon: Icons.videocam_outlined, label: '视频 / 伴随文件', value: '${_formatCount(preview.videoCount)} / ${_formatCount(preview.companionCount)}'),
                  ] else ...[
                    _SummaryRow(icon: Icons.camera_outlined, label: 'RAW / JPEG', value: '${_formatCount(preview.rawCount)} / ${_formatCount(preview.jpegCount)}'),
                  ],
                  _SummaryRow(icon: Icons.shield_outlined, label: '同名文件处理', value: state.conflictStrategy?.label ?? '未选择'),
                  _SummaryRow(icon: Icons.description_outlined, label: '审阅信息', value: _reviewExportLabel(state)),
                  _SummaryRow(icon: Icons.data_usage_rounded, label: '预计写入量', value: _formatBytes(preview.totalBytes)),
                  _SummaryRow(
                    icon: Icons.space_bar_rounded,
                    label: '目标剩余空间 / 安全余量',
                    value: '${_formatBytes(preview.targetFreeBytes)} / ${_formatBytes(preview.safetyReserveBytes)}',
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
                  const Icon(Icons.battery_alert_rounded, color: AppColors.pending),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('盒子电量仅剩 $lowBatteryPercent%，建议连接电源后再复制。'),
                  ),
                ],
              ),
            ),
          ],
          if (preview.isExpired) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer_off_outlined, color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '预检已过期，请重新获取后再创建任务。',
                    style: TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
                TextButton(onPressed: onRefreshPreview, child: const Text('重新获取')),
              ],
            ),
          ],
        ],
      ],
    );
  }

  static String _scopeLabel(CopyConfigState state) => switch (state.scope) {
    CopyScope.selectedAssets => '已选择 ${state.selectionPhotoCount ?? 0} 张',
    CopyScope.keptAssets => '复制已保留',
    CopyScope.batchAllAssets => '复制本批次全部照片',
    CopyScope.mediaFullBackup => '摄影资料全量备份',
  };

  static String _reviewExportLabel(CopyConfigState state) {
    final config = state.reviewExport;
    if (!config.enabled) return '不向目标盘导出审阅信息';
    return config.embedIntoSupportedCopy
        ? 'XMP + CSV，支持格式嵌入副本'
        : 'XMP + CSV（不嵌入副本）';
  }
}

class _RadioOption<T> extends StatelessWidget {
  const _RadioOption({
    required this.value,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final T value;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.brand : AppColors.inkMuted,
              size: 23,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.forestDeep : AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
              _CopyFlowHeader(title: title, subtitle: subtitle, onBack: onBack),
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
  const _CopyFlowHeader({required this.title, required this.subtitle, this.onBack});

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
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestDeep),
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
                    style: const TextStyle(color: AppColors.mutedInk, fontSize: 14),
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
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  final CopyConfigState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (state.devicesError != null) ...[
        const SizedBox(height: 8),
        Text(
          _errorText(state.devicesError!),
          style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
        ),
      ],
      if (state.error != null) ...[
        const SizedBox(height: 8),
        Text(
          _errorText(state.error!),
          style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
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
    child: SizedBox(height: 96, child: Center(child: CircularProgressIndicator())),
  );
}

class _EmptyDeviceHint extends StatelessWidget {
  const _EmptyDeviceHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.usb_off_rounded, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
          ),
        ],
      ),
    ),
  );
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';

String _formatCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);
