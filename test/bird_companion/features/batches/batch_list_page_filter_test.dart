import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four UI filters produce different local result sets', () async {
    final source = [
      _batch('running', state: 'analyzing'),
      _batch('review', state: 'ready_to_review', pending: 3),
      _batch('failed', state: 'failed'),
      _batch('completed', state: 'completed'),
    ];
    final expectations = <String?, List<String>>{
      null: ['running', 'review', 'failed', 'completed'],
      'in_progress': ['running'],
      'review': ['review'],
      'failed': ['failed'],
    };

    for (final entry in expectations.entries) {
      final repository = _PagedBatchRepository({
        null: BatchPage(items: source, hasMore: false),
      });
      final cubit = BatchListCubit(repository);
      await cubit.load(filter: entry.key);

      expect(cubit.state.filter, entry.key);
      expect(cubit.state.items.map((item) => item.id), entry.value);
      expect(repository.requestedStates, [entry.key]);
      await cubit.close();
    }
  });

  test('ignored server filter scans later cursors until a page is filled', () async {
    final repository = _PagedBatchRepository({
      null: BatchPage(
        items: [
          _batch('completed-1', state: 'completed'),
          _batch('running-1', state: 'processing'),
        ],
        hasMore: true,
        nextCursor: 'cursor-2',
      ),
      'cursor-2': BatchPage(
        items: [
          _batch('failed-1', state: 'failed'),
          _batch('review-1', state: 'ready_to_review', pending: 2),
        ],
        hasMore: true,
        nextCursor: 'cursor-3',
      ),
      'cursor-3': BatchPage(
        items: [
          _batch('failed-2', copyState: 'failed'),
          _batch('unknown-1'),
        ],
        hasMore: false,
      ),
    });
    final cubit = BatchListCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(filter: 'failed');

    expect(cubit.state.items.map((item) => item.id), ['failed-1', 'failed-2']);
    expect(cubit.state.hasMore, isFalse);
    expect(repository.requestedCursors, [null, 'cursor-2', 'cursor-3']);
    expect(repository.requestedStates, ['failed', 'failed', 'failed']);
  });

  test('filtered loadMore keeps scanning and deduplicates matching records', () async {
    final repository = _PagedBatchRepository({
      null: BatchPage(
        items: [
          _batch('review-1', state: 'ready_to_review', pending: 2),
          _batch('completed-1', state: 'completed'),
        ],
        hasMore: true,
        nextCursor: 'cursor-2',
      ),
      'cursor-2': BatchPage(
        items: [
          _batch('review-2', pending: 1),
          _batch('completed-2', state: 'completed'),
        ],
        hasMore: true,
        nextCursor: 'cursor-3',
      ),
      'cursor-3': BatchPage(
        items: [
          _batch('completed-3', state: 'completed'),
          _batch('review-3', state: 'pending_review', pending: 4),
        ],
        hasMore: true,
        nextCursor: 'cursor-4',
      ),
      'cursor-4': BatchPage(
        items: [
          _batch('review-3', state: 'pending_review', pending: 4),
          _batch('review-4', state: 'review', pending: 5),
        ],
        hasMore: false,
      ),
    });
    final cubit = BatchListCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(filter: 'review');
    expect(cubit.state.items.map((item) => item.id), ['review-1', 'review-2']);
    expect(cubit.state.nextCursor, 'cursor-3');
    expect(cubit.state.hasMore, isTrue);

    await cubit.loadMore();
    expect(
      cubit.state.items.map((item) => item.id),
      ['review-1', 'review-2', 'review-3', 'review-4'],
    );
    expect(cubit.state.hasMore, isFalse);
    expect(repository.requestedCursors, [null, 'cursor-2', 'cursor-3', 'cursor-4']);
  });

  test('repeated server cursor terminates filtered pagination', () async {
    final repository = _PagedBatchRepository({
      null: BatchPage(
        items: [_batch('completed-1', state: 'completed')],
        hasMore: true,
        nextCursor: 'same-cursor',
      ),
      'same-cursor': BatchPage(
        items: [_batch('completed-2', state: 'completed')],
        hasMore: true,
        nextCursor: 'same-cursor',
      ),
    });
    final cubit = BatchListCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(filter: 'failed');

    expect(cubit.state.items, isEmpty);
    expect(cubit.state.hasMore, isFalse);
    expect(repository.requestedCursors, [null, 'same-cursor']);
  });

  test('optimistic batch counts immediately leave an active review filter', () async {
    final bus = AppDataChangeBus();
    final repository = _PagedBatchRepository({
      null: BatchPage(
        items: [_batch('last-pending', pending: 1)],
        hasMore: false,
      ),
    });
    final cubit = BatchListCubit(repository, null, bus);
    addTearDown(cubit.close);
    addTearDown(bus.dispose);
    await cubit.load(filter: 'review');
    expect(cubit.state.items.single.id, 'last-pending');

    bus.publishChange(
      const BatchReviewDecisionChanged(
        deviceId: 'box-1',
        projectId: 'last-pending',
        transitions: [
          ReviewStateTransition(
            fileId: 'photo-1',
            before: KeepState.pending,
            after: KeepState.keep,
          ),
        ],
        queued: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.items, isEmpty);

    // A manual reload still sees the server's stale pending=1 snapshot. The
    // local filter must continue using the optimistic pending=0 count.
    await cubit.load(filter: 'review');
    expect(cubit.state.items, isEmpty);
  });
}

class _PagedBatchRepository implements BatchRepository {
  _PagedBatchRepository(this.pages);

  final Map<String?, BatchPage> pages;
  final List<String?> requestedStates = [];
  final List<String?> requestedCursors = [];

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    requestedStates.add(state);
    requestedCursors.add(cursor);
    return pages[cursor] ?? const BatchPage(items: [], hasMore: false);
  }

  @override
  Future<BatchSummary?> current() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BatchSummary _batch(
  String id, {
  String? state,
  String copyState = 'unknown',
  int pending = 0,
}) => BatchSummary(
  id: id,
  name: id,
  createdAt: DateTime.utc(2026, 9, 14),
  totalFiles: 10,
  analyzedCount: 10,
  reviewCount: pending,
  keepCount: 10 - pending,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: copyState,
  state: state,
);
