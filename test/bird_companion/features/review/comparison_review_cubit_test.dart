import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('重复调整单张状态不会改写另一张照片', () async {
    final repository = _ComparisonRepository({
      'left': _detail('left'),
      'right': _detail('right'),
    });
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.mark('left', KeepState.keep);
    expect(_states(cubit), [KeepState.keep, KeepState.pending]);

    await cubit.mark('left', KeepState.discard);
    expect(_states(cubit), [KeepState.discard, KeepState.pending]);

    await cubit.mark('right', KeepState.keep);
    expect(_states(cubit), [KeepState.discard, KeepState.keep]);
    expect(cubit.state.message, '照片状态已更新');
    expect(cubit.state.messageIsError, isFalse);
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

    expect(_states(cubit), [KeepState.pending, KeepState.featured]);
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

  test('comparison limits a larger candidate list to the top two photos', () async {
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
      ['first', 'second'],
    );

    await cubit.keepAll();

    expect(
      _states(cubit),
      [KeepState.keep, KeepState.keep],
    );
    expect(cubit.state.message, '已保留全部对比照片');
  });

  test('keeping one comparison photo only affects the two loaded candidates', () async {
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
      [KeepState.pending, KeepState.keep],
    );
  });

  test('version conflict keeps the current comparison and emits a Chinese error message', () async {
    final repository = _ComparisonRepository(
      {
        'left': _detail('left'),
        'right': _detail('right'),
      },
      saveResult: const ReviewSaveResult(
        conflict: true,
        message: 'The photo decision changed on the box. Reload before saving.',
      ),
    );
    final cubit = ComparisonReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(const ['left', 'right']);
    await cubit.mark('left', KeepState.keep);

    expect(_states(cubit), [KeepState.pending, KeepState.pending]);
    expect(cubit.state.message, '照片状态已在盒子端更新，请重新加载后再试。');
    expect(cubit.state.messageIsError, isTrue);
  });
}

List<KeepState> _states(ComparisonReviewCubit cubit) => cubit.state.items
    .map(
      (item) => item.decision?.keepState ?? KeepStateWireValue.fromWire(item.photo.summary.keepState),
    )
    .toList();

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
  _ComparisonRepository(this.details, {this.saveResult = const ReviewSaveResult()});

  final Map<String, ReviewDetail> details;
  final ReviewSaveResult saveResult;

  @override
  Future<ReviewDetail> detail(String fileId) async => details[fileId]!;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async => saveResult;
}
