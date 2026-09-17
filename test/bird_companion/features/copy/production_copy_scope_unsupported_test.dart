import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// RC3 能力门控负向路径（01 文档 §二 P0-2）：
/// 预检 COPY_SCOPE_UNSUPPORTED → scopeUnavailable=true、不得创建任务。
void main() {
  test('preview COPY_SCOPE_UNSUPPORTED → scopeUnavailable，submit 不调 createJob', () async {
    final repository = _ScopeUnsupportedRepository();
    final cubit = CopyConfigCubit(
      repository,
      batchId: 'batch-1',
      scope: CopyScope.batchAllAssets,
    );
    addTearDown(cubit.close);
    await cubit.initialize();
    cubit.selectTarget(_repositoryTargetId);
    cubit.setConflictStrategy(ConflictStrategy.skip);

    final fetched = await cubit.fetchPreview();
    expect(fetched, isFalse);
    expect(cubit.state.scopeUnavailable, isTrue);
    // 提交被 submissionBlockReason 阻断，createJob 不被调用。
    expect(cubit.state.submissionBlockReason, isNotNull);
    final submitted = await cubit.submit();
    expect(submitted, isFalse);
    expect(repository.createJobCalls, 0);
    // 文案走 mapper（新码映射冻结测试并入此处）。
    final message = UserMessageMapper.fromError(repository.lastError!);
    expect(message.title, '当前盒子不支持全量备份');
  });
}

const _repositoryTargetId = 'media_target_1';

class _ScopeUnsupportedRepository implements CopyRepository {
  int createJobCalls = 0;
  Object? lastError;

  @override
  Future<CopyCapabilities> capabilities() async => const CopyCapabilities(
    revision: '1.0-rc3',
    copyReady: true,
    supportedScopes: [CopyScope.batchAllAssets],
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
  Future<CopyPreferences> preferences() async =>
      const CopyPreferences(pairPolicy: PairPolicy.rawOnly, version: 1, origin: 'factory_default');

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
    const CopyScopeOption(
      scope: CopyScope.batchAllAssets,
      available: true,
      logicalAssets: 120,
      countState: 'known',
      navigationAction: 'none',
    ),
  ];

  @override
  Future<CopySelectionSnapshot> createSelection(
    String batchId,
    List<String> assetIds, {
    required int clientRevision,
  }) async => CopySelectionSnapshot(
    selectionId: 'sel-1',
    assetCount: assetIds.length,
  );

  @override
  Future<CopyDeviceList> devices() async => const CopyDeviceList(devices: [
    StorageDeviceSummary(
      mediaId: 'media_source_1',
      displayName: '相机卡（读卡器）',
      kind: 'card_reader',
      kindConfidence: 'high',
      detail: '',
      capacityBytes: 128000000000,
      freeBytes: 96400000000,
      filesystem: 'exfat',
      label: '',
      roleState: 'available',
      canBeSource: true,
      canBeTarget: false,
      targetBlockReasons: [],
      identityConfidence: 'stable_uuid',
    ),
    StorageDeviceSummary(
      mediaId: _repositoryTargetId,
      displayName: 'U 盘 Ee',
      kind: 'usb_flash',
      kindConfidence: 'medium',
      detail: '',
      capacityBytes: 30765203456,
      freeBytes: 30500000000,
      filesystem: 'exfat',
      label: '',
      roleState: 'available',
      canBeSource: false,
      canBeTarget: true,
      targetBlockReasons: [],
      identityConfidence: 'stable_uuid',
    ),
  ]);

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async {
    lastError = const ApiException(
      message: '当前盒子不支持全量备份',
      code: 'COPY_SCOPE_UNSUPPORTED',
      statusCode: 422,
    );
    throw lastError!;
  }

  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async {
    createJobCalls++;
    throw StateError('scope unavailable，不得创建任务');
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async => null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {}
}
