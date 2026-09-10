import 'dart:math';

import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';

/// 协议字段 mock 实现（迁移对照文档 §7）。
///
/// 后端交付 birdbox-copy-v1 前，[useMockCopyRepository] 为 true 时使用本实现。
/// 所有字段与语义均为主协议字段，不创造临时枚举；设备数据取自协议 §22
/// 已实机验证记录。联调时将开关置为 false 即可切换真实接口。
const useMockCopyRepository = true;

class MockCopyRepository implements CopyRepository {
  MockCopyRepository();

  final Random _random = Random();
  final Map<String, String> _aliases = {};
  final Set<String> _createdSelections = {};
  final Set<String> _createdJobs = {};

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
  Future<List<StorageDeviceSummary>> devices() async {
    await _delay();
    return [
      for (final device in const [
        _cameraCard,
        _usbStick,
        _externalSsd,
        _readOnlyHdd,
        _offlineStick,
      ])
        if (_aliases[device.mediaId] case final alias?) _withAlias(device, alias) else device,
    ];
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
      createdAt: DateTime.now(),
    );
    _createdSelections.add(snapshot.selectionId);
    return snapshot;
  }

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    await _delay();
    final source = _requireDevice(draft.sourceMediaId, source: true);
    final target = _requireDevice(draft.targetMediaId, target: true);    if (source.mediaId == target.mediaId) {
      throw StateError('源设备与目标设备不能相同');
    }
    final stats = _scopeStats(draft);
    final safetyReserve = max(target.capacityBytes ~/ 20, 1 << 30);
    return CopyPreview(
      previewToken: 'preview_mock_${_nextToken()}',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
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
    final summary = CopyJobSummary(
      copyJobId: 'copy_mock_${_nextToken()}',
      state: 'queued',
      eventSeq: 0,
      createdAt: DateTime.now(),
    );
    _createdJobs.add(summary.copyJobId);
    return summary;
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async =>
      null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {
    await _delay();
    _aliases[mediaId] = alias.trim();
  }

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

  String _nextToken() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(0xFFFFFF)}';

  Future<void> _delay() => Future<void>.delayed(const Duration(milliseconds: 260));
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
