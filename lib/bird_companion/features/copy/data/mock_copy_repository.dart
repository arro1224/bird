import 'dart:math';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

/// 协议字段 mock 实现（迁移对照文档 §7）。
///
/// 后端交付 birdbox-copy-v1 前，[useMockCopyRepository] 为 true 时使用本实现。
/// 所有字段与语义均为主协议字段，不创造临时枚举；设备数据取自协议 §22
/// 已实机验证记录。联调时将开关置为 false 即可切换真实接口。
const useMockCopyRepository = false;

/// RC3 任务闭环 mock：
/// - 状态机用**惰性时间推进**（注入 [clock]，所有读写在调用时按相对时间
///   推进），不用 Timer——测试用可变 clock 做确定性断言，详情页 2s 轮询
///   自然驱动进度；
/// - [fullBackupAvailable] 镜像真实后端 `copy-capabilities`：默认 false 时
///   全量备份预检返回 COPY_SCOPE_UNSUPPORTED（联调问题 01 §二 P0-2）。
class MockCopyRepository implements CopyRepository, CopyJobRepository {
  MockCopyRepository({DateTime Function()? clock, this.fullBackupAvailable = false})
    : _now = clock ?? DateTime.now;

  /// 惰性推进用的时间源。
  final DateTime Function() _now;

  /// false 时镜像真实后端：copy-capabilities 不含 media_full_backup，
  /// 全量备份预检 COPY_SCOPE_UNSUPPORTED。
  final bool fullBackupAvailable;

  final Random _random = Random();
  final Map<String, String> _aliases = {};
  final Set<String> _createdSelections = {};
  final Map<String, _MockCopyJob> _jobs = {};
  final Map<String, List<CopyJobItem>> _previewItems = {};
  final Set<String> _safeRemovedDevices = {};

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [
      CopyScope.selectedAssets,
      CopyScope.filteredAssets,
      CopyScope.recognizedAssets,
      CopyScope.batchAllAssets,
      CopyScope.mediaFullBackup,
    ],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );

  @override
  Future<SourceBinding> source({String? batchId}) async => SourceBinding(
    sourceMediaId: _cameraCard.mediaId,
    displayName: _cameraCard.displayName,
    token: 'src_mock_binding',
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    verifiedReadOnly: true,
    batchId: batchId,
  );

  @override
  Future<CopyPreferences> preferences() async => const CopyPreferences(
    pairPolicy: PairPolicy.rawOnly,
    version: 1,
    origin: 'factory_default',
  );

  @override
  Future<CopyPreferences> savePreferences(
    PairPolicy pairPolicy, {
    required int expectedVersion,
  }) async => CopyPreferences(
    pairPolicy: pairPolicy,
    version: expectedVersion + 1,
    origin: 'user_saved',
  );

  @override
  Future<List<CopyScopeOption>> scopeOptions({
    String? batchId,
    String? selectionId,
    Map<String, dynamic>? filter,
  }) async => [
    for (final scope in const [
      CopyScope.selectedAssets,
      CopyScope.filteredAssets,
      CopyScope.recognizedAssets,
      CopyScope.batchAllAssets,
      CopyScope.mediaFullBackup,
    ])
      CopyScopeOption(
        scope: scope,
        available: scope == CopyScope.mediaFullBackup || batchId != null,
        logicalAssets: scope == CopyScope.mediaFullBackup ? null : 34,
        countState: scope == CopyScope.mediaFullBackup ? 'requires_preview' : 'known',
        navigationAction: 'none',
      ),
  ];

  static const _cameraCard = StorageDeviceSummary(
    mediaId: 'media_2d6dee77bb5ecc73e3d34787',
    displayName: '相机卡（读卡器）',
    kind: 'card_reader',
    kindConfidence: 'high',
    detail: '双逻辑槽位读卡器 · 119.2 GB · EXFAT',
    capacityBytes: 128000000000,
    freeBytes: 96400000000,
    filesystem: 'exfat',
    label: '',
    roleState: 'available',
    canBeSource: true,
    canBeTarget: false,
    targetBlockReasons: ['当前任务源设备'],
    identityConfidence: 'stable_uuid',
  );

  static const _usbStick = StorageDeviceSummary(
    mediaId: 'media_7f9a76e6c97690b61aedf6fd',
    displayName: 'U 盘 Ee',
    kind: 'usb_flash',
    kindConfidence: 'medium',
    detail: 'SanDisk Ultra USB 3.0 · 28.7 GB · EXFAT',
    capacityBytes: 30765203456,
    freeBytes: 30500000000,
    filesystem: 'exfat',
    label: 'Ee',
    roleState: 'available',
    canBeSource: false,
    canBeTarget: true,
    targetBlockReasons: [],
    identityConfidence: 'stable_uuid',
  );

  static const _externalSsd = StorageDeviceSummary(
    mediaId: 'media_55a1f0c2d9e8437b6a1c2d3e',
    displayName: '移动固态硬盘',
    kind: 'external_ssd',
    kindConfidence: 'high',
    detail: 'Samsung T7 · 2 TB · EXFAT',
    capacityBytes: 2000000000000,
    freeBytes: 1280000000000,
    filesystem: 'exfat',
    label: 'T7',
    roleState: 'available',
    canBeSource: true,
    canBeTarget: true,
    targetBlockReasons: [],
    identityConfidence: 'stable_uuid',
  );

  /// 只读硬件设备：演示「不可选原因」的展示规则（§4.3）。
  static const _readOnlyHdd = StorageDeviceSummary(
    mediaId: 'media_c3e9b8a7f0d5e2c4b8a0f9e1',
    displayName: '移动硬盘（只读）',
    kind: 'external_hdd',
    kindConfidence: 'high',
    detail: 'Seagate Backup Plus · 2 TB · NTFS',
    capacityBytes: 2000000000000,
    freeBytes: 1400000000000,
    filesystem: 'ntfs',
    label: 'Backup',
    roleState: 'available',
    canBeSource: true,
    canBeTarget: false,
    targetBlockReasons: ['硬件只读设备，不能作为复制目标'],
    identityConfidence: 'stable_uuid',
  );

  /// 离线/身份降级设备：演示「不得作为长期默认目标」的展示规则（§3.1）。
  static const _offlineStick = StorageDeviceSummary(
    mediaId: 'media_9a4d1e2f3b8c7d6e5f4a3b2c',
    displayName: 'USB 存储设备（类型未确认）',
    kind: 'unknown',
    kindConfidence: 'low',
    detail: '无卷标 · 8 GB · FAT32',
    capacityBytes: 8000000000,
    freeBytes: 3000000000,
    filesystem: 'fat32',
    label: '',
    roleState: 'removed',
    canBeSource: false,
    canBeTarget: false,
    targetBlockReasons: ['设备已拔出或身份已变化'],
    identityConfidence: 'degraded',
  );

  @override
  Future<CopyDeviceList> devices() async {
    await _delay();
    final devices = [
      for (final device in const [
        _cameraCard,
        _usbStick,
        _externalSsd,
        _readOnlyHdd,
        _offlineStick,
      ])
        if (_aliases[device.mediaId] case final alias?) _withAlias(device, alias) else device,
    ];
    return CopyDeviceList(
      devices: devices,
      // 推荐目标默认 U 盘（§4.4 可修改的预选，非全局默认盘）。
      recommendedTargetMediaId: _usbStick.mediaId,
    );
  }

  static StorageDeviceSummary _withAlias(
    StorageDeviceSummary device,
    String alias,
  ) => StorageDeviceSummary(
    mediaId: device.mediaId,
    displayName: alias,
    kind: device.kind,
    kindConfidence: device.kindConfidence,
    detail: device.detail,
    capacityBytes: device.capacityBytes,
    freeBytes: device.freeBytes,
    filesystem: device.filesystem,
    label: device.label,
    roleState: device.roleState,
    canBeSource: device.canBeSource,
    canBeTarget: device.canBeTarget,
    targetBlockReasons: device.targetBlockReasons,
    identityConfidence: device.identityConfidence,
    lastSeenAt: device.lastSeenAt,
    userAlias: alias,
  );

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async {
    await _delay();
    if (assetIds.isEmpty) {
      throw StateError('没有选中的照片');
    }
    final snapshot = CopySelectionSnapshot(
      selectionId: 'sel_mock_${_nextToken()}',
      assetCount: assetIds.length,
      createdAt: _now(),
    );
    _createdSelections.add(snapshot.selectionId);
    return snapshot;
  }

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    await _delay();
    _guardFullBackup(draft.scope);
    final source = _requireDevice(draft.sourceMediaId, source: true);
    final target = _requireDevice(draft.targetMediaId, target: true);
    if (source.mediaId == target.mediaId) {
      throw StateError('源设备与目标设备不能相同');
    }
    final stats = _scopeStats(draft);
    final safetyReserve = max(target.capacityBytes ~/ 20, 1 << 30);
    final previewToken = 'preview_mock_${_nextToken()}';
    _previewItems[previewToken] = _buildPreviewItems(stats.files, stats.conflicts);
    return CopyPreview(
      previewToken: previewToken,
      expiresAt: _now().add(const Duration(minutes: 15)),
      source: source,
      target: target,
      logicalPhotoCount: stats.logical,
      actualFileCount: stats.files,
      totalBytes: stats.bytes,
      rawCount: stats.raw,
      jpegCount: stats.jpeg,
      videoCount: stats.video,
      companionCount: stats.companion,
      estimatedDateDirectories: stats.dateDirectories,
      conflictCount: stats.conflicts,
      targetFreeBytes: target.freeBytes,
      safetyReserveBytes: safetyReserve,
      unsupportedCount: stats.unsupported,
      missingCount: stats.missing,
    );
  }

  @override
  Future<CopyJobSummary> createJob(
    CopyRequestDraft draft,
    String previewToken,
  ) async {
    await _delay();
    _guardFullBackup(draft.scope);
    final source = _requireDevice(draft.sourceMediaId, source: true);
    final target = _requireDevice(draft.targetMediaId, target: true);
    // 演示任务固定 2 个文件项，其中 1 个校验失败（COPY_HASH_MISMATCH 语义），
    // 保证端到端能走完「部分完成 + 失败项重试」闭环。
    final job = _MockCopyJob(
      copyJobId: 'copy_mock_${_nextToken()}',
      createdAt: _now(),
      scopeWire: draft.scope.wireValue,
      batchId: draft.batchId,
      selectionId: draft.selectionId,
      sourceMediaId: source.mediaId,
      targetMediaId: target.mediaId,
    );
    _jobs[job.copyJobId] = job;
    return CopyJobSummary(
      copyJobId: job.copyJobId,
      state: job.state.wire,
      eventSeq: job.eventSeq,
      createdAt: job.createdAt,
    );
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async => null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {
    await _delay();
    _aliases[mediaId] = alias.trim();
  }

  // ---- RC3 任务闭环（§13.5/§13.6）----
  // capabilities() 沿用上方 rc3 契约 mock（copy_models.dart 的 CopyCapabilities）；
  // 全量备份不可用的负向路径由 _guardFullBackup 在 preview/createJob 拦截。

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async {
    await _delay();
    final jobs = _jobs.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final page = jobs.skip(offset).take(_pageSize).toList(growable: false);
    final hasMore = offset + page.length < jobs.length;
    return CopyJobPage(
      items: [
        for (final job in page)
          CopyJobListItem(
            copyJobId: job.copyJobId,
            state: job.state,
            scopeWire: job.scopeWire,
            stats: _statsFor(job),
            createdAt: job.createdAt,
          ),
      ],
      hasMore: hasMore,
      nextCursor: hasMore ? '${offset + page.length}' : null,
    );
  }

  @override
  Future<CopyJobDetail> getJob(String copyJobId) async {
    await _delay();
    final job = _requireJob(copyJobId);
    return _detailFor(job);
  }

  @override
  Future<CopyJobItemPage> jobItems(
    String copyJobId, {
    String? cursor,
    String? state,
  }) async {
    await _delay();
    final job = _requireJob(copyJobId);
    var items = job.items;
    if (state != null && state.isNotEmpty) {
      items = items.where((item) => item.state.wire == state).toList(growable: false);
    }
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final page = items.skip(offset).take(_pageSize).toList(growable: false);
    final hasMore = offset + page.length < items.length;
    return CopyJobItemPage(
      items: List.unmodifiable(page),
      hasMore: hasMore,
      nextCursor: hasMore ? '${offset + page.length}' : null,
    );
  }

  @override
  Future<CopyJobEventPage> jobEvents(String copyJobId, {int? afterSeq}) async {
    await _delay();
    final job = _requireJob(copyJobId);
    final events = afterSeq == null
        ? job.events
        : job.events
              .where((event) => event.seq != null && event.seq! > afterSeq)
              .toList(growable: false);
    return CopyJobEventPage(events: List.unmodifiable(events), hasMore: false);
  }

  @override
  Future<CopyReport> jobReport(String copyJobId) async {
    await _delay();
    final job = _requireJob(copyJobId);
    if (!job.state.isTerminal) {
      throw const ApiException(
        message: '任务结束后才能生成报告',
        code: 'COPY_REPORT_NOT_READY',
        statusCode: 409,
      );
    }
    final stats = _statsFor(job);
    final elapsedSeconds = job.finishedAt?.difference(job.createdAt).inSeconds;
    return CopyReport(
      copyJobId: job.copyJobId,
      selectionId: job.selectionId,
      logicalPhotoCount: job.items.length,
      actualFileCount: stats.totalFiles,
      copiedFiles: stats.copiedFiles,
      failedFiles: stats.failedFiles,
      skippedFiles: stats.skippedFiles,
      notApplicableFiles: stats.notApplicableFiles,
      totalBytes: stats.totalBytes,
      elapsedSeconds: elapsedSeconds,
      bytesPerSecond: stats.copiedBytes > 0 && elapsedSeconds != null && elapsedSeconds > 0
          ? stats.copiedBytes ~/ elapsedSeconds
          : null,
      sourceDevice: CopyJobDeviceSnapshot(mediaId: job.sourceMediaId),
      targetDevice: CopyJobDeviceSnapshot(mediaId: job.targetMediaId),
      generatedAt: _now(),
    );
  }

  @override
  Future<CopyJobDetail?> jobAction(
    String copyJobId,
    String actionWire, {
    required int expectedStateVersion,
  }) async {
    await _delay();
    final job = _requireJob(copyJobId);
    if (expectedStateVersion != job.stateVersion) {
      throw const ApiException(
        message: '任务状态已更新，请刷新后重试',
        code: 'COPY_STATE_VERSION_CONFLICT',
        statusCode: 409,
      );
    }
    final now = _now();
    switch (actionWire) {
      case 'pause':
        if (job.state == CopyJobState.running ||
            job.state == CopyJobState.acquiringTarget) {
          job.transition(CopyJobState.pauseRequested, now, '已请求暂停，当前文件完成后暂停');
        }
      case 'resume':
        if (job.state == CopyJobState.paused) {
          job.resume(now);
        }
      case 'cancel':
        if (!job.state.isTerminal) {
          job.transition(CopyJobState.cancelRequested, now, '已请求取消，已完成的副本不会删除');
        }
      case 'retry_failed':
        if (job.state == CopyJobState.failed ||
            job.state == CopyJobState.completedWithErrors) {
          job.retryFailed(now);
        }
      case 'safe_remove_source' || 'safe_remove_target':
        // App 走 safeRemoveDevice 端点；动作路由仅做版本校验兜底。
        break;
      default:
        throw const ApiException(
          message: '不支持的任务动作',
          code: 'COPY_ACTION_UNSUPPORTED',
          statusCode: 422,
        );
    }
    return _detailFor(job);
  }

  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async {
    await _delay();
    final items = _previewItems[previewId];
    if (items == null) {
      throw const ApiException(
        message: '预检已过期，请重新预检',
        code: 'COPY_PREVIEW_EXPIRED',
        statusCode: 404,
      );
    }
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final page = items.skip(offset).take(_pageSize).toList(growable: false);
    final hasMore = offset + page.length < items.length;
    return CopyJobItemPage(
      items: List.unmodifiable(page),
      hasMore: hasMore,
      nextCursor: hasMore ? '${offset + page.length}' : null,
    );
  }

  @override
  Future<SafeRemoveResult> safeRemoveDevice(
    String mediaId, {
    required String role,
    String? expectedCopyJobId,
  }) async {
    await _delay();
    final now = _now();
    // 有进行中的任务占用该设备时不得拔出（§4.5 安全移除条件）。
    final busy = _jobs.values.any(
      (job) =>
          !job.state.isTerminal &&
          (job.sourceMediaId == mediaId || job.targetMediaId == mediaId),
    );
    if (busy) {
      return const SafeRemoveResult(
        safeToRemove: false,
        reason: '有复制任务正在使用该设备，任务结束后再移除',
      );
    }
    _safeRemovedDevices.add(mediaId);
    return SafeRemoveResult(
      safeToRemove: true,
      keepUntil: now.add(const Duration(seconds: 60)),
    );
  }

  CopyJobDetail _detailFor(_MockCopyJob job) => CopyJobDetail(
    copyJobId: job.copyJobId,
    state: job.state,
    stateVersion: job.stateVersion,
    eventSeq: job.eventSeq,
    stats: _statsFor(job),
    sourceDevice: CopyJobDeviceSnapshot(mediaId: job.sourceMediaId),
    targetDevice: CopyJobDeviceSnapshot(mediaId: job.targetMediaId),
    allowedActions: _allowedActions(job),
    scopeWire: job.scopeWire,
    batchId: job.batchId,
    selectionId: job.selectionId,
    createdAt: job.createdAt,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
  );

  List<CopyAllowedAction> _allowedActions(_MockCopyJob job) {
    if (job.state == CopyJobState.running ||
        job.state == CopyJobState.acquiringTarget) {
      return const [CopyAllowedAction.pause, CopyAllowedAction.cancel];
    }
    if (job.state == CopyJobState.paused) {
      return const [CopyAllowedAction.resume, CopyAllowedAction.cancel];
    }
    if (job.state == CopyJobState.pauseRequested ||
        job.state == CopyJobState.cancelRequested) {
      return const [];
    }
    if (job.state == CopyJobState.completedWithErrors ||
        job.state == CopyJobState.failed) {
      return const [CopyAllowedAction.retryFailed];
    }
    if (job.state.isTerminal) {
      // 完成后允许安全移除目标设备（§4.5）。
      return const [CopyAllowedAction.safeRemoveTarget];
    }
    // waiting_* / queued / draft：只允许取消。
    return const [CopyAllowedAction.cancel];
  }

  CopyJobStats _statsFor(_MockCopyJob job) {
    var copied = 0;
    var failed = 0;
    var skipped = 0;
    var notApplicable = 0;
    for (final item in job.items) {
      switch (item.state) {
        case CopyItemState.copied:
          copied++;
        case CopyItemState.failed:
          failed++;
        case CopyItemState.skippedConflict:
          skipped++;
        case CopyItemState.notApplicable:
          notApplicable++;
        default:
          break;
      }
    }
    const itemBytes = 28 * 1024 * 1024;
    final total = job.items.length;
    return CopyJobStats(
      totalFiles: total,
      copiedFiles: copied,
      failedFiles: failed,
      skippedFiles: skipped,
      notApplicableFiles: notApplicable,
      totalBytes: total * itemBytes,
      copiedBytes: copied * itemBytes,
      elapsedSeconds: job.startedAt == null
          ? null
          : (_now().difference(job.startedAt!).inSeconds),
      etaSeconds: job.state.isTerminal || total == 0
          ? null
          : max(total - copied - failed, 1) * 2,
      bytesPerSecond: job.state == CopyJobState.running ? itemBytes ~/ 2 : null,
      currentFile: job.state == CopyJobState.running
          ? job.items
              .firstWhere(
                (entry) =>
                    entry.state == CopyItemState.copying ||
                    entry.state == CopyItemState.verifying,
                orElse: () => job.items.first,
              )
              .item
              .targetFilename
          : null,
      progressPercent: total == 0 ? null : ((copied + failed) / total).clamp(0.0, 1.0),
    );
  }

  _MockCopyJob _requireJob(String copyJobId) {
    _advanceAll();
    final job = _jobs[copyJobId];
    if (job == null) {
      throw const ApiException(message: '复制任务不存在', code: 'COPY_JOB_NOT_FOUND', statusCode: 404);
    }
    return job;
  }

  /// 惰性推进所有任务的状态机（每次读写前调用）。
  void _advanceAll() {
    final now = _now();
    for (final job in _jobs.values) {
      job.advance(now);
    }
  }

  void _guardFullBackup(CopyScope scope) {
    if (scope == CopyScope.mediaFullBackup && !fullBackupAvailable) {
      throw const ApiException(
        message: '当前盒子不支持全量备份',
        code: 'COPY_SCOPE_UNSUPPORTED',
        statusCode: 422,
      );
    }
  }

  /// 确定性预检明细：文件名按序号生成，前 [conflicts] 个标 skip。
  List<CopyJobItem> _buildPreviewItems(int files, int conflicts) {
    return List.unmodifiable([
      for (var i = 0; i < files; i++)
        CopyJobItem(
          copyItemId: 'item_${i.toString().padLeft(4, '0')}',
          sourceRelativePath: 'DCIM/100MSDCF/DSC0${(5000 + i).toString()}',
          sourceSize: 28 * 1024 * 1024,
          sourceMtimeNs: 1726000000000000000 + i * 1000000000,
          targetRelativeDirectory: '20260901',
          targetFilename:
              'DSC0${(5000 + i).toString()}${i.isEven ? '.ARW' : '.JPG'}',
          state: CopyItemState.pending,
          conflictDecision: i < conflicts ? 'skip' : null,
        ),
    ]);
  }

  static const _pageSize = 20;

  StorageDeviceSummary _requireDevice(
    String mediaId, {
    bool source = false,
    bool target = false,
  }) {
    const all = [
      _cameraCard,
      _usbStick,
      _externalSsd,
      _readOnlyHdd,
      _offlineStick,
    ];
    final device = all.where((item) => item.mediaId == mediaId).firstOrNull;
    if (device == null) throw StateError('设备不在线，请重新选择');
    if (source && !device.canBeSource) {
      throw StateError('该设备不能作为源设备');
    }
    if (target && !device.canBeTarget) {
      throw StateError('该设备不能作为目标设备');
    }
    return device;
  }

  /// 按范围生成协议结构的统计（§10.1 分类统计）。
  _MockStats _scopeStats(CopyRequestDraft draft) {
    switch (draft.scope) {
      case CopyScope.selectedAssets:
        final count = max(_selectedCount(draft), 1);
        return _MockStats(
          logical: count,
          files: count * 2,
          bytes: count * 2 * 28 * 1024 * 1024,
          raw: count,
          jpeg: count,
          conflicts: count ~/ 10,
          missing: 0,
        );
      case CopyScope.keptAssets:
      case CopyScope.recognizedAssets:
      case CopyScope.filteredAssets:
        return const _MockStats(
          logical: 34,
          files: 67,
          bytes: 34 * 28 * 1024 * 1024 + 33 * 6 * 1024 * 1024,
          raw: 34,
          jpeg: 33,
          video: 0,
          companion: 2,
          dateDirectories: 2,
          conflicts: 3,
          unsupported: 0,
          missing: 1,
        );
      case CopyScope.batchAllAssets:
        return const _MockStats(
          logical: 120,
          files: 240,
          bytes: 120 * 28 * 1024 * 1024 + 118 * 6 * 1024 * 1024 + 4 * 400 * 1024 * 1024,
          raw: 120,
          jpeg: 118,
          video: 4,
          companion: 9,
          dateDirectories: 3,
          conflicts: 5,
          unsupported: 0,
          missing: 2,
        );
      case CopyScope.mediaFullBackup:
        return const _MockStats(
          logical: 148,
          files: 296,
          bytes: 145 * 28 * 1024 * 1024 + 143 * 6 * 1024 * 1024 + 6 * 400 * 1024 * 1024,
          raw: 145,
          jpeg: 143,
          video: 6,
          companion: 14,
          dateDirectories: 4,
          conflicts: 6,
          unsupported: 3,
          missing: 1,
        );
    }
  }

  int _selectedCount(CopyRequestDraft draft) {
    // 相册多选后创建了不可变 selection；mock 用选择快照数量近似文件统计。
    final selection = draft.selectionId?.trim() ?? '';
    return selection.isEmpty ? 4 : _stableNumber(selection) % 9 + 2;
  }

  int _stableNumber(String seed) => seed.codeUnits.fold(0, (a, b) => a + b);

  String _nextToken() => '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(0xFFFFFF)}';

  Future<void> _delay() => Future<void>.delayed(const Duration(milliseconds: 260));
}

/// mock 任务状态机：由 [MockCopyRepository._advanceAll] 惰性驱动。
///
/// 时间线（固定演示节奏，总计约 6.4 秒到终态）：
/// queued(1.2s) → acquiring_target(1.2s) → running（文件项串行：每个
/// 1.8s = 复制 1.2s + 校验 0.6s；第 2 项校验失败）→ completed_with_errors。
class _MockCopyJob {
  _MockCopyJob({
    required this.copyJobId,
    required this.createdAt,
    required this.scopeWire,
    required this.batchId,
    required this.selectionId,
    required this.sourceMediaId,
    required this.targetMediaId,
  }) {
    _emit('job_created', '复制任务已创建');
  }

  final String copyJobId;
  final DateTime createdAt;
  final String scopeWire;
  final String? batchId;
  final String? selectionId;
  final String sourceMediaId;
  final String targetMediaId;

  CopyJobState state = CopyJobState.queued;
  int stateVersion = 1;
  int eventSeq = 0;
  DateTime? startedAt;
  DateTime? finishedAt;
  DateTime phaseStart = DateTime.now(); // 由首次 advance 修正
  bool _phaseStartInitialized = false;

  /// running 阶段的活跃毫秒数（排除暂停时间），驱动文件项推进。
  int _activeRunningMs = 0;
  DateTime? _runningTick;

  late final List<_MockCopyItemState> items = [
    _MockCopyItemState(
      item: const CopyJobItem(
        copyItemId: 'copy_item_0001',
        sourceRelativePath: 'DCIM/100MSDCF/DSC05001',
        sourceSize: 28 * 1024 * 1024,
        targetRelativeDirectory: '20260901',
        targetFilename: 'DSC05001.ARW',
      ),
      willFail: false,
    ),
    _MockCopyItemState(
      item: const CopyJobItem(
        copyItemId: 'copy_item_0002',
        sourceRelativePath: 'DCIM/100MSDCF/DSC05002',
        sourceSize: 28 * 1024 * 1024,
        targetRelativeDirectory: '20260901',
        targetFilename: 'DSC05002.JPG',
      ),
      // 第 2 项校验失败：演示「部分完成不得显示成成功」与失败项重试。
      willFail: true,
    ),
  ];

  final List<CopyJobEvent> events = [];

  void _emit(String type, String message) {
    eventSeq++;
    events.add(
      CopyJobEvent(
        seq: eventSeq,
        type: type,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  void transition(CopyJobState next, DateTime now, String message) {
    state = next;
    stateVersion++;
    phaseStart = now;
    _phaseStartInitialized = true;
    if (next == CopyJobState.running && startedAt == null) startedAt = now;
    if (next.isTerminal) finishedAt = now;
    _emit('state_changed', message);
  }

  void resume(DateTime now) {
    transition(CopyJobState.running, now, '任务已继续');
    _runningTick = now;
  }

  void retryFailed(DateTime now) {
    for (final item in items) {
      if (item.state == CopyItemState.failed) {
        item.state = CopyItemState.pending;
        item.enteredAtMs = 0;
      }
    }
    transition(CopyJobState.running, now, '已开始重试失败项');
    _runningTick = now;
    _activeRunningMs = 0;
  }

  /// 惰性推进：按当前状态与相对时间推进状态机与文件项。
  void advance(DateTime now) {
    if (!_phaseStartInitialized) {
      phaseStart = now;
      _phaseStartInitialized = true;
    }
    if (state.isTerminal) return;

    switch (state) {
      case CopyJobState.queued:
        if (now.difference(phaseStart) >= const Duration(milliseconds: 1200)) {
          transition(CopyJobState.acquiringTarget, now, '正在获取目标盘');
        }
      case CopyJobState.acquiringTarget:
        if (now.difference(phaseStart) >= const Duration(milliseconds: 1200)) {
          transition(CopyJobState.running, now, '开始复制文件');
          _runningTick = now;
        }
      case CopyJobState.running:
        _activeRunningMs += now.difference(_runningTick ?? now).inMilliseconds;
        _runningTick = now;
        _advanceItems();
        if (state == CopyJobState.running && items.every(_itemTerminal)) {
          transition(
            CopyJobState.completedWithErrors,
            now,
            '任务部分完成：${items.where((item) => item.state == CopyItemState.failed).length} 个文件失败',
          );
        }
      case CopyJobState.pauseRequested:
        if (now.difference(phaseStart) >= const Duration(milliseconds: 800)) {
          state = CopyJobState.paused;
          stateVersion++;
          phaseStart = now;
          _emit('state_changed', '任务已暂停');
        }
      case CopyJobState.cancelRequested:
        if (now.difference(phaseStart) >= const Duration(milliseconds: 800)) {
          state = CopyJobState.cancelled;
          stateVersion++;
          phaseStart = now;
          finishedAt = now;
          _emit('state_changed', '任务已取消，已完成的副本不会删除');
        }
      default:
        break;
    }
  }

  bool _itemTerminal(_MockCopyItemState item) => switch (item.state) {
    CopyItemState.copied ||
    CopyItemState.failed ||
    CopyItemState.skippedConflict ||
    CopyItemState.notApplicable => true,
    _ => false,
  };

  /// 文件项串行推进：同一时刻只有一个文件在复制/校验（§12 文件项状态机）。
  void _advanceItems() {
    var busy = false;
    for (final item in items) {
      switch (item.state) {
        case CopyItemState.pending:
          if (!busy) {
            item.state = CopyItemState.copying;
            item.enteredAtMs = _activeRunningMs;
            busy = true;
          }
        case CopyItemState.copying:
          busy = true;
          if (_activeRunningMs - item.enteredAtMs >= 1200) {
            item.state = CopyItemState.verifying;
            item.enteredAtMs = _activeRunningMs;
          }
        case CopyItemState.verifying:
          busy = true;
          if (_activeRunningMs - item.enteredAtMs >= 600) {
            item.state = item.willFail ? CopyItemState.failed : CopyItemState.copied;
            _emit(
              item.willFail ? 'item_failed' : 'item_copied',
              item.willFail
                  ? '文件 ${item.item.targetFilename} 校验失败（COPY_HASH_MISMATCH）'
                  : '文件 ${item.item.targetFilename} 已复制并通过校验',
            );
          }
        default:
          break;
      }
      if (busy) break; // 串行：当前文件占用时后续文件不再推进
    }
  }
}

class _MockCopyItemState {
  _MockCopyItemState({required this.item, required this.willFail});

  CopyJobItem item;
  final bool willFail;
  CopyItemState state = CopyItemState.pending;
  int enteredAtMs = 0;
}

class _MockStats {
  const _MockStats({
    required this.logical,
    required this.files,
    required this.bytes,
    required this.raw,
    required this.jpeg,
    this.video = 0,
    this.companion = 0,
    this.dateDirectories = 1,
    this.conflicts = 0,
    this.unsupported = 0,
    this.missing = 0,
  });

  final int logical;
  final int files;
  final int bytes;
  final int raw;
  final int jpeg;
  final int video;
  final int companion;
  final int dateDirectories;
  final int conflicts;
  final int unsupported;
  final int missing;
}
