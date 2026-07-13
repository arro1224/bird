import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _CopyRepository implements CopyRepository {
  _CopyRepository(this.estimateValue);
  final CopyEstimate estimateValue;
  var creates = 0;
  @override
  Future<BirdJobStatus> create(String batchId, String mode, String targetId) async {
    creates++;
    return const BirdJobStatus(id: 'job', type: BirdJobType.copy, state: BirdJobState.running);
  }

  @override
  Future<CopyEstimate> estimate(String batchId, String mode) async => estimateValue;
}

void main() {
  test('空间不足时不允许创建复制任务', () async {
    final repository = _CopyRepository(
      const CopyEstimate(
        mode: 'keep',
        fileCount: 10,
        requiredBytes: 100,
        pendingCount: 1,
        targets: [StorageTarget(id: 'disk', name: '磁盘', freeBytes: 99, totalBytes: 100, online: true)],
      ),
    );
    final cubit = CopyConfirmationCubit(repository, 'batch');
    await cubit.load();
    expect(cubit.state.submissionBlockReason, isNotNull);
    await cubit.submit();
    expect(repository.creates, 0);
  });
}
