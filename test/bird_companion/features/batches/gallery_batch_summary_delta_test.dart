import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'review deltas update counts immediately and coalesce authoritative reloads',
    () async {
      final bus = AppDataChangeBus();
      final repository = _BatchRepository(_batch(10, 5, 0));
      final cubit = BatchListCubit(
        repository,
        null,
        bus,
        const Duration(milliseconds: 5),
      );
      addTearDown(cubit.close);
      addTearDown(bus.dispose);
      await cubit.load();

      bus.publishChange(
        const ReviewDecisionChanged(
          deviceId: 'box-1',
          projectId: 'project-1',
          fileId: 'photo-1',
          beforeKeepState: KeepState.pending,
          afterKeepState: KeepState.keep,
          authoritativeVersion: 2,
          queued: false,
        ),
      );
      bus.publishChange(
        const ReviewDecisionChanged(
          deviceId: 'box-1',
          projectId: 'project-1',
          fileId: 'photo-2',
          beforeKeepState: KeepState.keep,
          afterKeepState: KeepState.discard,
          authoritativeVersion: null,
          queued: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.current?.reviewCount, 9);
      expect(cubit.state.current?.keepCount, 5);
      expect(cubit.state.current?.discardCount, 1);
      expect(cubit.state.items.single, cubit.state.current);

      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(repository.pageCalls, 1);
      expect(repository.currentCalls, 1);

      repository.batch = _batch(8, 6, 1);
      bus.publishChange(
        const ReviewDecisionChanged(
          deviceId: 'box-1',
          projectId: 'project-1',
          fileId: 'photo-2',
          beforeKeepState: KeepState.discard,
          afterKeepState: KeepState.discard,
          authoritativeVersion: 3,
          queued: false,
        ),
      );
      await _waitUntil(() => cubit.state.current?.reviewCount == 8);

      expect(cubit.state.current?.keepCount, 6);
      expect(cubit.state.current?.discardCount, 1);
      expect(repository.pageCalls, 2);
      expect(repository.currentCalls, 2);
    },
  );

  test('detail-route reconciliation is idempotent and keeps queued counts local', () async {
    final repository = _BatchRepository(_batch(10, 5, 0));
    final cubit = BatchListCubit(
      repository,
      null,
      null,
      const Duration(milliseconds: 5),
    );
    addTearDown(cubit.close);
    await cubit.load();
    final baseline = cubit.state.current!;
    const changes = [
      ReviewDecisionChanged(
        deviceId: 'box-1',
        projectId: 'project-1',
        fileId: 'photo-1',
        beforeKeepState: KeepState.pending,
        afterKeepState: KeepState.keep,
        authoritativeVersion: null,
        queued: true,
      ),
      ReviewDecisionChanged(
        deviceId: 'box-1',
        projectId: 'project-1',
        fileId: 'photo-2',
        beforeKeepState: KeepState.keep,
        afterKeepState: KeepState.discard,
        authoritativeVersion: null,
        queued: true,
      ),
    ];

    cubit.reconcileReviewChanges(baseline, changes);
    cubit.reconcileReviewChanges(baseline, changes);
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(cubit.state.current?.reviewCount, 9);
    expect(cubit.state.current?.keepCount, 5);
    expect(cubit.state.current?.discardCount, 1);
    expect(repository.pageCalls, 1);
    expect(repository.currentCalls, 1);
  });
}

class _BatchRepository implements BatchRepository {
  _BatchRepository(this.batch);

  BatchSummary batch;
  int pageCalls = 0;
  int currentCalls = 0;

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    pageCalls += 1;
    return BatchPage(items: [batch], hasMore: false);
  }

  @override
  Future<BatchSummary?> current() async {
    currentCalls += 1;
    return batch;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchSummary _batch(int pending, int keep, int discard) => BatchSummary(
  id: 'project-1',
  name: '测试拍摄记录',
  createdAt: DateTime.utc(2026, 9, 7),
  totalFiles: pending + keep + discard,
  analyzedCount: pending + keep + discard,
  reviewCount: pending,
  keepCount: keep,
  discardCount: discard,
  pendingCopyCount: 0,
  copyState: 'idle',
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Condition was not reached in time.');
}
