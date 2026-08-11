import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/group_review_comparison_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('照片模块 B0 基线契约', () {
    test('照片主链路路由保持稳定', () {
      expect(BirdRoutes.gallery, '/gallery');
      expect(BirdRoutes.batches, '/batches');
      expect(BirdRoutes.scenes, '/scenes');
      expect(BirdRoutes.groupReview, '/group-review');
      expect(BirdRoutes.photoDetail, '/photo-detail');
      expect(BirdRoutes.comparisonReview, '/comparison-review');
    });

    test('照片主链路接口与盒子协议一致', () {
      expect(ApiEndpoints.currentBatch, '/api/v1/projects/current');
      expect(ApiEndpoints.batches, '/api/v1/projects');
      expect(ApiEndpoints.photos, '/api/v1/projects/{batchId}/files');
      expect(ApiEndpoints.scenes, '/api/v1/projects/{batchId}/scenes');
      expect(ApiEndpoints.groups, '/api/v1/projects/{batchId}/groups');
      expect(ApiEndpoints.photoDetail, '/api/v1/files/{fileId}');
      expect(ApiEndpoints.photoHistory, '/api/v1/files/{fileId}/history');
      expect(ApiEndpoints.photoDecision, '/api/v1/files/{fileId}/decision');
      expect(ApiEndpoints.batchPhotoOperation, '/api/v1/projects/{batchId}/files/actions');
    });

    test('照片筛选使用固定线值并可序列化恢复', () {
      const query = PhotoQuery(
        sort: 'score_desc',
        search: '翠鸟',
        minScore: 4,
        minConfidence: .85,
        tags: ['湿地'],
        keepState: 'pending',
        analysisState: 'completed',
        clarityState: 'clear',
        recognitionState: 'recognized',
        sceneId: 'scene-01',
      );

      final restored = PhotoQuery.fromJson(query.toJson());

      expect(restored.toJson(), {
        'page_size': 60,
        'sort': 'score_desc',
        'search': '翠鸟',
        'min_score': 4,
        'min_confidence': .85,
        'tags': ['湿地'],
        'keep_state': 'pending',
        'analysis_state': 'completed',
        'clarity_state': 'clear',
        'recognition_state': 'recognized',
        'scene_id': 'scene-01',
      });
      expect(restored.parameters, {
        'page_size': 60,
        'sort': 'score_desc',
        'keep_state': 'pending',
        'analysis_state': 'completed',
        'scene_id': 'scene-01',
      });
    });

    testWidgets('更多筛选条件默认折叠且可以展开', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilterSheet(
              initial: const PhotoQuery(),
              onApply: (_) {},
            ),
          ),
        ),
      );

      final moreConditions = find.byKey(const ValueKey('photo-filter-more-conditions'));
      await tester.scrollUntilVisible(
        moreConditions,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(moreConditions, findsOneWidget);
      expect(find.text('文件名、鸟种或标签'), findsNothing);

      await tester.tap(moreConditions);
      await tester.pumpAndSettle();

      expect(find.text('文件名、鸟种或标签'), findsOneWidget);
    });

    testWidgets('连拍页新增的照片对比按钮保持可用', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupReviewComparisonAction(
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byKey(groupReviewComparisonActionKey), findsOneWidget);
      expect(find.text('对比最推荐的 2 张'), findsOneWidget);

      await tester.tap(find.byKey(groupReviewComparisonActionKey));
      expect(tapped, isTrue);
    });
  });
}
