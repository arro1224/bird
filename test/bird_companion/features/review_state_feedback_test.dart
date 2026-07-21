import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/comparison_review_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连拍照片保存后立即回写当前照片状态', () async {
    final photo = _photo('left', 'keep');
    final group = BirdGroup(
      id: 'group-1',
      type: 'burst',
      representativeFileId: photo.id,
      memberFileIds: [photo.id],
      members: [photo],
    );
    final repository = _FakeReviewRepository(groupItems: [group], details: {'left': _detail(photo)});
    final cubit = GroupReviewCubit(repository);

    await cubit.load('batch-1');
    await cubit.markFile(group, 'left', KeepState.featured);

    expect(cubit.state.groups.single.members.single.keepState, 'featured');
    expect(cubit.state.actingGroupId, isNull);
    await cubit.close();
  });

  test('照片对比保存后立即更新按钮所依赖的状态', () async {
    final left = _photo('left', 'keep');
    final right = _photo('right', 'pending');
    final repository = _FakeReviewRepository(
      details: {'left': _detail(left), 'right': _detail(right)},
    );
    final cubit = ComparisonReviewCubit(repository);

    await cubit.load(['left', 'right']);
    await cubit.mark('right', KeepState.featured);

    final updated = cubit.state.items.singleWhere((item) => item.photo.summary.id == 'right');
    expect(updated.photo.summary.keepState, 'featured');
    expect(updated.decision?.keepState, KeepState.featured);
    expect(cubit.state.savingId, isNull);
    await cubit.close();
  });
}

PhotoSummary _photo(String id, String keepState) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'jpg',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  keepState: keepState,
);

ReviewDetail _detail(PhotoSummary photo) => ReviewDetail(
  photo: PhotoDetail(summary: photo),
  decision: UserDecision(fileId: photo.id, keepState: KeepStateWireValue.fromWire(photo.keepState)),
);

class _FakeReviewRepository implements ReviewRepository {
  _FakeReviewRepository({this.groupItems = const [], this.details = const {}});

  final List<BirdGroup> groupItems;
  final Map<String, ReviewDetail> details;

  @override
  Future<ReviewDetail> detail(String fileId) async => details[fileId]!;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => groupItems;

  @override
  Future<ReviewSaveResult> save(UserDecision value) async => const ReviewSaveResult();
}
