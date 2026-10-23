import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// 修复 2 走查（2026-10-14）：RAW+JPEG 策略保存失败回滚。
///
/// 实机走查补充：`BIRD_USE_MOCK_COPY=true` 时 savePreferences 走 App 内置
/// 内存 mock（mock_copy_repository.dart，永远成功），关掉 mock 盒子进程
/// 触发不了失败分支——回滚逻辑（copy_config_cubit.dart `setPairPolicy`）
/// 在此用注入失败的 fake 仓储验证。
void main() {
  test('后端未开放审阅导出时，保留普通复制并禁止打开导出开关', () async {
    final cubit = await _initialized(_NoExportRepository());
    addTearDown(cubit.close);
    expect(cubit.state.copyReady, isTrue);
    expect(cubit.state.reviewExportReady, isFalse);
    cubit.setReviewExportEnabled(true);
    expect(cubit.state.reviewExport.enabled, isFalse);
  });
  test('保存失败 → 策略回滚到旧值并暴露 error，版本号不变', () async {
    final repository = _FakeCopyRepository()..saveShouldThrow = true;
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    expect(cubit.state.pairPolicy, PairPolicy.rawOnly);
    expect(cubit.state.preferencesVersion, 1);

    await cubit.setPairPolicy(PairPolicy.jpegOnly);

    expect(cubit.state.pairPolicy, PairPolicy.rawOnly, reason: '保存失败必须回滚 UI 选择');
    expect(cubit.state.error, isA<ApiException>());
    expect(cubit.state.preferencesVersion, 1);
  });

  test('保存成功 → 保持新策略并吸收服务端版本号', () async {
    final repository = _FakeCopyRepository();
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    await cubit.setPairPolicy(PairPolicy.both);

    expect(cubit.state.pairPolicy, PairPolicy.both);
    expect(cubit.state.error, isNull);
    expect(cubit.state.preferencesVersion, 2);
  });

  test('保存期间用户又改策略 → 以最新 UI 选择为准，不回滚到旧请求值', () async {
    final repository = _FakeCopyRepository();
    final cubit = await _initialized(repository);
    addTearDown(cubit.close);

    repository.gateNextSave(
      const CopyPreferences(pairPolicy: PairPolicy.jpegOnly, version: 2, origin: 'user_saved'),
    );
    final first = cubit.setPairPolicy(PairPolicy.jpegOnly);
    await pumpEventQueue();
    await cubit.setPairPolicy(PairPolicy.both);
    await first;
    await pumpEventQueue();

    expect(cubit.state.pairPolicy, PairPolicy.both, reason: '以保存期间用户的最新选择为准');
    expect(cubit.state.error, isNull);
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

Future<CopyConfigCubit> _initialized(_FakeCopyRepository repository) async {
  final cubit = CopyConfigCubit(
    repository,
    batchId: 'batch-1',
    scope: CopyScope.recognizedAssets,
  );
  await cubit.initialize();
  expect(cubit.state.preferencesVersion, 1);
  return cubit;
}

class _FakeCopyRepository implements CopyRepository {
  bool saveShouldThrow = false;
  Completer<CopyPreferences>? _gatedSave;

  /// 下一次 savePreferences 挂在已完成的 completer 上，用于制造
  /// 「保存仍在途」窗口。
  void gateNextSave(CopyPreferences response) {
    _gatedSave = Completer<CopyPreferences>()..complete(response);
  }

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
    final gate = _gatedSave;
    if (gate != null) {
      _gatedSave = null;
      return gate.future;
    }
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
  Future<CopyDeviceList> devices() async => const CopyDeviceList(devices: []);

  @override
  Future<CopyPreview> preview(CopyRequestDraft draft) async => throw UnimplementedError();

  @override
  Future<CopyJobSummary> createJob(CopyRequestDraft draft, String previewToken) async {
    throw UnimplementedError();
  }

  @override
  Future<BatchTargetPreference?> lastSuccessfulTarget(String batchId) async => null;

  @override
  Future<void> setDeviceAlias(String mediaId, String alias) async {}
}
