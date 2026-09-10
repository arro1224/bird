import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CopyConfigState {
  const CopyConfigState({
    required this.scope,
    this.batchId,
    this.selectionId,
    this.selectionPhotoCount,
    this.selectionDiscardedCount,
    this.preferredTargetMediaId,
    this.pairPolicy = PairPolicy.rawOnly,
    this.sourceMediaId,
    this.targetMediaId,
    this.conflictStrategy,
    this.reviewExport = const ReviewExportConfig(
      enabled: true,
      writeXmp: true,
      writeCsv: true,
      embedIntoSupportedCopy: true,
    ),
    this.devices = const [],
    this.loadingDevices = true,
    this.devicesError,
    this.preview,
    this.loadingPreview = false,
    this.submitting = false,
    this.submitted = false,
    this.createdJob,
    this.error,
  });

  final CopyScope scope;
  final String? batchId;
  final String? selectionId;
  final int? selectionPhotoCount;
  final int? selectionDiscardedCount;
  final String? preferredTargetMediaId;
  final PairPolicy pairPolicy;
  final String? sourceMediaId;
  final String? targetMediaId;
  final ConflictStrategy? conflictStrategy;
  final ReviewExportConfig reviewExport;
  final List<StorageDeviceSummary> devices;
  final bool loadingDevices;
  final Object? devicesError;
  final CopyPreview? preview;
  final bool loadingPreview;
  final bool submitting;
  final bool submitted;
  final CopyJobSummary? createdJob;
  final Object? error;

  bool get fullBackup => scope == CopyScope.mediaFullBackup;

  /// selected_assets 与全量备份的范围由入口固定，页面不展示范围列表（§3.3）。
  bool get scopeFixed =>
      scope == CopyScope.selectedAssets || scope == CopyScope.mediaFullBackup;

  StorageDeviceSummary? get sourceDevice => _device(sourceMediaId);
  StorageDeviceSummary? get targetDevice => _device(targetMediaId);

  StorageDeviceSummary? _device(String? id) {
    if (id == null) return null;
    return devices.where((device) => device.mediaId == id).firstOrNull;
  }

  List<StorageDeviceSummary> get availableSources => devices
      .where((device) => device.online && device.canBeSource)
      .toList(growable: false);

  List<StorageDeviceSummary> get availableTargets => devices
      .where((device) => device.online && device.canBeTarget)
      .toList(growable: false);

  bool get canFetchPreview =>
      !loadingDevices &&
      devices.isNotEmpty &&
      sourceMediaId != null &&
      targetMediaId != null &&
      conflictStrategy != null &&
      (scope != CopyScope.selectedAssets || selectionId != null);

  String? get submissionBlockReason {
    if (conflictStrategy == null) return '请选择同名文件处理策略';
    final source = sourceDevice;
    final target = targetDevice;
    if (source == null) return '请选择源设备';
    if (target == null) return '请选择目标设备';
    if (source.mediaId == target.mediaId) return '源设备与目标设备不能相同';
    final previewValue = preview;
    if (previewValue == null) return '请先获取预检';
    if (previewValue.isExpired) return '预检已过期，请重新获取';
    if (!previewValue.hasEnoughSpace) return '目标设备空间不足，请更换目标设备';
    return null;
  }

  CopyRequestDraft get draft => CopyRequestDraft(
    batchId: batchId,
    scope: scope,
    selectionId: selectionId,
    sourceMediaId: sourceMediaId!,
    targetMediaId: targetMediaId!,
    pairPolicy: pairPolicy,
    conflictStrategy: conflictStrategy,
    reviewExport: reviewExport,
  );

  CopyConfigState copyWith({
    CopyScope? scope,
    String? batchId,
    String? selectionId,
    int? selectionPhotoCount,
    int? selectionDiscardedCount,
    String? preferredTargetMediaId,
    PairPolicy? pairPolicy,
    String? sourceMediaId,
    String? targetMediaId,
    ConflictStrategy? conflictStrategy,
    ReviewExportConfig? reviewExport,
    List<StorageDeviceSummary>? devices,
    bool? loadingDevices,
    Object? devicesError,
    bool clearDevicesError = false,
    CopyPreview? preview,
    bool clearPreview = false,
    bool clearSourceMediaId = false,
    bool clearTargetMediaId = false,
    bool clearSelectionId = false,
    bool? loadingPreview,
    bool? submitting,
    bool? submitted,
    CopyJobSummary? createdJob,
    Object? error,
    bool clearError = false,
  }) => CopyConfigState(
    scope: scope ?? this.scope,
    batchId: batchId ?? this.batchId,
    selectionId: clearSelectionId ? null : selectionId ?? this.selectionId,
    selectionPhotoCount:
        clearSelectionId ? null : selectionPhotoCount ?? this.selectionPhotoCount,
    selectionDiscardedCount:
        clearSelectionId ? null : selectionDiscardedCount ?? this.selectionDiscardedCount,
    preferredTargetMediaId: preferredTargetMediaId ?? this.preferredTargetMediaId,
    pairPolicy: pairPolicy ?? this.pairPolicy,
    sourceMediaId: clearSourceMediaId
        ? null
        : sourceMediaId ?? this.sourceMediaId,
    targetMediaId: clearTargetMediaId
        ? null
        : targetMediaId ?? this.targetMediaId,
    conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    reviewExport: reviewExport ?? this.reviewExport,
    devices: devices ?? this.devices,
    loadingDevices: loadingDevices ?? this.loadingDevices,
    devicesError: clearDevicesError ? null : devicesError ?? this.devicesError,
    preview: clearPreview ? null : preview ?? this.preview,
    loadingPreview: loadingPreview ?? this.loadingPreview,
    submitting: submitting ?? this.submitting,
    submitted: submitted ?? this.submitted,
    createdJob: createdJob ?? this.createdJob,
    error: clearError ? null : error ?? this.error,
  );
}

/// 复制配置状态机（birdbox-copy-v1 第 10 节：预检 → 创建）。
///
/// 同名策略没有默认值；未选择时 [CopyConfigState.submissionBlockReason]
/// 恒非空，页面不得在 Cubit 中补默认（协议 §8）。
class CopyConfigCubit extends Cubit<CopyConfigState> {
  CopyConfigCubit(
    this._repository, {
    required this.batchId,
    required this.scope,
    this.selectionId,
    this.selectionPhotoCount,
    this.selectionDiscardedCount,
    this.preferredTargetMediaId,
    this.onRememberTarget,
    this.dataChanges,
    this.initialPairPolicy = PairPolicy.rawOnly,
    this.initialReviewExportEnabled = true,
    this.initialEmbedReviewMetadata = true,
  }) : super(
         CopyConfigState(
           scope: scope,
           batchId: batchId,
           selectionId: selectionId,
           selectionPhotoCount: selectionPhotoCount,
           selectionDiscardedCount: selectionDiscardedCount,
           preferredTargetMediaId: preferredTargetMediaId,
           pairPolicy: initialPairPolicy,
           reviewExport: ReviewExportConfig(
             enabled: initialReviewExportEnabled,
             writeXmp: true,
             writeCsv: true,
             embedIntoSupportedCopy: initialEmbedReviewMetadata,
           ),
         ),
       );

  final CopyRepository _repository;
  final String? batchId;
  final CopyScope scope;
  final String? selectionId;
  final int? selectionPhotoCount;
  final int? selectionDiscardedCount;

  /// 同批次上次成功目标（§4.4），仅当该设备当前在线且可作为目标时预选。
  final String? preferredTargetMediaId;

  /// 创建成功后记录「同批次上次成功目标」。
  final void Function(String batchId, String mediaId)? onRememberTarget;
  final AppDataChangeBus? dataChanges;
  final PairPolicy initialPairPolicy;
  final bool initialReviewExportEnabled;
  final bool initialEmbedReviewMetadata;
  int _loadGeneration = 0;

  Future<void> initialize() async {
    final generation = ++_loadGeneration;
    try {
      final devices = await _repository.devices();
      if (isClosed || generation != _loadGeneration) return;
      final source = devices
          .where((device) => device.online && device.canBeSource)
          .firstOrNull;
      String? targetId;
      final preferred = preferredTargetMediaId;
      if (preferred != null && preferred.isNotEmpty) {
        final match = devices
            .where(
              (device) =>
                  device.mediaId == preferred &&
                  device.online &&
                  device.canBeTarget,
            )
            .firstOrNull;
        if (match != null) targetId = match.mediaId;
      }
      emit(
        state.copyWith(
          devices: devices,
          loadingDevices: false,
          sourceMediaId: source?.mediaId,
          targetMediaId: targetId,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(loadingDevices: false, devicesError: error));
    }
  }

  void selectSource(String mediaId) {
    final device = state._device(mediaId);
    if (device == null || !device.online || !device.canBeSource) return;
    emit(
      state.copyWith(
        sourceMediaId: mediaId,
        // 同一设备不能同时作为源与目标（§1.3）。
        clearTargetMediaId: state.targetMediaId == mediaId,
        clearPreview: true,
        clearError: true,
      ),
    );
  }

  void selectTarget(String mediaId) {
    final device = state._device(mediaId);
    if (device == null || !device.online || !device.canBeTarget) return;
    emit(
      state.copyWith(
        targetMediaId: mediaId,
        // 同一设备不能同时作为源与目标（§1.3）。
        clearSourceMediaId: state.sourceMediaId == mediaId,
        clearPreview: true,
        clearError: true,
      ),
    );
  }

  void setScope(CopyScope value) {
    if (state.scopeFixed || value == state.scope) return;
    emit(
      state.copyWith(
        scope: value,
        // 切换范围后必须重新创建选择快照。
        clearSelectionId: true,
        clearPreview: true,
        clearError: true,
      ),
    );
  }

  void setPairPolicy(PairPolicy value) => emit(
    state.copyWith(pairPolicy: value, clearPreview: true, clearError: true),
  );

  void setConflictStrategy(ConflictStrategy value) => emit(
    state.copyWith(conflictStrategy: value, clearError: true),
  );

  void setReviewExportEnabled(bool enabled) => emit(
    state.copyWith(
      reviewExport: enabled
          ? ReviewExportConfig(
              enabled: true,
              writeXmp: true,
              writeCsv: true,
              embedIntoSupportedCopy: state.reviewExport.embedIntoSupportedCopy,
            )
          : const ReviewExportConfig.disabled(),
      clearPreview: true,
      clearError: true,
    ),
  );

  void setEmbedReviewMetadata(bool enabled) => emit(
    state.copyWith(
      reviewExport: ReviewExportConfig(
        enabled: state.reviewExport.enabled,
        writeXmp: true,
        writeCsv: true,
        embedIntoSupportedCopy: enabled,
      ),
      clearPreview: true,
      clearError: true,
    ),
  );

  /// 获取预检（§10.1），返回是否成功。
  Future<bool> fetchPreview() async {
    if (isClosed || state.loadingPreview || state.submitting) return false;
    if (!state.canFetchPreview) return false;
    final generation = ++_loadGeneration;
    emit(state.copyWith(loadingPreview: true, clearError: true));
    try {
      final preview = await _repository.preview(state.draft);
      if (isClosed || generation != _loadGeneration) return false;
      emit(state.copyWith(loadingPreview: false, preview: preview));
      return true;
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return false;
      emit(state.copyWith(loadingPreview: false, error: error));
      return false;
    }
  }

  /// 提交前二次预检（§10.2：preview_token 未过期、空间仍足够），随后创建任务。
  Future<bool> submit() async {
    if (isClosed || state.submitting || state.submitted) return false;
    if (state.submissionBlockReason != null) return false;
    final generation = ++_loadGeneration;
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      // 容量与设备状态可能在用户停留期间变化：创建前必须用新预检验证。
      final refreshed = await _repository.preview(state.draft);
      if (isClosed || generation != _loadGeneration) return false;
      if (refreshed.isExpired || !refreshed.hasEnoughSpace) {
        emit(
          state.copyWith(
            submitting: false,
            preview: refreshed,
            error: StateError('目标设备已断开或剩余空间不足，请重新获取预检后再试。'),
          ),
        );
        return false;
      }
      final job = await _repository.createJob(state.draft, refreshed.previewToken);
      if (isClosed || generation != _loadGeneration) return false;
      final batch = state.batchId?.trim();
      if (batch != null && batch.isNotEmpty) {
        onRememberTarget?.call(batch, state.targetMediaId!);
      }
      dataChanges?.publish(
        {AppDataResource.jobs, AppDataResource.device, AppDataResource.batches},
        reason: 'copy_job_created',
      );
      emit(
        state.copyWith(
          submitting: false,
          submitted: true,
          createdJob: job,
          preview: refreshed,
        ),
      );
      return true;
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return false;
      emit(state.copyWith(submitting: false, error: error));
      return false;
    }
  }
}
