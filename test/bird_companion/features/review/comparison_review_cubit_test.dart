import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('左右照片的保留状态互斥', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.mark('left', KeepState.keep);
    expect(_states(cubit), [KeepState.keep, KeepState.discard]);

    await cubit.mark('right', KeepState.keep);
    expect(_states(cubit), [KeepState.discard, KeepState.keep]);
    expect(_states(cubit).where((state) => state.isRetained), hasLength(1));
  });

  test('将保留照片设为精选后仍只有该照片处于保留状态', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.mark('right', KeepState.keep);
    await cubit.mark('right', KeepState.featured);

    expect(_states(cubit), [KeepState.discard, KeepState.featured]);
    expect(_states(cubit).where((state) => state.isRetained), hasLength(1));
  });

  test('可以同时保留两张照片', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.keepBoth();

    expect(_states(cubit), [KeepState.keep, KeepState.keep]);
    expect(cubit.state.message, '已保留两张照片');
  });

  test('保留两张时不会取消已有的精选状态', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.mark('left', KeepState.featured);
    await cubit.keepBoth();

    expect(_states(cubit), [KeepState.featured, KeepState.keep]);
  });

  test('保留两张后设置精选仍然保留两张', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.keepBoth();
    await cubit.mark('left', KeepState.featured);

    expect(_states(cubit), [KeepState.featured, KeepState.keep]);
    expect(_states(cubit).where((state) => state.isRetained), hasLength(2));
  });

  test('保留两张时切换精选不会产生两张精选照片', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.keepBoth();
    await cubit.mark('left', KeepState.featured);
    await cubit.mark('right', KeepState.featured);

    expect(_states(cubit), [KeepState.keep, KeepState.featured]);
    expect(_states(cubit).where((state) => state.isRetained), hasLength(2));
  });

  test('three-photo comparison loads Top 3 and can retain all', () async {
    final repository = _ComparisonRepository({
      'first': _detail('first'),
      'second': _detail('second'),
      'third': _detail('third'),
      'fourth': _detail('fourth'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['first', 'second', 'third', 'fourth']);

    expect(
      cubit.state.items.map((item) => item.photo.summary.id),
      ['first', 'second', 'third'],
    );

    await cubit.keepAll();

    expect(
      _states(cubit),
      [KeepState.keep, KeepState.keep, KeepState.keep],
    );
    expect(cubit.state.message, '已保留全部对比照片');
  });

  test('keeping one of three comparison photos discards the other two', () async {
    final repository = _ComparisonRepository({
      'first': _detail('first'),
      'second': _detail('second'),
      'third': _detail('third'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['first', 'second', 'third']);
    await cubit.mark('second', KeepState.keep);

    expect(
      _states(cubit),
      [KeepState.discard, KeepState.keep, KeepState.discard],
    );
  });
}

List<KeepState> _states(ComparisonReviewCubit cubit) => cubit.state.items.map((item) => item.decision!.keepState).toList();

ReviewDetail _detail(String id) => ReviewDetail(
  photo: PhotoDetail(
    summary: PhotoSummary(
      id: id,
      filename: '$id.jpg',
      format: 'JPEG',
      preview: const PreviewRef(),
      analysisState: AnalysisState.completed,
      keepState: 'pending',
    ),
  ),
);

class _ComparisonRepository implements ReviewRepository {
  _ComparisonRepository(this.details);

  final Map<String, ReviewDetail> details;

  @override
  Future<ReviewDetail> detail(String fileId) async => details[fileId]!;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async => const ReviewSaveResult();
}
