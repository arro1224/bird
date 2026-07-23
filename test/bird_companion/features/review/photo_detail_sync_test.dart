import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
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
      final cubit = PhotoDetailCubit(repository);
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

  @override
  Future<ReviewDetail> detail(String fileId) async => staleDetail;

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(UserDecision value) async => const ReviewSaveResult();
}
