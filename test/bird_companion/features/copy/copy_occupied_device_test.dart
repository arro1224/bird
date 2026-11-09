import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

/// v10 返修问题 6（2026-11-09）：设备被进行中任务占用的显示。
///
/// 核心互斥已通过（反馈原文 §三.6）；本轮修的是显示——占用不归类为
/// 断线、不诱导反复检测，并提供"查看当前任务"入口（乙侧设备页消费）。
void main() {
  test('目标盘 COPY_TARGET_BUSY → 占用文案，不是断线文案', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    repository.storage[1] = b3Device('target', reasons: ['COPY_TARGET_BUSY']);
    await cubit.refreshDevices();
    expect(cubit.state.occupiedByRunningJob, true);
    expect(cubit.state.targetOccupiedByJob, true);
    expect(cubit.state.submissionBlockReason, contains('占用'));
    expect(cubit.state.submissionBlockReason, isNot(contains('断开')));
    expect(cubit.state.submissionBlockReason, isNot(contains('连接')));
    expect(await cubit.submit(), false);
  });

  test('源卡 COPY_TARGET_BUSY → 占用文案；普通源卡角色标记不算占用', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    // rc3 常规源卡带角色说明标记，不算占用。
    expect(cubit.state.sourceOccupiedByJob, false);
    expect(cubit.state.occupiedByRunningJob, false);

    repository.storage[0] = b3Device('source', source: true, target: false, reasons: ['COPY_TARGET_BUSY']);
    await cubit.refreshDevices();
    expect(cubit.state.sourceOccupiedByJob, true);
    expect(cubit.state.environmentBlockReason, contains('占用'));
  });

  test('离线设备的 COPY_TARGET_BUSY 不是占用（盘已拔出）', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    repository.storage[1] = b3Device('target', online: false, reasons: ['COPY_TARGET_BUSY']);
    await cubit.refreshDevices();
    expect(cubit.state.targetOccupiedByJob, false, reason: '断开优先于占用');
    expect(cubit.state.submissionBlockReason, contains('断开'));
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
