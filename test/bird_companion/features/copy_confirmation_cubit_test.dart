import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _CopyRepository implements CopyRepository {
  _CopyRepository(this.estimateValues);
  final List<CopyEstimate> estimateValues;
  var creates = 0;
  var estimates = 0;
  bool? createdWithXmp;
  @override
  Future<BirdJobStatus> create(String batchId, String mode, String targetId, {required bool xmpEnabled}) async {
    creates++;
    createdWithXmp = xmpEnabled;
    return const BirdJobStatus(id: 'job', type: BirdJobType.copy, state: BirdJobState.running);
  }

  @override
  Future<CopyEstimate> estimate(String batchId, String mode) async {
    final index = estimates < estimateValues.length ? estimates : estimateValues.length - 1;
    estimates++;
    return estimateValues[index];
  }
}

void main() {
  test('空间不足时不允许创建复制任务', () async {
    final repository = _CopyRepository([
      const CopyEstimate(
        mode: 'keep',
        fileCount: 10,
        requiredBytes: 100,
        pendingCount: 1,
        targets: [StorageTarget(id: 'disk', name: '磁盘', freeBytes: 99, totalBytes: 100, online: true)],
      ),
    ]);
    final cubit = CopyConfirmationCubit(repository, 'batch');
    await cubit.load();
    expect(cubit.state.submissionBlockReason, isNotNull);
    await cubit.submit();
    expect(repository.creates, 0);
  });

  test('提交前会重新估算并拦截已离线的目标盘', () async {
    const available = CopyEstimate(
      mode: 'keep',
      fileCount: 10,
      requiredBytes: 100,
      pendingCount: 0,
      targets: [StorageTarget(id: 'disk', name: '磁盘', freeBytes: 200, totalBytes: 300, online: true)],
    );
    const offline = CopyEstimate(
      mode: 'keep',
      fileCount: 10,
      requiredBytes: 100,
      pendingCount: 0,
      targets: [StorageTarget(id: 'disk', name: '磁盘', freeBytes: 200, totalBytes: 300, online: false)],
    );
    final repository = _CopyRepository([available, offline]);
    final cubit = CopyConfirmationCubit(repository, 'batch');
    await cubit.load();
    await cubit.submit();
    expect(repository.estimates, 2);
    expect(repository.creates, 0);
    expect(cubit.state.error, isNotNull);
  });

  test('XMP 选择会写入创建任务请求', () async {
    const available = CopyEstimate(
      mode: 'keep',
      fileCount: 10,
      requiredBytes: 100,
      pendingCount: 0,
      targets: [StorageTarget(id: 'disk', name: '磁盘', freeBytes: 200, totalBytes: 300, online: true)],
    );
    final repository = _CopyRepository([available]);
    final cubit = CopyConfirmationCubit(repository, 'batch');
    await cubit.load();
    cubit.setXmpEnabled(false);
    await cubit.submit();
    expect(repository.creates, 1);
    expect(repository.createdWithXmp, isFalse);
  });
}
