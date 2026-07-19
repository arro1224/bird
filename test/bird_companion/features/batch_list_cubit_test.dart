import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_overview.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

final _activeBatch = BatchSummary(
  id: 'batch-active',
  name: '2026.07.16 崇明东滩',
  createdAt: DateTime.utc(2026, 7, 16),
  totalFiles: 3672,
  analyzedCount: 2384,
  reviewCount: 1284,
  keepCount: 2012,
  discardCount: 376,
  pendingCopyCount: 0,
  copyState: 'idle',
);

class _BatchRepository implements BatchRepository {
  BatchSummary? active = _activeBatch;

  @override
  Future<BatchSummary?> current() async => active;

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async => BatchPage(items: active == null ? const [] : [active!], hasMore: false);

  @override
  Future<void> resume(String batchId) async {}

  @override
  Future<BatchOverview> overview() async => BatchOverview(active: active);
}

void main() {
  test('load clears a stale current batch after the box reports no active batch', () async {
    final repository = _BatchRepository();
    final cubit = BatchListCubit(repository);
    addTearDown(cubit.close);

    await cubit.load();
    expect(cubit.state.current, _activeBatch);

    repository.active = null;
    await cubit.load();

    expect(cubit.state.current, isNull);
    expect(cubit.state.items, isEmpty);
  });
}
