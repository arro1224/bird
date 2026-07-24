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
  Future<ReviewSaveResult> save(UserDecision value) async => const ReviewSaveResult();
}
