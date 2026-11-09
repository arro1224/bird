import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

/// v10 返修问题 10（2026-11-09）：预检 120 秒过期自动重检。
///
/// 后端已把 TTL 收敛为 120 秒（修改说明 §3）；App 侧过期后自动重新
/// 预检并展示最新摘要，重大变化的重确认由 submit 签名比对保证。
void main() {
  test('预检过期后自动重新预检，新令牌生效且无需用户点击', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(milliseconds: 80);
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    final oldToken = cubit.state.preview!.previewToken;
    final callsBefore = repository.previewCalls;

    // 等过期定时器触发自动重检。
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await _settle(() => repository.previewCalls > callsBefore && cubit.state.preflightStatus == CopyPreflightStatus.valid);
    expect(cubit.state.preview?.previewToken, isNot(oldToken), reason: '自动重检产生新令牌');
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
    expect(cubit.state.invalidationReason, isNull, reason: '自动重检成功后清除过期标记');
    expect(await cubit.submit(), true, reason: '计划未变化时直接可创建');
  });

  test('预检过期且设备已离线 → 自动重检失败并明确提示，不静默创建', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(milliseconds: 80);
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    repository.storage[1] = b3Device('target', online: false);

    await Future<void>.delayed(const Duration(milliseconds: 160));
    await _settle(() => cubit.state.preflightStatus != CopyPreflightStatus.loading && cubit.state.invalidationReason != null);
    expect(cubit.state.preview, isNull);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.targetOffline);
    expect(await cubit.submit(), false);
  });

  test('后台页面的预检过期只失效不自动重检，回前台后刷新再重检', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(milliseconds: 80);
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    final callsBefore = repository.previewCalls;
    cubit.setPageActive(false);

    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(repository.previewCalls, callsBefore, reason: '非活跃页面不自动重检');
    expect(cubit.state.preview, isNull);

    cubit.setPageActive(true);
    await _settle(() => repository.previewCalls > callsBefore || cubit.state.preflightStatus != CopyPreflightStatus.invalidated);
    expect(cubit.state.pageActive, true);
  });
}

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository, {Duration poll = Duration.zero}) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: poll);
  addTearDown(cubit.close);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

Future<void> _settle(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('State did not settle');
}
