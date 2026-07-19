import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_tile.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('图库缩略图按实际显示像素限制内存与磁盘解码尺寸', (tester) async {
    tester.view.physicalSize = const Size(300, 300);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final photo = PhotoSummary(
      id: 'photo-cache',
      filename: 'DSC_0001.NEF',
      format: 'NEF',
      preview: PreviewRef(thumbnailUri: Uri.parse('https://example.invalid/thumb.jpg'), width: 6000, height: 4000),
      analysisState: AnalysisState.completed,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: PhotoTile(photo: photo, selected: false, onTap: () {}, onLongPress: () {}),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.memCacheWidth, 300);
    expect(image.memCacheHeight, 300);
    expect(image.maxWidthDiskCache, 600);
    expect(image.maxHeightDiskCache, 600);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });
}
