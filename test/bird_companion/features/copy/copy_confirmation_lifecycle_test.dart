import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository, {Duration poll = Duration.zero}) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: poll);
  addTearDown(cubit.close);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

/// v10 返修问题 3（2026-11-09）：确认页生命周期。
///
/// 截图/通知栏/锁屏/短暂切后台触发 inactive→paused→resumed；预检在
/// 令牌有效期内不得销毁。不透明路由压栈仍走 setPageActive 失效语义
/// （b3_copy_targets_and_errors_test 已覆盖，不在此重复）。
void main() {
  test('生命周期往返不销毁有效预检，静默刷新后原令牌仍在', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    final token = cubit.state.preview!.previewToken;

    // 截图/下拉通知栏：inactive。
    cubit.setAppLifecycleActive(false);
    expect(cubit.state.preview?.previewToken, token, reason: 'inactive 不销毁预检');
    expect(cubit.state.pageActive, true, reason: '页面本身仍在导航栈顶');

    // 回前台：静默刷新，设备未变化 → 恢复原确认页。
    cubit.setAppLifecycleActive(true);
    final fresh = await cubit.refreshDevices();
    expect(fresh, true);
    expect(cubit.state.preview?.previewToken, token, reason: '设备未变化时恢复原预检');
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
    expect(cubit.state.invalidationReason, isNull);
    expect(await cubit.submit(), true, reason: '往返后可直接创建任务');
  });

  test('锁屏期间目标盘被移除 → 回前台刷新失效并要求重新预检', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    cubit.setAppLifecycleActive(false);

    // 锁屏期间真实世界变化：目标盘移除。
    repository.storage[1] = b3Device('target', online: false);
    cubit.setAppLifecycleActive(true);
    await cubit.refreshDevices();
    expect(cubit.state.preview, isNull, reason: '设备真实变化必须失效预检');
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.targetOffline);
    expect(await cubit.submit(), false);
  });

  test('生命周期暂停期间停止轮询，恢复后重启', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository, poll: const Duration(milliseconds: 20));
    addTearDown(cubit.close);
    final before = repository.deviceCalls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final polled = repository.deviceCalls;
    expect(polled, greaterThan(before));

    cubit.setAppLifecycleActive(false);
    final paused = repository.deviceCalls;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(repository.deviceCalls, paused, reason: '后台期间不再轮询');

    cubit.setAppLifecycleActive(true);
    await until(() => repository.deviceCalls > paused);
    expect(cubit.state.devicesFresh, true);
  });

  test('提交成功后生命周期事件不再触碰状态', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository, poll: Duration.zero);
    addTearDown(cubit.close);
    expect(await cubit.submit(), true);
    expect(cubit.state.submitted, true);
    cubit.setAppLifecycleActive(false);
    cubit.setAppLifecycleActive(true);
    expect(cubit.state.submitted, true);
    expect(cubit.state.createdJob, isNotNull);
  });
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('State did not settle');
}
