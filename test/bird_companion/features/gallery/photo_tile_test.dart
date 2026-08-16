import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('相册首页的紧凑照片卡片显示详情评分', (tester) async {
    const photo = PhotoSummary(
      id: 'photo-1',
      filename: 'photo-1.jpg',
      format: 'JPEG',
      preview: PreviewRef(),
      analysisState: AnalysisState.completed,
      rating: RatingResult(totalScore: 4.8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: PhotoTile(
              photo: photo,
              selected: false,
              compact: true,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('4.8'), findsOneWidget);
    expect(tester.widget<Text>(find.text('4.8')).style?.fontSize, 16);
  });

  final statusCases = <({String state, IconData icon, Color color})>[
    (state: 'keep', icon: Icons.circle, color: AppColors.keep),
    (state: 'pending', icon: Icons.circle, color: AppColors.pending),
    (state: 'discard', icon: Icons.circle, color: AppColors.danger),
    (state: 'featured', icon: Icons.star_rounded, color: AppColors.featured),
  ];

  for (final statusCase in statusCases) {
    testWidgets('批量 ${statusCase.state} 后显示对应图标和颜色', (tester) async {
      final photo = PhotoSummary(
        id: '${statusCase.state}-photo',
        filename: '${statusCase.state}-photo.jpg',
        format: 'JPEG',
        preview: const PreviewRef(),
        analysisState: AnalysisState.lowConfidence,
        keepState: statusCase.state,
        isRecommended: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 160,
              child: PhotoTile(
                photo: photo,
                selected: false,
                compact: true,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      );

      final status = tester.widget<Icon>(
        find.byKey(ValueKey('photo-status-${statusCase.state}')),
      );
      expect(status.icon, statusCase.icon);
      expect(status.color, statusCase.color);
    });
  }

  testWidgets('rating and status overlays can be hidden without hiding selection', (tester) async {
    const photo = PhotoSummary(
      id: 'photo-overlay',
      filename: 'photo-overlay.jpg',
      format: 'JPEG',
      preview: PreviewRef(),
      analysisState: AnalysisState.completed,
      keepState: 'discard',
      rating: RatingResult(totalScore: 4.7),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: PhotoTile(
              photo: photo,
              selected: true,
              showRatingOverlay: false,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('4.7'), findsNothing);
    expect(find.byKey(const ValueKey('photo-status-discard')), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
