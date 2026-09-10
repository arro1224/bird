import 'dart:io';

import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R3 copy flow gating (birdbox-copy-v1)', () {
    test('initialize preselects a source and the same-batch target preference', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
        preferredTargetMediaId: 'media_target_2',
      );
      addTearDown(cubit.close);
      await cubit.initialize();

      expect(cubit.state.sourceMediaId, 'media_source_1');
      expect(cubit.state.targetMediaId, 'media_target_2');
      expect(cubit.state.loadingDevices, isFalse);
    });

    test('offline preferred target is not auto-replaced by another disk', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
        preferredTargetMediaId: 'media_target_offline',
      );
      addTearDown(cubit.close);
      await cubit.initialize();

      expect(cubit.state.targetMediaId, isNull);
      expect(cubit.state.preferredTargetMediaId, 'media_target_offline');
    });

    test('the same device cannot be source and target at once', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
      );
      addTearDown(cubit.close);
      await cubit.initialize();

      // 只能作源的设备不能选为目标。
      cubit.selectTarget('media_source_1');
      expect(cubit.state.targetMediaId, isNull);

      // 先选为目标，再选为源：最后选的角色生效，目标被清除。
      cubit.selectTarget('media_target_2');
      expect(cubit.state.targetMediaId, 'media_target_2');
      cubit.selectSource('media_target_2');
      expect(cubit.state.sourceMediaId, 'media_target_2');
      expect(cubit.state.targetMediaId, isNull);

      // 反过来：先选为源，再选为目标，源被清除。
      cubit.selectSource('media_target_2');
      expect(cubit.state.sourceMediaId, 'media_target_2');
      cubit.selectTarget('media_target_2');
      expect(cubit.state.sourceMediaId, isNull);
      expect(cubit.state.targetMediaId, 'media_target_2');
    });

    test('preview stays blocked until the conflict strategy is chosen', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
      );
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectTarget('media_target_1');

      expect(cubit.state.canFetchPreview, isFalse);
      expect(cubit.state.submissionBlockReason, '请选择同名文件处理策略');

      cubit.setConflictStrategy(ConflictStrategy.skip);
      expect(cubit.state.canFetchPreview, isTrue);
      expect(cubit.state.submissionBlockReason, '请先获取预检');

      final ok = await cubit.fetchPreview();
      expect(ok, isTrue);
      expect(cubit.state.preview, isNotNull);
    });

    test('submit never creates a job without an explicit conflict strategy', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
      );
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectTarget('media_target_1');
      await cubit.fetchPreview();

      final submitted = await cubit.submit();
      expect(submitted, isFalse);
      expect(repository.createCalls, 0);
      expect(cubit.state.submitted, isFalse);
    });

    test('submit re-runs the preview and creates the job with the fresh token', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.keptAssets,
      );
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectTarget('media_target_1');
      cubit.setConflictStrategy(ConflictStrategy.keepBoth);
      await cubit.fetchPreview();

      final submitted = await cubit.submit();
      expect(submitted, isTrue);
      expect(repository.previewCalls, 2);
      expect(repository.createCalls, 1);
      expect(repository.createdDraft?.conflictStrategy, ConflictStrategy.keepBoth);
      expect(repository.createdDraft?.targetMediaId, 'media_target_1');
      expect(cubit.state.submitted, isTrue);
      expect(cubit.state.createdJob?.copyJobId, 'copy_job_r3');
    });

    test('a double submit creates only one job', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: 'batch-1',
        scope: CopyScope.batchAllAssets,
      );
      addTearDown(cubit.close);
      await cubit.initialize();
      cubit.selectTarget('media_target_1');
      cubit.setConflictStrategy(ConflictStrategy.overwrite);
      await cubit.fetchPreview();

      final first = cubit.submit();
      final duplicate = cubit.submit();
      await duplicate;
      await first;
      expect(repository.createCalls, 1);
    });

    test('full backup scope requires no batch id', () async {
      final repository = _CopyRepository();
      final cubit = CopyConfigCubit(
        repository,
        batchId: null,
        scope: CopyScope.mediaFullBackup,
      );
      addTearDown(cubit.close);
      await cubit.initialize();

      expect(cubit.state.fullBackup, isTrue);
      expect(cubit.state.sourceMediaId, 'media_source_1');
      expect(cubit.state.batchId, isNull);
    });

    test('production page keeps the two-step flow and protocol gating', () {
      final source = File(
        'lib/bird_companion/features/copy/presentation/'
        'copy_confirmation_page.dart',
      ).readAsStringSync();

      expect(source, contains('CopyContentStep('));
      expect(source, contains('CopyFinalConfirmationStep('));
      expect(source, contains('conflictStrategy'));
      expect(source, contains('fetchPreview'));
      expect(source, isNot(contains('CopyConfirmDialog(')));
      expect(source, isNot(contains('双轨')));
    });
  });
}

const _sourceDevice = StorageDeviceSummary(
  mediaId: 'media_source_1',
  displayName: '相机卡',
  kind: 'card_reader',
  kindConfidence: 'high',
  detail: '双槽读卡器 · 119.2 GB · EXFAT',
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

const _target1 = StorageDeviceSummary(
  mediaId: 'media_target_1',
  displayName: 'U 盘 Ee',
  kind: 'usb_flash',
  kindConfidence: 'medium',
  detail: 'SanDisk · 28.7 GB · EXFAT',
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

const _target2 = StorageDeviceSummary(
  mediaId: 'media_target_2',
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

const _offlineTarget = StorageDeviceSummary(
  mediaId: 'media_target_offline',
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

class _CopyRepository implements CopyRepository {
  int previewCalls = 0;
  int createCalls = 0;
  CopyRequestDraft? createdDraft;

  @override
  Future<List<StorageDeviceSummary>> devices() async =>
      const [_sourceDevice, _target1, _target2, _offlineTarget];

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async => CopySelectionSnapshot(
    selectionId: 'sel_mock_1',
    assetCount: assetIds.length,
  );

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    previewCalls += 1;
    final target = const [_target1, _target2, _offlineTarget]
        .firstWhere((device) => device.mediaId == draft.targetMediaId);
    return CopyPreview(
      previewToken: 'preview_mock_$previewCalls',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      source: _sourceDevice,
      target: target,
      logicalPhotoCount: 34,
      actualFileCount: 67,
      totalBytes: 1024 * 1024 * 1024,
      rawCount: 34,
      jpegCount: 33,
      videoCount: 0,
      companionCount: 2,
      estimatedDateDirectories: 2,
      conflictCount: 3,
      targetFreeBytes: target.freeBytes,
      safetyReserveBytes: 1 << 30,
      missingCount: 1,
    );
  }

  @override
  Future<CopyJobSummary> createJob(
    CopyRequestDraft draft,
    String previewToken,
  ) async {
    createCalls += 1;
    createdDraft = draft;
    return const CopyJobSummary(
      copyJobId: 'copy_job_r3',
      state: 'queued',
      eventSeq: 0,
    );
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async =>
      null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {}
}
