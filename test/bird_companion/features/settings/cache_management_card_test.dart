import 'package:aves/bird_companion/features/settings/presentation/widgets/cache_management_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('图片缓存、相册元数据和待同步操作具有独立说明', (tester) async {
    var imageCleared = false;
    var albumCleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CacheManagementCard(
            imageBytes: 2048,
            albumBytes: 4096,
            onClearImages: () => imageCleared = true,
            onClearAlbumData: () => albumCleared = true,
          ),
        ),
      ),
    );

    expect(find.text('照片预览缓存'), findsOneWidget);
    expect(find.text('相册离线信息'), findsOneWidget);
    expect(find.textContaining('待同步修改单独保存'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '清理').first);
    await tester.tap(find.widgetWithText(TextButton, '清理').last);
    expect(imageCleared, isTrue);
    expect(albumCleared, isTrue);
  });
}
