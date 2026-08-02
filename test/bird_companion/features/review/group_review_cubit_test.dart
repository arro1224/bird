import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('整组操作保存每张照片并立即更新本地状态', () async {
    final group = _group();
    final repository = _GroupRepository(group);
    final cubit = GroupReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load('batch-1');
    await cubit.markGroup(group, KeepState.keep);

    expect(
      repository.saved.map((decision) => decision.fileId),
      ['first', 'second', 'third'],
    );
    expect(
      repository.saved.map((decision) => decision.version),
      [1, 2, 3],
    );
    expect(repository.projectIds, everyElement('batch-1'));
    expect(
      cubit.state.groups.single.members.map((photo) => photo.keepState),
      everyElement('keep'),
    );
    expect(cubit.state.message, '整组状态已更新');
    expect(cubit.state.actingGroupId, isNull);
  });

  test('整组操作部分失败时保留成功结果并提示重试', () async {
    final group = _group();
    final repository = _GroupRepository(
      group,
      failures: {'third'},
    );
    final cubit = GroupReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load('batch-1');
    await cubit.markGroup(group, KeepState.discard);

    expect(
      cubit.state.groups.single.members.map((photo) => photo.keepState),
      ['discard', 'discard', 'pending'],
    );
    expect(cubit.state.message, contains('已更新 2/3 张'));
    expect(cubit.state.message, contains('1 张失败，请重试'));
    expect(cubit.state.error, isNull);
    expect(cubit.state.actingGroupId, isNull);
  });

  test('整组操作全部失败时进入错误状态且解除忙碌状态', () async {
    final group = _group();
    final repository = _GroupRepository(
      group,
      failures: {'first', 'second', 'third'},
    );
    final cubit = GroupReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load('batch-1');
    await cubit.markGroup(group, KeepState.featured);

    expect(cubit.state.error, isA<StateError>());
    expect(cubit.state.actingGroupId, isNull);
    expect(
      cubit.state.groups.single.members.map((photo) => photo.keepState),
      everyElement('pending'),
    );
  });

  test('空分组不会发起保存请求', () async {
    const group = BirdGroup(
      id: 'empty-group',
      type: 'scene',
      representativeFileId: '',
      memberFileIds: [],
    );
    final repository = _GroupRepository(group);
    final cubit = GroupReviewCubit(repository);
    addTearDown(cubit.close);

    await cubit.load('batch-1');
    await cubit.markGroup(group, KeepState.keep);

    expect(repository.saved, isEmpty);
    expect(cubit.state.message, '本组没有可操作的照片');
    expect(cubit.state.actingGroupId, isNull);
  });
}

BirdGroup _group() => BirdGroup(
  id: 'group-1',
  type: 'burst',
  representativeFileId: 'first',
  memberFileIds: const ['first', 'second', 'third'],
  rankOrder: const ['first', 'second', 'third'],
  members: [
    _photo('first', 1),
    _photo('second', 2),
    _photo('third', 3),
  ],
);

PhotoSummary _photo(String id, int version) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: const PreviewRef(),
  analysisState: AnalysisState.completed,
  keepState: 'pending',
  version: version,
);

class _GroupRepository implements ReviewRepository {
  _GroupRepository(
    this.group, {
    this.failures = const {},
  });

  final BirdGroup group;
  final Set<String> failures;
  final List<UserDecision> saved = [];
  final List<String?> projectIds = [];

  @override
  Future<ReviewDetail> detail(String fileId) => throw UnimplementedError();

  @override
  Future<List<BirdGroup>> groups(
    String batchId, {
    String? sceneId,
  }) async => [group];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async {
    if (failures.contains(value.fileId)) {
      throw StateError('save failed: ${value.fileId}');
    }
    saved.add(value);
    projectIds.add(projectId);
    return const ReviewSaveResult();
  }
}
