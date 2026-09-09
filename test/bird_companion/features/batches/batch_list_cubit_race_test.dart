import 'dart:async';

import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('older batch load cannot overwrite a newer generation', () async {
    final repository = _ControllableBatchRepository();
    final cubit = BatchListCubit(repository);
    addTearDown(cubit.close);

    final older = cubit.load(filter: 'older');
    final newer = cubit.load(filter: 'newer');

    repository.completePage(1, _page(_batch('newer-project')));
    repository.completeCurrent(1, _batch('newer-project'));
    await newer;

    repository.completePage(0, _page(_batch('older-project')));
    repository.completeCurrent(0, _batch('older-project'));
    await older;

    expect(cubit.state.filter, 'newer');
    expect(cubit.state.current?.id, 'newer-project');
    expect(cubit.state.items.single.id, 'newer-project');
  });
}

class _ControllableBatchRepository implements BatchRepository {
  final _pages = <Completer<BatchPage>>[];
  final _currents = <Completer<BatchSummary?>>[];

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) {
    final completer = Completer<BatchPage>();
    _pages.add(completer);
    return completer.future;
  }

  @override
  Future<BatchSummary?> current() {
    final completer = Completer<BatchSummary?>();
    _currents.add(completer);
    return completer.future;
  }

  void completePage(int index, BatchPage value) => _pages[index].complete(value);

  void completeCurrent(int index, BatchSummary value) =>
      _currents[index].complete(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchPage _page(BatchSummary batch) =>
    BatchPage(items: [batch], hasMore: false);

BatchSummary _batch(String id) => BatchSummary(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 9, 7),
  totalFiles: 10,
  analyzedCount: 10,
  reviewCount: 10,
  keepCount: 0,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: 'idle',
);
