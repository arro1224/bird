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
}
