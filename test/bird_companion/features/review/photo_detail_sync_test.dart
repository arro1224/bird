import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_cubit.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/rating_reason_panel.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/recognition_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('照片详情修改同步', () {
    test('保存后即使设备暂时返回旧详情也保留刚修改的决定', () async {
      final repository = _StaleReviewRepository(_originalDetail());
      final cubit = PhotoDetailCubit(
        repository,
        null,
        null,
        'project-7',
      );
      addTearDown(cubit.close);

      await cubit.load('photo-1');
      final changed = UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.keep,
        userSpeciesId: 'oriental',
        userSpecies: '东方大苇莺',
        userScore: 4.2,
        userTags: const ['湿地'],
        updatedAt: DateTime(2026, 7, 23),
        version: 1,
      );

      await cubit.save(changed);

      expect(cubit.state.detail?.decision?.userSpecies, '东方大苇莺');
      expect(cubit.state.detail?.decision?.userScore, 4.2);
      expect(cubit.state.detail?.decision?.userTags, ['湿地']);
      expect(cubit.state.detail?.photo.summary.keepState, 'keep');
      expect(cubit.state.saving, isFalse);
      expect(repository.savedProjectId, 'project-7');
    });

    test('标签保存可以提供专用的成功提示', () async {
      final cubit = PhotoDetailCubit(_StaleReviewRepository(_originalDetail()));
      addTearDown(cubit.close);
      await cubit.load('photo-1');

      await cubit.save(
        const UserDecision(
          fileId: 'photo-1',
          keepState: KeepState.pending,
          userTags: ['湿地'],
        ),
        successMessage: '标签添加成功',
      );

      expect(cubit.state.message, '标签添加成功');
      expect(cubit.state.messageIsError, isFalse);
    });

    test('详情加载失败时保留异常对象而不是暴露原始异常文本', () async {
      final repository = _FailingReviewRepository();
      final cubit = PhotoDetailCubit(repository);
      addTearDown(cubit.close);

      await cubit.load('photo-1');

      expect(cubit.state.loading, isFalse);
      expect(cubit.state.detail, isNull);
      expect(cubit.state.error, isA<ApiException>());
      expect(cubit.state.message, isNull);

      final message = UserMessageMapper.fromError(cubit.state.error!);
      expect(message.title, '照片详情不可用');
      expect(message.message, isNot(contains('Unknown mock endpoint')));
    });

    test('409 conflict keeps local choice until user reloads remote result', () async {
      final repository = _ConflictReviewRepository();
      final cubit = PhotoDetailCubit(
        repository,
        null,
        null,
        'project-7',
      );
      addTearDown(cubit.close);
      await cubit.load('photo-1');
      const local = UserDecision(
        fileId: 'photo-1',
        keepState: KeepState.featured,
        version: 1,
      );

      await cubit.save(local);

      expect(cubit.state.conflict, isTrue);
      expect(cubit.state.pendingConflictDecision, local);
      expect(repository.savedProjectId, 'project-7');

      await cubit.useRemote('photo-1');

      expect(cubit.state.conflict, isFalse);
      expect(cubit.state.detail?.decision?.keepState, KeepState.discard);
      expect(cubit.state.detail?.decision?.version, 2);
    });

    testWidgets('详细鸟种指标优先显示用户保存的结果', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecognitionPanel(
              value: _recognition,
              currentSpeciesId: 'oriental',
              currentSpecies: '东方大苇莺',
            ),
          ),
        ),
      );

      final current = tester.widget<Text>(
        find.byKey(const ValueKey('recognition-current-species')),
      );
      expect(current.data, '东方大苇莺');
      expect(find.text('当前结果'), findsOneWidget);
    });

    testWidgets('详细评分指标优先显示用户保存的分数', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RatingReasonPanel(
              value: RatingResult(totalScore: 4.8),
              currentScore: 3.6,
            ),
          ),
        ),
      );

      final current = tester.widget<Text>(
        find.byKey(const ValueKey('rating-current-score')),
      );
      expect(current.data, '3.6');
    });
  });
}

const _recognition = RecognitionResult(
  candidates: [
    SpeciesCandidate(
      speciesId: 'other',
      name: '其他鸟类',
      confidence: .89,
    ),
    SpeciesCandidate(
      speciesId: 'oriental',
      name: '东方大苇莺',
      confidence: .11,
    ),
  ],
);

ReviewDetail _originalDetail() => ReviewDetail(
  photo: const PhotoDetail(
    summary: PhotoSummary(
      id: 'photo-1',
      filename: 'photo-1.jpg',
      format: 'JPEG',
      preview: PreviewRef(),
      analysisState: AnalysisState.completed,
      recognition: _recognition,
      rating: RatingResult(totalScore: 4.8),
      keepState: 'pending',
    ),
  ),
  decision: UserDecision(
    fileId: 'photo-1',
    keepState: KeepState.pending,
    userSpeciesId: 'other',
    userSpecies: '其他鸟类',
    userScore: 4.8,
    updatedAt: DateTime(2026, 7, 22),
    version: 1,
  ),
);

class _StaleReviewRepository implements ReviewRepository {
  _StaleReviewRepository(this.staleDetail);

  final ReviewDetail staleDetail;
  String? savedProjectId;

  @override
  Future<ReviewDetail> detail(String fileId) async => staleDetail;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async {
    savedProjectId = projectId;
    return const ReviewSaveResult();
  }
}

class _FailingReviewRepository implements ReviewRepository {
  @override
  Future<ReviewDetail> detail(String fileId) async {
    throw const ApiException(
      code: 'not_found',
      statusCode: 404,
      message: 'Unknown mock endpoint: /api/v1/files/photo-1',
    );
  }

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async => const ReviewSaveResult();
}

class _ConflictReviewRepository implements ReviewRepository {
  var reads = 0;
  String? savedProjectId;

  @override
  Future<ReviewDetail> detail(String fileId) async {
    reads++;
    final remote = reads > 1;
    return ReviewDetail(
      photo: PhotoDetail(
        summary: PhotoSummary(
          id: fileId,
          filename: '$fileId.jpg',
          format: 'JPEG',
          preview: const PreviewRef(),
          analysisState: AnalysisState.completed,
          keepState: remote ? 'discard' : 'pending',
          version: remote ? 2 : 1,
        ),
      ),
      decision: UserDecision(
        fileId: fileId,
        keepState: remote ? KeepState.discard : KeepState.pending,
        version: remote ? 2 : 1,
      ),
    );
  }

  @override
  Future<List<BirdGroup>> groups(
    String batchId, {
    String? sceneId,
  }) async => const [];

  @override
  Future<ReviewSaveResult> save(
    UserDecision value, {
    String? projectId,
  }) async {
    savedProjectId = projectId;
    return const ReviewSaveResult(
      conflict: true,
      message: '照片审阅结果已更新',
    );
  }
}
