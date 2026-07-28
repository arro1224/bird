import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/review/data/review_repository_impl.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/group_review_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_photo_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('保存决定会合并到照片摘要供相册与连拍缓存复用', () {
    final merged = mergeReviewDecisionIntoPhotoJson(
      {
        'file_id': 'photo-1',
        'keep_state': 'pending',
        'user_tags': ['旧标签'],
        'rating': {'total_score': 3.1, 'quality_score': 7.8},
        'recognition': {
          'species_topn': [
            {
              'species_id': 'old',
              'name': '旧鸟种',
              'confidence': .72,
            },
          ],
          'low_confidence': true,
        },
      },
      const UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.featured,
        userScore: 4.6,
        userSpeciesId: 'new-species',
        userSpecies: '东方大苇莺',
        userTags: ['湿地', '复核完成'],
      ),
    );

    expect(merged['keep_state'], 'featured');
    expect(merged['user_tags'], ['湿地', '复核完成']);
    expect((merged['rating'] as Map)['total_score'], 4.6);
    expect((merged['rating'] as Map)['quality_score'], 7.8);
    final recognition = merged['recognition'] as Map;
    expect(recognition['low_confidence'], isFalse);
    expect(
      ((recognition['species_topn'] as List).first as Map)['species_id'],
      'new-species',
    );
    expect(
      ((recognition['species_topn'] as List).first as Map)['name'],
      '东方大苇莺',
    );
  });

  test('详情或对比保存后仍在栈中的连拍页会重新读取状态', () async {
    final bus = AppDataChangeBus();
    final repository = _ReloadingRepository(
      _groupWithState('pending'),
    );
    final cubit = GroupReviewCubit(repository, null, bus);
    addTearDown(cubit.close);
    addTearDown(bus.dispose);

    await cubit.load('batch-1');
    expect(_currentState(cubit), 'pending');
    expect(repository.groupReads, 1);

    repository.group = _groupWithState('featured');
    bus.publish(
      {AppDataResource.photos},
      reason: 'comparison_review_saved',
    );
    await _waitFor(() => repository.groupReads == 2);

    expect(_currentState(cubit), 'featured');

    repository.group = _groupWithState('keep');
    bus.publish(
      {AppDataResource.photos},
      reason: 'photo_review_saved',
    );
    await _waitFor(() => repository.groupReads == 3);
    expect(_currentState(cubit), 'keep');

    bus.publish(
      {AppDataResource.photos},
      reason: 'group_photo_review_saved',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repository.groupReads, 3);
  });

  test('未知接口错误不会把内部异常信息直接展示给用户', () {
    const internalMessage = 'ApiException(code: mock_failure, message: Unknown mock endpoint)';
    final message = UserMessageMapper.fromError(
      const ApiException(
        code: 'mock_failure',
        statusCode: 400,
        message: internalMessage,
      ),
    );

    expect(message.message, isNot(contains('ApiException')));
    expect(message.message, isNot(contains('Unknown mock endpoint')));
    expect(message.actionLabel, '重试');
  });

  testWidgets('照片对比优先显示用户保存后的评分', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 500,
            child: ComparisonPhotoPane(
              detail: ReviewDetail(
                photo: PhotoDetail(
                  summary: PhotoSummary(
                    id: 'photo-1',
                    filename: 'photo-1.jpg',
                    format: 'JPEG',
                    preview: PreviewRef(),
                    analysisState: AnalysisState.completed,
                    rating: RatingResult(totalScore: 4.8),
                  ),
                ),
                decision: UserDecision(
                  fileId: 'photo-1',
                  keepState: KeepState.keep,
                  userScore: 3.6,
                ),
              ),
              rank: 0,
              saving: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('3.6'), findsOneWidget);
    expect(find.text('4.8'), findsNothing);
  });
}

String? _currentState(GroupReviewCubit cubit) => cubit.state.groups.single.members.single.keepState;

BirdGroup _groupWithState(String keepState) => BirdGroup(
  id: 'group-1',
  type: 'burst',
  representativeFileId: 'photo-1',
  memberFileIds: const ['photo-1'],
  rankOrder: const ['photo-1'],
  members: [
    PhotoSummary(
      id: 'photo-1',
      filename: 'photo-1.jpg',
      format: 'JPEG',
      preview: const PreviewRef(),
      analysisState: AnalysisState.completed,
      keepState: keepState,
    ),
  ],
);

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for asynchronous refresh.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _ReloadingRepository implements ReviewRepository {
  _ReloadingRepository(this.group);

  BirdGroup group;
  int groupReads = 0;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async {
    groupReads += 1;
    return [group];
  }

  @override
  Future<ReviewDetail> detail(String fileId) {
    throw UnimplementedError();
  }

  @override
  Future<ReviewSaveResult> save(UserDecision value) {
    throw UnimplementedError();
  }
}
