import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/synthetic_copy_plan.dart';

/// v10 返修问题 7（2026-11-09）：RAW+JPEG 策略保存时机。
///
/// 原「保存失败回滚」走查（2026-10-14）语义已迁移：草稿期选择不再写盘，
/// 服务端偏好只在任务创建成功后原子保存（copy_config_cubit
/// `_persistPairPolicyAfterCreate`）。保存失败的"回滚"对象变为
/// 「创建结果不受偏好保存失败影响」，见第 3 条用例。
void main() {
  test('后端未开放审阅导出时，保留普通复制并禁止打开导出开关', () async {
    final cubit = await _initialized(_NoExportRepository());
    addTearDown(cubit.close);
    expect(cubit.state.copyReady, isTrue);
    expect(cubit.state.reviewExportReady, isFalse);
    cubit.setReviewExportEnabled(true);
    expect(cubit.state.reviewExport.enabled, isFalse);
  });

  test('草稿期选择不写盘：退出前任何选择都不产生 savePreferences 调用', () async {
    final repository = _FakeCopyRepository()..saveShouldThrow = true;
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    expect(cubit.state.pairPolicy, PairPolicy.rawOnly);
    expect(cubit.state.preferencesVersion, 1);

    cubit.setPairPolicy(PairPolicy.jpegOnly);
    expect(cubit.state.pairPolicy, PairPolicy.jpegOnly, reason: '草稿选择立即生效于本地状态');
    expect(repository.saveCalls, 0, reason: '未创建任务不得保存偏好');
    expect(cubit.state.error, isNull);
    expect(cubit.state.preferencesVersion, 1);

    // 反复改选也不写盘。
    cubit.setPairPolicy(PairPolicy.both);
    expect(cubit.state.pairPolicy, PairPolicy.both);
    expect(repository.saveCalls, 0);
  });

  test('创建成功 → 以草稿最新选择保存一次并吸收服务端版本号', () async {
    final repository = _FakeCopyRepository();
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    cubit.setPairPolicy(PairPolicy.both);
    expect(cubit.state.preview, isNull, reason: '草稿变更使旧预检失效（期望行为）');
    expect(await cubit.fetchPreview(), true);
    final submitted = await cubit.submit();
    expect(submitted, isTrue);
    expect(repository.createCalls, 1);
    expect(repository.createdDraft?.pairPolicy, PairPolicy.both);
    expect(repository.saveCalls, 1);
    expect(repository.lastSavedPolicy, PairPolicy.both);
    expect(cubit.state.preferencesVersion, 2, reason: '吸收服务端返回的新版本号');
    expect(cubit.state.pairPolicy, PairPolicy.both);
    expect(cubit.state.error, isNull);
  });

  test('创建后保存失败 → 任务创建结果不受影响，草稿选择保留不回滚', () async {
    final repository = _FakeCopyRepository()..saveShouldThrow = true;
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    cubit.setPairPolicy(PairPolicy.jpegOnly);
    expect(await cubit.fetchPreview(), true);
    final submitted = await cubit.submit();
    expect(submitted, isTrue, reason: '偏好是便利设置，保存失败不得否定已成功的创建');
    expect(repository.createCalls, 1);
    expect(cubit.state.submitted, isTrue);
    expect(cubit.state.createdJob, isNotNull);
    expect(cubit.state.pairPolicy, PairPolicy.jpegOnly, reason: '草稿选择保留，等待下次创建时再保存');
    expect(cubit.state.preferencesVersion, 1, reason: '版本号不吸收失败响应');
    expect(cubit.state.error, isNull, reason: '偏好保存失败不暴露为任务错误');
  });

  test('未改动的策略创建后不重复保存', () async {
    final repository = _FakeCopyRepository();
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    // 初始偏好即 rawOnly，未改选 → 创建后不调用 savePreferences。
    final submitted = await cubit.submit();
    expect(submitted, isTrue);
    expect(repository.saveCalls, 0, reason: '与服务端已知值一致时不得重复保存');
    expect(cubit.state.preferencesVersion, 1);
  });
}

class _NoExportRepository extends _FakeCopyRepository {
  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.recognizedAssets],
    recognitionPolicyVersion: 'recognized-assets-v1',
    reviewExportReady: false,
  );
}

const _source = StorageDeviceSummary(
  mediaId: 'media_source_1',
  displayName: '相机卡（读卡器）',
  kind: 'memory_card',
  kindConfidence: 'high',
  detail: '测试设备',
  capacityBytes: 2000000,
  freeBytes: 1000000,
  filesystem: 'exfat',
  label: 'source',
  roleState: 'available',
  canBeSource: true,
  canBeTarget: false,
  targetBlockReasons: [],
  identityConfidence: 'stable_uuid',
);

const _target = StorageDeviceSummary(
  mediaId: 'media_target_1',
  displayName: 'U 盘',
  kind: 'usb_flash',
  kindConfidence: 'high',
  detail: '测试设备',
  capacityBytes: 2000000,
  freeBytes: 1000000,
  filesystem: 'exfat',
  label: 'target',
  roleState: 'available',
  canBeSource: true,
  canBeTarget: true,
  targetBlockReasons: [],
  identityConfidence: 'stable_uuid',
);

Future<CopyConfigCubit> _initialized(_FakeCopyRepository repository) async {
  final cubit = CopyConfigCubit(
    repository,
    batchId: 'batch-1',
    scope: CopyScope.recognizedAssets,
  );
  await cubit.initialize();
  expect(cubit.state.preferencesVersion, 1);
  cubit.selectTarget('media_target_1');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  cubit.selectTarget('media_target_1');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

class _FakeCopyRepository with SyntheticCopyPlan implements CopyRepository {
  bool saveShouldThrow = false;
  int saveCalls = 0;
  PairPolicy? lastSavedPolicy;
  int createCalls = 0;
  CopyRequestDraft? createdDraft;

  @override
  int get syntheticFileCount => 1;
  @override
  int get syntheticBytes => 100;

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.recognizedAssets],
    recognitionPolicyVersion: 'recognized-assets-v1',
  );

  @override
  Future<SourceBinding> source({String? batchId}) async => SourceBinding(
    sourceMediaId: 'media_source_1',
    displayName: '相机卡（读卡器）',
    token: 'binding-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    verifiedReadOnly: true,
    batchId: batchId,
  );

  @override
  Future<CopyPreferences> preferences() async => const CopyPreferences(pairPolicy: PairPolicy.rawOnly, version: 1, origin: 'factory_default');

  @override
  Future<CopyPreferences> savePreferences(
    PairPolicy pairPolicy, {
    required int expectedVersion,
  }) async {
    saveCalls += 1;
    lastSavedPolicy = pairPolicy;
    if (saveShouldThrow) {
      throw const ApiException(
        message: '网络连接失败',
        code: 'NETWORK_UNREACHABLE',
        statusCode: 0,
      );
    }
    return CopyPreferences(
      pairPolicy: pairPolicy,
      version: expectedVersion + 1,
      origin: 'user_saved',
    );
  }

  @override
  Future<List<CopyScopeOption>> scopeOptions({
    String? batchId,
    String? selectionId,
    Map<String, dynamic>? filter,
  }) async => const [
    CopyScopeOption(
      scope: CopyScope.recognizedAssets,
      available: true,
      logicalAssets: 34,
      countState: 'known',
      navigationAction: 'none',
    ),
  ];

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async => CopySelectionSnapshot(selectionId: 'sel-1', assetCount: assetIds.length);

  @override
  Future<CopyDeviceList> devices() async => const CopyDeviceList(devices: [_source, _target]);

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async => CopyPreview(
    previewToken: 'preview_mock_1',
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    source: _source,
    target: _target,
    logicalPhotoCount: 34,
    actualFileCount: 1,
    totalBytes: syntheticBytes,
    rawCount: 34,
    jpegCount: 33,
    videoCount: 0,
    companionCount: 0,
    estimatedDateDirectories: 1,
    conflictCount: 0,
    targetFreeBytes: _target.freeBytes,
    safetyReserveBytes: 1,
  );

  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async {
    createCalls += 1;
    createdDraft = draft;
    return const CopyJobSummary(copyJobId: 'copy_job_pair_pref', state: 'queued', eventSeq: 0);
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async => null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {}
}
