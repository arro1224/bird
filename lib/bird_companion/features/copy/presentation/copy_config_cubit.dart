import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_plan_integrity.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_device_policy.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CopyPreflightStatus { notRequested, loading, valid, invalidated, needsRecheck }

enum CopyPreflightInvalidation { sourceOffline, targetOffline, bindingChanged, configurationChanged, expired, planInconsistent, deviceDataStale, sessionUnavailable, targetUnavailable, targetOccupied, insufficientSpace, verificationFailed }

String copyPreflightMessage(CopyPreflightInvalidation reason) => switch (reason) {
  CopyPreflightInvalidation.sourceOffline => '相机卡已断开，请重新插入后重新预检。',
  CopyPreflightInvalidation.targetOffline => '目标 U 盘已断开，请重新插入或选择其他目标设备。',
  CopyPreflightInvalidation.bindingChanged => '源设备绑定已变化，请确认相机卡后重新预检。',
  CopyPreflightInvalidation.configurationChanged => '复制配置已修改，请重新预检。',
  CopyPreflightInvalidation.expired => '预检已过期，正在重新检查，请稍候。',
  CopyPreflightInvalidation.planInconsistent => '预检中的设备与当前选择不一致，请重新检测。',
  CopyPreflightInvalidation.deviceDataStale => '设备状态暂时无法确认，请检查盒子连接后重新检测；当前显示上次记录。',
  CopyPreflightInvalidation.sessionUnavailable => '盒子连接已变化，请恢复本次复制使用的盒子后重新检测。',
  CopyPreflightInvalidation.targetUnavailable => '目标设备当前不可写入或不可用，请检查或选择其他目标设备。',
  CopyPreflightInvalidation.targetOccupied => '设备正被进行中的复制任务占用，可查看当前任务；任务结束后设备自动恢复。',
  CopyPreflightInvalidation.insufficientSpace => '目标设备空间不足，请更换目标设备或减少复制范围。',
  CopyPreflightInvalidation.verificationFailed => '预检未通过，请重新检测后再开始复制。',
};

class CopyConfigState {
  const CopyConfigState({
    required this.scope,
    this.batchId,
    this.selectionId,
    this.selectionPhotoCount,
    this.selectionDiscardedCount,
    this.filter,
    this.preferredTargetMediaId,
    this.pairPolicy = PairPolicy.rawOnly,
    this.sourceMediaId,
    this.sourceBindingToken,
    this.sourceDisplayName,
    this.preferencesVersion,
    this.scopeOptions = const [],
    this.copyReady = false,
    this.reviewExportReady = true,
    this.targetMediaId,
    this.conflictStrategy,
    this.reviewExport = const ReviewExportConfig.disabled(),
    this.devices = const [],
    this.loadingDevices = true,
    this.devicesError,
    this.scopeUnavailable = false,
    this.preview,
    this.loadingPreview = false,
    this.submitting = false,
    this.checkingPlan = false,
    this.submitted = false,
    this.createdJob,
    this.error,
    this.persistenceNotice,
    this.devicesFresh = true,
    this.refreshingDevices = false,
    this.sessionAvailable = true,
    this.pageActive = true,
    this.sourceBindingExpiresAt,
    this.sourceVerifiedReadOnly = true,
    this.preflightPhase,
    this.invalidationReason,
    this.planIntegrity,
    this.planNotice,
  });

  final CopyScope scope;
  final String? batchId;
  final String? selectionId;
  final int? selectionPhotoCount;
  final int? selectionDiscardedCount;
  final Map<String, dynamic>? filter;
  final String? preferredTargetMediaId;
  final PairPolicy pairPolicy;
  final String? sourceMediaId;
  final String? sourceBindingToken;
  final String? sourceDisplayName;
  final int? preferencesVersion;
  final List<CopyScopeOption> scopeOptions;
  final bool copyReady;
  final bool reviewExportReady;
  final String? targetMediaId;
  final ConflictStrategy? conflictStrategy;
  final ReviewExportConfig reviewExport;
  final List<StorageDeviceSummary> devices;
  final bool loadingDevices;
  final Object? devicesError;

  /// 预检返回 COPY_SCOPE_UNSUPPORTED（当前盒子不支持该范围，如全量备份）：
  /// 页面渲染琥珀提示并禁止提交（01 文档 §二 P0-2）。
  final bool scopeUnavailable;
  final CopyPreview? preview;
  final bool loadingPreview;
  final bool submitting;
  final bool checkingPlan;
  final bool submitted;
  final CopyJobSummary? createdJob;
  final Object? error;
  final String? persistenceNotice;
  final bool devicesFresh, refreshingDevices, sessionAvailable, pageActive;
  final DateTime? sourceBindingExpiresAt;
  final bool sourceVerifiedReadOnly;
  final CopyPreflightStatus? preflightPhase;
  final CopyPreflightInvalidation? invalidationReason;
  final CopyPlanIntegrity? planIntegrity;
  final String? planNotice;
  CopyPreflightStatus get preflightStatus => preview?.isExpired == true
      ? CopyPreflightStatus.invalidated
      : preflightPhase ??
            (loadingPreview
                ? CopyPreflightStatus.loading
                : preview == null
                ? CopyPreflightStatus.notRequested
                : CopyPreflightStatus.valid);
  String? get preflightNotice => preflightStatus == CopyPreflightStatus.needsRecheck
      ? '设备已恢复，请重新预检后开始复制。'
      : invalidationReason == null
      ? null
      : copyPreflightMessage(invalidationReason!);

  bool get fullBackup => scope == CopyScope.mediaFullBackup;

  /// selected_assets 与全量备份的范围由入口固定，页面不展示范围列表（§3.3）。
  bool get scopeFixed => scope == CopyScope.selectedAssets || scope == CopyScope.mediaFullBackup;

  StorageDeviceSummary? get sourceDevice => _device(sourceMediaId);
  StorageDeviceSummary? get targetDevice => _device(targetMediaId);

  StorageDeviceSummary? _device(String? id) {
    if (id == null) return null;
    return devices.where((device) => device.mediaId == id).firstOrNull;
  }

  List<StorageDeviceSummary> get availableSources => devices.where((device) => device.online && device.canBeSource).toList(growable: false);

  List<StorageDeviceSummary> get targetCandidates => devices.where((device) => CopyDevicePolicy.isTargetCandidate(device, sourceMediaId)).toList(growable: false);
  List<StorageDeviceSummary> get availableTargets => devices.where((device) => CopyDevicePolicy.canSelectTarget(device, sourceMediaId)).toList(growable: false);

  CopyScopeOption? get currentScopeOption => scopeOptions.where((option) => option.scope == scope).firstOrNull;

  bool get canFetchPreview =>
      environmentBlockReason == null &&
      !loadingDevices &&
      devices.isNotEmpty &&
      copyReady &&
      sourceMediaId != null &&
      sourceBindingToken != null &&
      targetMediaId != null &&
      conflictStrategy != null &&
      (currentScopeOption?.available ?? false) &&
      (fullBackup || preferencesVersion != null) &&
      (scope != CopyScope.filteredAssets || filter != null) &&
      (scope != CopyScope.selectedAssets || selectionId != null);

  String? get environmentBlockReason {
    if (!sessionAvailable) return copyPreflightMessage(CopyPreflightInvalidation.sessionUnavailable);
    if (!pageActive) return '返回复制页面后请重新检测设备。';
    if (loadingDevices) return '正在读取设备状态，请稍候。';
    if (!devicesFresh) return copyPreflightMessage(invalidationReason ?? CopyPreflightInvalidation.deviceDataStale);
    final source = sourceDevice;
    if (source == null && sourceMediaId == null) return '请选择源设备';
    if (source == null || !source.online) return copyPreflightMessage(CopyPreflightInvalidation.sourceOffline);
    if (sourceOccupiedByJob) return copyPreflightMessage(CopyPreflightInvalidation.targetOccupied);
    if (!source.canBeSource || !sourceVerifiedReadOnly || sourceBindingToken == null || sourceBindingToken!.trim().isEmpty) return copyPreflightMessage(CopyPreflightInvalidation.bindingChanged);
    if (sourceBindingExpiresAt != null && !DateTime.now().isBefore(sourceBindingExpiresAt!)) return copyPreflightMessage(CopyPreflightInvalidation.expired);
    if (targetMediaId == null) return '请选择目标设备';
    if (targetMediaId == sourceMediaId) return '源设备与目标设备不能相同';
    final target = targetDevice;
    if (target == null || !target.online) return copyPreflightMessage(CopyPreflightInvalidation.targetOffline);
    if (targetOccupiedByJob) return copyPreflightMessage(CopyPreflightInvalidation.targetOccupied);
    if (!CopyDevicePolicy.canSelectTarget(target, sourceMediaId)) return CopyDevicePolicy.targetDisabledReason(target, sourceMediaId: sourceMediaId);
    return null;
  }

  /// v10 返修问题 6：源/目标设备被进行中的复制任务占用。占用不是断线，
  /// 不得显示"请检查与盒子的连接"或诱导用户反复检测设备；页面据此
  /// 显示占用文案与"查看当前任务"入口。
  ///
  /// `当前任务源设备` 是源卡的角色说明（rc3 源卡不能当目标），不是阻塞；
  /// 真正的占用信号是后端 targetBlockReasons 里的 `COPY_TARGET_BUSY`。
  bool get sourceOccupiedByJob => sourceDevice?.online == true && sourceDevice!.targetBlockReasons.contains('COPY_TARGET_BUSY');

  bool get targetOccupiedByJob => targetDevice?.online == true && targetDevice!.targetBlockReasons.contains('COPY_TARGET_BUSY');

  bool get occupiedByRunningJob => !loadingDevices && devicesFresh && (sourceOccupiedByJob || targetOccupiedByJob);

  String? get submissionBlockReason {
    if (scopeUnavailable) return '当前盒子不支持全量备份，本次不会创建任务';
    if (!(currentScopeOption?.available ?? false)) return '当前复制范围不可用';
    if (conflictStrategy == null) return '请选择同名文件处理策略';
    final environment = environmentBlockReason;
    if (environment != null) return environment;
    final previewValue = preview;
    if (previewValue == null) return preflightNotice ?? '请先获取预检';
    if (previewValue.isExpired) return '预检已过期，请重新获取';
    if (preflightStatus != CopyPreflightStatus.valid) return preflightNotice ?? '预检已失效，请重新获取';
    final integrity = planIntegrity;
    if (integrity?.verified != true || integrity?.token != previewValue.previewToken) return integrity?.message ?? '正在核对预检，请完成完整性校验后开始复制。';
    if (integrity!.blockedCount > 0) return '计划包含已阻止的文件，请处理问题后重新预检。';
    final problem = previewProblem(previewValue);
    if (problem != null) return copyPreflightMessage(problem);
    return null;
  }

  CopyPreflightInvalidation? previewProblem(CopyPreview value, {CopyRequestDraft? request}) {
    final sourceId = request?.sourceMediaId ?? sourceMediaId, targetId = request?.targetMediaId ?? targetMediaId;
    if (value.source.mediaId != sourceId || value.target.mediaId != targetId || value.previewToken.trim().isEmpty) return CopyPreflightInvalidation.planInconsistent;
    if (!value.source.online) return CopyPreflightInvalidation.sourceOffline;
    if (!value.source.canBeSource) return CopyPreflightInvalidation.bindingChanged;
    if (!CopyDevicePolicy.canSelectTarget(value.target, sourceId)) return value.target.online ? CopyPreflightInvalidation.targetUnavailable : CopyPreflightInvalidation.targetOffline;
    if (value.isExpired) return CopyPreflightInvalidation.expired;
    if (targetDevice == null || !targetDevice!.online) return CopyPreflightInvalidation.targetOffline;
    if (!value.hasEnoughSpace || targetDevice!.freeBytes < value.totalBytes + value.safetyReserveBytes) return CopyPreflightInvalidation.insufficientSpace;
    return null;
  }

  CopyRequestDraft get draft => CopyRequestDraft(
    batchId: batchId,
    scope: scope,
    selectionId: selectionId,
    sourceMediaId: sourceMediaId!,
    sourceBindingToken: sourceBindingToken,
    targetMediaId: targetMediaId!,
    expectedPreferencesVersion: preferencesVersion,
    filter: filter,
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
    Map<String, dynamic>? filter,
    String? preferredTargetMediaId,
    PairPolicy? pairPolicy,
    String? sourceMediaId,
    String? sourceBindingToken,
    String? sourceDisplayName,
    int? preferencesVersion,
    List<CopyScopeOption>? scopeOptions,
    bool? copyReady,
    bool? reviewExportReady,
    String? targetMediaId,
    ConflictStrategy? conflictStrategy,
    ReviewExportConfig? reviewExport,
    List<StorageDeviceSummary>? devices,
    bool? loadingDevices,
    Object? devicesError,
    bool clearDevicesError = false,
    bool? scopeUnavailable,
    bool clearScopeUnavailable = false,
    CopyPreview? preview,
    bool clearPreview = false,
    bool clearSourceMediaId = false,
    bool clearTargetMediaId = false,
    bool clearSelectionId = false,
    bool? loadingPreview,
    bool? submitting,
    bool? checkingPlan,
    bool? submitted,
    CopyJobSummary? createdJob,
    Object? error,
    bool clearError = false,
    String? persistenceNotice,
    bool? devicesFresh,
    bool? refreshingDevices,
    bool? sessionAvailable,
    bool? pageActive,
    DateTime? sourceBindingExpiresAt,
    bool? sourceVerifiedReadOnly,
    CopyPreflightStatus? preflightStatus,
    CopyPreflightInvalidation? invalidationReason,
    bool clearInvalidation = false,
    CopyPlanIntegrity? planIntegrity,
    String? planNotice,
    bool clearPlanNotice = false,
  }) => CopyConfigState(
    scope: scope ?? this.scope,
    batchId: batchId ?? this.batchId,
    selectionId: clearSelectionId ? null : selectionId ?? this.selectionId,
    selectionPhotoCount: clearSelectionId ? null : selectionPhotoCount ?? this.selectionPhotoCount,
    selectionDiscardedCount: clearSelectionId ? null : selectionDiscardedCount ?? this.selectionDiscardedCount,
    filter: filter ?? this.filter,
    preferredTargetMediaId: preferredTargetMediaId ?? this.preferredTargetMediaId,
    pairPolicy: pairPolicy ?? this.pairPolicy,
    sourceMediaId: clearSourceMediaId ? null : sourceMediaId ?? this.sourceMediaId,
    sourceBindingToken: sourceBindingToken ?? this.sourceBindingToken,
    sourceDisplayName: sourceDisplayName ?? this.sourceDisplayName,
    preferencesVersion: preferencesVersion ?? this.preferencesVersion,
    scopeOptions: scopeOptions ?? this.scopeOptions,
    copyReady: copyReady ?? this.copyReady,
    reviewExportReady: reviewExportReady ?? this.reviewExportReady,
    targetMediaId: clearTargetMediaId ? null : targetMediaId ?? this.targetMediaId,
    conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    reviewExport: reviewExport ?? this.reviewExport,
    devices: devices ?? this.devices,
    loadingDevices: loadingDevices ?? this.loadingDevices,
    devicesError: clearDevicesError ? null : devicesError ?? this.devicesError,
    scopeUnavailable: clearScopeUnavailable ? false : scopeUnavailable ?? this.scopeUnavailable,
    preview: clearPreview ? null : preview ?? this.preview,
    loadingPreview: loadingPreview ?? this.loadingPreview,
    submitting: submitting ?? this.submitting,
    checkingPlan: checkingPlan ?? this.checkingPlan,
    submitted: submitted ?? this.submitted,
    createdJob: createdJob ?? this.createdJob,
    error: clearError ? null : error ?? this.error,
    persistenceNotice: persistenceNotice ?? this.persistenceNotice,
    devicesFresh: devicesFresh ?? this.devicesFresh,
    refreshingDevices: refreshingDevices ?? this.refreshingDevices,
    sessionAvailable: sessionAvailable ?? this.sessionAvailable,
    pageActive: pageActive ?? this.pageActive,
    sourceBindingExpiresAt: sourceBindingExpiresAt ?? this.sourceBindingExpiresAt,
    sourceVerifiedReadOnly: sourceVerifiedReadOnly ?? this.sourceVerifiedReadOnly,
    preflightPhase: preflightStatus ?? preflightPhase,
    invalidationReason: clearInvalidation ? null : invalidationReason ?? this.invalidationReason,
    planIntegrity: clearPreview ? null : planIntegrity ?? this.planIntegrity,
    planNotice: clearPreview || clearPlanNotice ? null : planNotice ?? this.planNotice,
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
    this.filter,
    this.preferredTargetMediaId,
    this.onRememberTarget,
    this.onJobCreated,
    this.canUseDevice,
    this.dataChanges,
    this.sessionChanges,
    this.refreshSignals,
    this.diagnostic,
    this.planRepository,
    this.planVerifier = const CopyPlanVerifier(),
    this.pollInterval = const Duration(seconds: 5),
    this.initialPairPolicy = PairPolicy.rawOnly,
    this.initialReviewExportEnabled = false,
    this.initialEmbedReviewMetadata = true,
  }) : super(
         CopyConfigState(
           scope: scope,
           batchId: batchId,
           selectionId: selectionId,
           selectionPhotoCount: selectionPhotoCount,
           selectionDiscardedCount: selectionDiscardedCount,
           filter: filter,
           preferredTargetMediaId: preferredTargetMediaId,
           pairPolicy: initialPairPolicy,
           sessionAvailable: canUseDevice?.call() ?? true,
           reviewExport: ReviewExportConfig(enabled: initialReviewExportEnabled, writeXmp: true, writeCsv: true, embedIntoSupportedCopy: initialEmbedReviewMetadata),
         ),
       ) {
    _sessionSubscription = sessionChanges?.listen((_) => sessionChanged());
    _refreshSubscription = refreshSignals?.listen((_) => _requestRefresh());
    _dataSubscription = dataChanges?.changes.listen((change) {
      if (change.affects(AppDataResource.copyPreferences)) _change(state);
      // v10 问题 5：任务终态会释放设备占用，配置页必须重新拉设备可用性。
      if (change.affects(AppDataResource.device) || change.affects(AppDataResource.jobs)) _requestRefresh();
    });
  }

  final CopyRepository _repository;
  final CopyJobRepository? planRepository;
  final CopyPlanVerifier planVerifier;

  Future<CopyPlanIntegrity> _verifyPlan(CopyPreview preview, bool Function() current) => planVerifier.verify(
    preview,
    planRepository ?? (_repository is CopyJobRepository ? _repository as CopyJobRepository : null),
    isCurrent: current,
  );

  void cancelPlanVerification() {
    if (_creating || (!state.loadingPreview && !state.submitting)) return;
    ++_operation;
    _invalidate(CopyPreflightInvalidation.verificationFailed);
  }

  final String? batchId, selectionId;
  final CopyScope scope;
  final int? selectionPhotoCount, selectionDiscardedCount;
  final Map<String, dynamic>? filter;
  final String? preferredTargetMediaId;
  final FutureOr<void> Function(String batchId, String mediaId)? onRememberTarget;
  final Future<void> Function(CopyJobSummary job)? onJobCreated;
  final bool Function()? canUseDevice;
  final AppDataChangeBus? dataChanges;
  final Stream<void>? sessionChanges, refreshSignals;
  final void Function(Map<String, dynamic>)? diagnostic;
  final Duration pollInterval;
  final PairPolicy initialPairPolicy;
  final bool initialReviewExportEnabled, initialEmbedReviewMetadata;
  StreamSubscription<void>? _sessionSubscription, _refreshSubscription;
  StreamSubscription<AppDataChange>? _dataSubscription;
  Timer? _poll, _expiry;
  Future<bool>? _refreshing;
  Future<void>? _resumeRefresh;
  bool _refreshingRenewsBinding = false;
  Future<void>? _initializing;
  int _environment = 0, _configuration = 0, _contextVersion = 0, _operation = 0;
  bool _initialized = false, _creating = false, _created = false;
  PairPolicy? _persistedPairPolicy;
  bool _planReconfirmationRequired = false;

  bool get _usable => !isClosed && (canUseDevice?.call() ?? true);
  bool _current(int environment, int configuration, int operation) {
    if (!_usable) sessionChanged();
    return _usable && state.pageActive && environment == _environment && configuration == _configuration && operation == _operation;
  }

  bool _sameEnvironment(int environment) {
    if (!_usable) sessionChanged();
    return _usable && environment == _environment;
  }

  void _invalidate(CopyPreflightInvalidation reason, {CopyConfigState? next}) {
    if (isClosed || state.submitted) return;
    ++_contextVersion;
    _planReconfirmationRequired = false;
    _expiry?.cancel();
    _trace('copy_preflight_invalidated', reason: reason);
    emit((next ?? state).copyWith(clearPreview: true, loadingPreview: false, checkingPlan: false, submitting: _creating ? null : false, preflightStatus: CopyPreflightStatus.invalidated, invalidationReason: reason));
  }

  void _trace(String event, {CopyPreflightInvalidation? reason, Object? error}) {
    try {
      diagnostic?.call({
        'event': event,
        'phase': 'copy_preflight',
        'generation': _environment,
        if (reason != null) 'classification': reason.name,
        if (error != null) 'error_class': error.runtimeType.toString(),
        if (error is ApiException) 'error_code': error.code,
        if (error is ApiException) 'http_status': error.statusCode,
      });
    } catch (_) {
      /* Diagnostics do not decide whether copying is allowed. */
    }
  }

  void sessionChanged() {
    if (isClosed) return;
    final available = _usable;
    if (state.sessionAvailable == available) return;
    ++_environment;
    ++_operation;
    _refreshing = null;
    _initializing = null;
    _invalidate(
      CopyPreflightInvalidation.sessionUnavailable,
      next: state.copyWith(sessionAvailable: available, devicesFresh: false, refreshingDevices: false, loadingDevices: false, error: available ? null : StateError('盒子连接已变化，请重新检测。')),
    );
    if (available && state.pageActive) unawaited(refreshDevices());
  }

  void setPageActive(bool active) {
    if (isClosed || state.pageActive == active) return;
    _poll?.cancel();
    if (!active) {
      ++_environment;
      ++_operation;
      _refreshing = null;
      _initializing = null;
      _invalidate(CopyPreflightInvalidation.deviceDataStale, next: state.copyWith(pageActive: false, loadingDevices: false, devicesFresh: false, refreshingDevices: false));
    } else {
      emit(state.copyWith(pageActive: true));
      _startPolling();
      if (_usable) unawaited(refreshDevices());
    }
  }

  /// v10 返修问题 3：App 生命周期离开（截图/通知栏/锁屏/短暂切后台）不再
  /// 立即销毁有效预检。暂停只停轮询；回前台静默刷新设备，源/目标身份、
  /// 参数与预检令牌未变化时恢复原确认页，只有设备或清单真实变化才失效。
  ///
  /// 不透明路由压栈（预览明细 sheet、其他页面）仍走 [setPageActive]：
  /// 遮挡期间预检必须失效，那是另一条已冻结语义。
  void setAppLifecycleActive(bool active) {
    if (isClosed || state.submitted) return;
    if (!active) {
      _poll?.cancel();
      ++_operation;
      _refreshing = null;
      if (state.pageActive) {
        emit(state.copyWith(devicesFresh: false, refreshingDevices: false, loadingDevices: false));
      }
      return;
    }
    emit(state.copyWith(clearError: true));
    if (state.pageActive && _usable) {
      _startPolling();
      // v10 问题 3：回前台先静默重试设备读取并留短宽限期——单次 transient
      // 失败不得立刻销毁有效预检；连续失败才按设备数据不可用失效。
      if (_resumeRefresh == null) {
        final future = _refreshAfterResume();
        _resumeRefresh = future;
        unawaited(
          future.whenComplete(() {
            if (identical(_resumeRefresh, future)) _resumeRefresh = null;
          }),
        );
      }
    }
  }

  Future<void> _refreshAfterResume() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (isClosed || !state.pageActive || !_usable) return;
      if (await refreshDevices(invalidateOnFailure: false)) return;
      if (isClosed || !state.pageActive) return;
      if (attempt < 2) await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!isClosed && state.pageActive && state.preview != null) {
      _invalidate(state.invalidationReason ?? CopyPreflightInvalidation.deviceDataStale);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (!isClosed && _initialized && state.pageActive && !state.submitted && pollInterval > Duration.zero) {
      _poll = Timer.periodic(pollInterval, (_) => _requestRefresh());
    }
  }

  void _requestRefresh() {
    if (_initialized && !isClosed && state.pageActive && !state.submitted && _usable) unawaited(refreshDevices());
  }

  Future<void> initialize() {
    if (_initializing != null) return _initializing!;
    final future = _initialize();
    _initializing = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_initializing, future)) _initializing = null;
      }),
    );
    return future;
  }

  Future<void> _initialize() async {
    if (isClosed || state.submitting) return;
    final environment = _environment;
    if (!_usable) {
      _invalidate(CopyPreflightInvalidation.sessionUnavailable, next: state.copyWith(sessionAvailable: false, loadingDevices: false, devicesFresh: false));
      return;
    }
    emit(state.copyWith(loadingDevices: true, clearDevicesError: true));
    try {
      final capabilities = await _repository.capabilities();
      if (!_sameEnvironment(environment)) return;
      if (!capabilities.copyReady || capabilities.revision != '1.0-rc3') throw StateError('盒子复制能力尚未就绪。');
      final results = await Future.wait<Object>([
        _repository.devices(),
        _repository.source(batchId: batchId),
        if (scope != CopyScope.mediaFullBackup) _repository.preferences(),
        _repository.scopeOptions(batchId: batchId, selectionId: selectionId, filter: filter),
      ], eagerError: true);
      if (!_sameEnvironment(environment)) return;
      final devices = (results[0] as CopyDeviceList).devices;
      final binding = results[1] as SourceBinding;
      final preferences = scope == CopyScope.mediaFullBackup ? null : results[2] as CopyPreferences;
      final target = devices.where((d) => d.mediaId == preferredTargetMediaId && CopyDevicePolicy.canSelectTarget(d, binding.sourceMediaId)).firstOrNull;
      _initialized = true;
      _persistedPairPolicy = preferences?.pairPolicy;
      emit(
        state.copyWith(
          devices: devices,
          loadingDevices: false,
          devicesFresh: true,
          sessionAvailable: true,
          clearDevicesError: true,
          clearError: true,
          copyReady: true,
          reviewExportReady: capabilities.reviewExportReady,
          reviewExport: capabilities.reviewExportReady ? state.reviewExport : const ReviewExportConfig.disabled(),
          sourceMediaId: binding.sourceMediaId,
          sourceBindingToken: binding.token,
          sourceDisplayName: binding.displayName,
          sourceBindingExpiresAt: binding.expiresAt,
          sourceVerifiedReadOnly: binding.verifiedReadOnly,
          preferencesVersion: preferences?.version,
          pairPolicy: preferences?.pairPolicy,
          scopeOptions: results.last as List<CopyScopeOption>,
          targetMediaId: target?.mediaId,
          clearTargetMediaId: target == null,
          clearPreview: true,
          clearInvalidation: true,
          preflightStatus: CopyPreflightStatus.notRequested,
        ),
      );
      _startPolling();
    } catch (error) {
      if (isClosed || environment != _environment) return;
      _trace('copy_initialization_failed', error: error);
      emit(state.copyWith(loadingDevices: false, devicesFresh: false, devicesError: error));
      _invalidate(_reasonFor(error) ?? CopyPreflightInvalidation.deviceDataStale);
    }
  }

  /// Devices and source are one authoritative snapshot. Failed reads retain
  /// the last list as stale data, never invent a physical unplug event.
  Future<bool> refreshDevices({bool renewSourceBinding = false, bool invalidateOnFailure = true}) {
    if (isClosed || state.submitted || !state.pageActive) return Future.value(false);
    if (!_usable) {
      sessionChanged();
      return Future.value(false);
    }
    if (!_initialized) return initialize().then((_) => _initialized && state.devicesFresh);
    if (_refreshing != null) {
      if (renewSourceBinding && !_refreshingRenewsBinding) return _renewAfterRefresh(_refreshing!);
      return _refreshing!;
    }
    final environment = _environment;
    _refreshingRenewsBinding = renewSourceBinding;
    final future = _readDevices(environment, renewSourceBinding: renewSourceBinding, invalidateOnFailure: invalidateOnFailure);
    _refreshing = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_refreshing, future)) _refreshing = null;
      }),
    );
    return future;
  }

  Future<bool> _renewAfterRefresh(Future<bool> existing) async {
    await existing;
    if (identical(_refreshing, existing)) _refreshing = null;
    return refreshDevices(renewSourceBinding: true);
  }

  Future<bool> _readDevices(int environment, {required bool renewSourceBinding, bool invalidateOnFailure = true}) async {
    emit(state.copyWith(refreshingDevices: true));
    try {
      final configuration = _configuration;
      final readPreferences = !state.fullBackup;
      final results = await Future.wait<Object>([_repository.devices(), _repository.source(batchId: state.batchId), if (readPreferences) _repository.preferences()], eagerError: true);
      if (!_sameEnvironment(environment)) return false;
      final binding = results[1] as SourceBinding;
      // GET may issue a new opaque token. Keep the unexpired token paired with
      // the confirmed preview when identity/read-only proof still match.
      // Explicit preflight renews it; the server revalidates the frozen binding.
      final keepBinding =
          !renewSourceBinding &&
          state.sourceMediaId == binding.sourceMediaId &&
          state.sourceBindingToken != null &&
          state.sourceVerifiedReadOnly &&
          binding.verifiedReadOnly &&
          state.sourceBindingExpiresAt != null &&
          DateTime.now().isBefore(state.sourceBindingExpiresAt!);
      final preferences = readPreferences && configuration == _configuration ? results[2] as CopyPreferences : null;
      // v10 问题 7：用户在本页的草稿选择优先于服务端旧偏好——刷新不得把
      // 尚未持久化的草稿值覆盖回服务端值；只吸收版本号更高的服务端变化。
      final hasDraftChoice = _persistedPairPolicy != null && state.pairPolicy != _persistedPairPolicy;
      final changedPreferences = preferences != null && preferences.version >= (state.preferencesVersion ?? 0) && (preferences.version != state.preferencesVersion || (!hasDraftChoice && preferences.pairPolicy != state.pairPolicy));
      final adoptPreferences = changedPreferences && !hasDraftChoice;
      // 服务端版本被采纳后要把“已持久化值”一起推进，否则下次创建会误以为
      // 草稿未保存而重复写一次偏好（v10 问题 7 的收尾）。
      if (adoptPreferences) _persistedPairPolicy = preferences.pairPolicy;
      final next = state.copyWith(
        devices: (results[0] as CopyDeviceList).devices,
        sourceMediaId: binding.sourceMediaId,
        sourceBindingToken: keepBinding ? state.sourceBindingToken : binding.token,
        sourceDisplayName: binding.displayName,
        sourceBindingExpiresAt: keepBinding ? state.sourceBindingExpiresAt : binding.expiresAt,
        sourceVerifiedReadOnly: binding.verifiedReadOnly,
        loadingDevices: false,
        devicesFresh: true,
        refreshingDevices: false,
        clearDevicesError: true,
        preferencesVersion: changedPreferences ? preferences.version : null,
        pairPolicy: adoptPreferences ? preferences.pairPolicy : null,
      );
      final reason =
          _snapshotProblem(next) ??
          (state.sourceMediaId != next.sourceMediaId || state.sourceBindingToken != next.sourceBindingToken
              ? CopyPreflightInvalidation.bindingChanged
              : changedPreferences
              ? CopyPreflightInvalidation.configurationChanged
              : null);
      if (reason != null) {
        _invalidate(reason, next: next);
      } else if (state.invalidationReason != null &&
          state.invalidationReason != CopyPreflightInvalidation.configurationChanged &&
          state.invalidationReason != CopyPreflightInvalidation.planInconsistent &&
          state.invalidationReason != CopyPreflightInvalidation.verificationFailed &&
          state.preview == null) {
        emit(next.copyWith(clearPreview: true, clearError: true, preflightStatus: CopyPreflightStatus.needsRecheck));
      } else {
        // v10 问题 3：刷新成功且无问题时恢复原确认页——清除陈旧标记，
        // 让确认页在生命周期往返后仍持有原预检（令牌 120s 内仍有效）。
        emit(next.copyWith(clearError: true, clearInvalidation: true));
      }
      return true;
    } catch (error) {
      if (isClosed || environment != _environment) return false;
      _trace('copy_device_refresh_failed', error: error);
      final failure = state.copyWith(refreshingDevices: false, devicesFresh: false, devicesError: error);
      if (invalidateOnFailure) {
        _invalidate(_reasonFor(error) ?? CopyPreflightInvalidation.deviceDataStale, next: failure);
      } else {
        // 回前台的宽限期内只标记“设备数据不新鲜”，保留有效预检等待重试；
        // 同时保留错误分类，连续失败后仍能显示“哪块盘断开/占用”而非泛化提示。
        emit(failure.copyWith(invalidationReason: _reasonFor(error)));
      }
      return false;
    }
  }

  CopyPreflightInvalidation? _snapshotProblem(CopyConfigState value) {
    final source = value.sourceDevice, target = value.targetDevice;
    if (source == null || !source.online) return CopyPreflightInvalidation.sourceOffline;
    if (value.sourceOccupiedByJob) return CopyPreflightInvalidation.targetOccupied;
    if (!source.canBeSource || !value.sourceVerifiedReadOnly) return CopyPreflightInvalidation.bindingChanged;
    if (value.sourceBindingExpiresAt != null && !DateTime.now().isBefore(value.sourceBindingExpiresAt!)) return CopyPreflightInvalidation.expired;
    if (value.targetMediaId == null) return null;
    if (target == null || !target.online) return CopyPreflightInvalidation.targetOffline;
    if (value.targetOccupiedByJob) return CopyPreflightInvalidation.targetOccupied;
    if (!CopyDevicePolicy.canSelectTarget(target, value.sourceMediaId)) return CopyPreflightInvalidation.targetUnavailable;
    final preview = value.preview;
    if (preview != null && target.freeBytes < preview.totalBytes + preview.safetyReserveBytes) return CopyPreflightInvalidation.insufficientSpace;
    return null;
  }

  static CopyPreflightInvalidation? _reasonFor(Object error) => error is! ApiException
      ? null
      : switch (error.code) {
          'COPY_SOURCE_NOT_PRESENT' => CopyPreflightInvalidation.sourceOffline,
          'COPY_TARGET_NOT_PRESENT' => CopyPreflightInvalidation.targetOffline,
          'COPY_MEDIA_ID_CHANGED' || 'COPY_SOURCE_CHANGED' => CopyPreflightInvalidation.bindingChanged,
          'COPY_PREVIEW_EXPIRED' => CopyPreflightInvalidation.expired,
          'COPY_TARGET_BUSY' => CopyPreflightInvalidation.targetOccupied,
          'COPY_TARGET_READ_ONLY' || 'COPY_UNSUPPORTED_FILESYSTEM' => CopyPreflightInvalidation.targetUnavailable,
          'COPY_INSUFFICIENT_SPACE' => CopyPreflightInvalidation.insufficientSpace,
          _ => null,
        };

  void selectSource(String mediaId) {
    /* rc3 source is server-bound. */
  }

  void _change(CopyConfigState next) {
    if (isClosed || _creating || state.submitted) return;
    ++_configuration;
    ++_operation;
    if (state.preflightStatus == CopyPreflightStatus.notRequested && state.preview == null) {
      ++_contextVersion;
      emit(next.copyWith(clearError: true, clearInvalidation: true, clearPreview: true, preflightStatus: CopyPreflightStatus.notRequested));
    } else {
      _invalidate(CopyPreflightInvalidation.configurationChanged, next: next.copyWith(clearError: true));
    }
  }

  void selectTarget(String mediaId) {
    final device = state._device(mediaId);
    if (device == null || !CopyDevicePolicy.canSelectTarget(device, state.sourceMediaId) || mediaId == state.targetMediaId) return;
    _change(state.copyWith(targetMediaId: mediaId));
  }

  void setScope(CopyScope value) {
    if (!state.scopeFixed && value != state.scope) _change(state.copyWith(scope: value, clearScopeUnavailable: true));
  }

  void setPairPolicy(PairPolicy value) {
    // v10 返修问题 7：页面选择只属于当前草稿，不在此处写持久偏好；
    // 服务端偏好仅在任务创建成功后原子保存（见 _persistPairPolicyAfterCreate）。
    if (isClosed || _creating || state.submitted || value == state.pairPolicy || state.fullBackup || !_usable) return;
    _change(state.copyWith(pairPolicy: value));
  }

  void setConflictStrategy(ConflictStrategy value) {
    if (state.conflictStrategy != value) _change(state.copyWith(conflictStrategy: value));
  }

  void setReviewExportEnabled(bool enabled) => _change(
    state.copyWith(
      reviewExport: enabled && state.reviewExportReady ? ReviewExportConfig(enabled: true, writeXmp: true, writeCsv: true, embedIntoSupportedCopy: state.reviewExport.embedIntoSupportedCopy) : const ReviewExportConfig.disabled(),
    ),
  );
  void setEmbedReviewMetadata(bool enabled) => _change(
    state.copyWith(
      reviewExport: ReviewExportConfig(enabled: state.reviewExport.enabled, writeXmp: true, writeCsv: true, embedIntoSupportedCopy: enabled),
    ),
  );

  void _armExpiry(CopyPreview preview) {
    _expiry?.cancel();
    var expires = preview.expiresAt;
    final binding = state.sourceBindingExpiresAt;
    if (binding != null && binding.isBefore(expires)) expires = binding;
    final delay = expires.difference(DateTime.now());
    _expiry = Timer(delay.isNegative ? Duration.zero : delay, _onPreviewExpired);
  }

  /// v10 返修问题 10：预检过期不再要求用户手动重检。过期即失效令牌，
  /// 页面显示"预检已过期，正在重新检查"；若页面仍活跃且环境未变，自动
  /// 重新预检并展示最新摘要。重大变化（计划/冲突/空间/身份）通过对比
  /// 过期前签名拦截一次提交，见 [_recheckAfterExpiry]。
  void _onPreviewExpired() {
    if (isClosed || state.submitted || state.submitting) return;
    final previousSignature = state.planIntegrity?.signature;
    _invalidate(CopyPreflightInvalidation.expired);
    if (state.pageActive && _usable) unawaited(_recheckAfterExpiry(previousSignature));
  }

  /// 过期自动重检后，若计划、冲突、空间或源/目标身份等签名发生变化，
  /// 不能把新计划当成用户已确认的计划直接创建：先阻断一次并提示核对。
  Future<void> _recheckAfterExpiry(String? previousSignature) async {
    final ok = await fetchPreview();
    if (!ok || isClosed || state.submitted || previousSignature == null) return;
    final currentSignature = state.planIntegrity?.signature;
    if (currentSignature == null || currentSignature == previousSignature) return;
    _planReconfirmationRequired = true;
    emit(state.copyWith(planNotice: '预检已过期并已重新检查，计划内容有变化，请核对最新明细后再次点击开始复制确认。'));
  }

  CopyPreflightInvalidation? _previewProblem(CopyPreview preview, CopyRequestDraft draft) {
    return state.previewProblem(preview, request: draft);
  }

  Future<bool> fetchPreview() async {
    if (isClosed || state.loadingPreview || state.submitting || state.submitted || !_usable || !state.pageActive) return false;
    final environment = _environment, configuration = _configuration, operation = ++_operation;
    _expiry?.cancel();
    emit(state.copyWith(loadingPreview: true, clearPreview: true, preflightStatus: CopyPreflightStatus.loading, clearError: true, clearScopeUnavailable: true));
    try {
      if (!await refreshDevices(renewSourceBinding: true) || !_current(environment, configuration, operation) || !state.canFetchPreview) return false;
      final version = _contextVersion, draft = state.draft;
      emit(state.copyWith(loadingPreview: true, preflightStatus: CopyPreflightStatus.loading));
      final preview = await _repository.preview(draft);
      if (!_current(environment, configuration, operation) || version != _contextVersion) return false;
      final problem = _previewProblem(preview, draft);
      if (problem != null) {
        _invalidate(problem);
        return false;
      }
      emit(
        state.copyWith(
          preview: preview,
          planIntegrity: CopyPlanIntegrity(CopyPlanIntegrityStatus.pending, token: preview.previewToken),
        ),
      );
      final integrity = await _verifyPlan(preview, () => _current(environment, configuration, operation) && version == _contextVersion);
      if (!_current(environment, configuration, operation) || version != _contextVersion) return false;
      _planReconfirmationRequired = false;
      emit(state.copyWith(loadingPreview: false, preview: preview, planIntegrity: integrity, clearInvalidation: true, preflightStatus: CopyPreflightStatus.valid));
      _armExpiry(preview);
      return integrity.verified;
    } catch (error) {
      if (!_current(environment, configuration, operation)) return false;
      _fail(error);
      return false;
    } finally {
      if (!isClosed && operation == _operation && state.loadingPreview) {
        emit(state.copyWith(loadingPreview: false, preflightStatus: state.preflightStatus == CopyPreflightStatus.loading ? (state.invalidationReason == null ? CopyPreflightStatus.notRequested : CopyPreflightStatus.invalidated) : null));
      }
    }
  }

  void _fail(Object error) {
    _trace('copy_preflight_failed', error: error);
    _invalidate(
      _reasonFor(error) ?? CopyPreflightInvalidation.verificationFailed,
      next: state.copyWith(error: error, scopeUnavailable: error is ApiException && error.code == 'COPY_SCOPE_UNSUPPORTED' ? true : null),
    );
  }

  /// v10 返修问题 7：偏好只在任务创建成功后原子保存。保存失败不改变已成功的
  /// 创建结果——偏好是便利设置，不是任务契约的一部分；页面上的草稿选择保留。
  Future<void> _persistPairPolicyAfterCreate() async {
    if (isClosed || state.fullBackup) return;
    final value = state.pairPolicy;
    if (value == _persistedPairPolicy) return;
    final expectedVersion = state.preferencesVersion;
    if (expectedVersion == null) return;
    try {
      final saved = await _repository.savePreferences(value, expectedVersion: expectedVersion);
      if (isClosed) return;
      _persistedPairPolicy = saved.pairPolicy;
      emit(state.copyWith(preferencesVersion: saved.version));
    } catch (_) {
      // 偏好保存失败不影响任务创建；下次创建成功后仍会尝试保存最新选择。
    }
  }

  /// Bind one immutable draft to fresh devices and the second preflight. Every
  /// asynchronous boundary before POST rejects changed session/configuration.
  Future<bool> submit() async {
    if (isClosed || state.submitting || state.submitted || _creating || _created || state.submissionBlockReason != null) return false;
    if (_planReconfirmationRequired) {
      _planReconfirmationRequired = false;
      emit(state.copyWith(planNotice: '计划已变化，请核对最新明细后再次点击开始复制确认。'));
      return false;
    }
    final environment = _environment, configuration = _configuration, operation = ++_operation, version = _contextVersion;
    emit(state.copyWith(submitting: true, checkingPlan: true, clearError: true));
    final confirmed = state.planIntegrity!;
    var sent = false;
    try {
      if (!await refreshDevices() || !_current(environment, configuration, operation) || version != _contextVersion || state.submissionBlockReason != null) return false;
      final draft = state.draft;
      final refreshed = await _repository.preview(draft);
      if (!_current(environment, configuration, operation) || version != _contextVersion) return false;
      final problem = _previewProblem(refreshed, draft);
      if (problem != null) {
        _invalidate(problem);
        return false;
      }
      final integrity = await _verifyPlan(refreshed, () => _current(environment, configuration, operation) && version == _contextVersion);
      if (!_current(environment, configuration, operation) || version != _contextVersion) return false;
      if (!integrity.verified) {
        emit(state.copyWith(preview: refreshed, planIntegrity: integrity, preflightStatus: CopyPreflightStatus.valid));
        _armExpiry(refreshed);
        return false;
      }
      // Re-read after a slow preflight, including source binding. A concurrent
      // refresh shares the request; it cannot authorize a different draft.
      if (!await refreshDevices() || !_current(environment, configuration, operation) || version != _contextVersion) return false;
      emit(state.copyWith(preview: refreshed, planIntegrity: integrity, preflightStatus: CopyPreflightStatus.valid, clearInvalidation: true, clearPlanNotice: true));
      _armExpiry(refreshed);
      if (confirmed.signature != integrity.signature) {
        emit(state.copyWith(planNotice: '预检计划已变化，请核对更新后的明细，再次点击开始复制确认。'));
        return false;
      }
      if (state.submissionBlockReason != null) return false;
      _creating = true;
      emit(state.copyWith(checkingPlan: false));
      sent = true;
      final job = await _repository.createJob(draft, refreshed.previewToken);
      _created = true;
      String? persistenceNotice;
      try {
        await onJobCreated?.call(job);
      } catch (_) {
        persistenceNotice = '任务已创建，但本机恢复记录保存失败。可从复制任务列表查看。';
      }
      if (isClosed) return false;
      final batch = draft.batchId?.trim();
      if (batch != null && batch.isNotEmpty) {
        try {
          await onRememberTarget?.call(batch, draft.targetMediaId);
        } catch (_) {
          /* A convenience preference cannot invalidate POST success. */
        }
      }
      await _persistPairPolicyAfterCreate();
      dataChanges?.publish({AppDataResource.jobs, AppDataResource.device, AppDataResource.batches}, reason: 'copy_job_created');
      _poll?.cancel();
      _expiry?.cancel();
      emit(state.copyWith(submitting: false, submitted: true, createdJob: job, preview: refreshed, preflightStatus: CopyPreflightStatus.valid, clearError: true, clearInvalidation: true, persistenceNotice: persistenceNotice));
      return true;
    } catch (error) {
      if (!isClosed && environment == _environment) _fail(error);
      return false;
    } finally {
      if (sent) _creating = false;
      if (!isClosed && (operation == _operation || sent) && state.submitting) emit(state.copyWith(submitting: false, checkingPlan: false));
    }
  }

  @override
  Future<void> close() async {
    ++_environment;
    ++_operation;
    _poll?.cancel();
    _expiry?.cancel();
    await _sessionSubscription?.cancel();
    await _refreshSubscription?.cancel();
    await _dataSubscription?.cancel();
    return super.close();
  }
}
