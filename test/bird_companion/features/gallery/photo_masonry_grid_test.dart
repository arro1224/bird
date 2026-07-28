import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/photo_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('照片使用懒构建的三列统一高度照片流', (tester) async {
    var builtCount = 0;
    final photos = List.generate(
      1200,
      (index) => _photo(
        '$index',
        width: 100,
        height: switch (index % 3) {
          0 => 100,
          1 => 160,
          _ => 220,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: PhotoMasonryGrid(
                  photos: photos,
                  itemBuilder: (_, photo, _) {
                    builtCount += 1;
                    return ColoredBox(
                      key: ValueKey('tile-${photo.id}'),
                      color: Colors.green,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final first = tester.getRect(find.byKey(const ValueKey('tile-0')));
    final second = tester.getRect(find.byKey(const ValueKey('tile-1')));
    final third = tester.getRect(find.byKey(const ValueKey('tile-2')));

    expect(first.top, second.top);
    expect(second.top, third.top);
    expect(first.left, lessThan(second.left));
    expect(second.left, lessThan(third.left));
    expect(first.height, closeTo(second.height, .01));
    expect(second.height, closeTo(third.height, .01));
    expect(builtCount, lessThan(1200));
  });

  testWidgets('1200 张照片往返滚动 10 轮时仅保留视口附近组件', (
    tester,
  ) async {
    final photos = List.generate(
      1200,
      (index) => _photo(
        '$index',
        width: 100,
        height: 120 + index % 3 * 40,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              PhotoMasonryGrid(
                photos: photos,
                itemBuilder: (_, photo, _) => ColoredBox(
                  key: ValueKey('stress-tile-${photo.id}'),
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    int activeStressTiles() => find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'stress-tile-',
              ),
        )
        .evaluate()
        .length;

    final scrollable = find.byType(CustomScrollView);
    for (var round = 0; round < 10; round++) {
      await tester.drag(scrollable, const Offset(0, -2400));
      await tester.pump();
      expect(activeStressTiles(), lessThan(80));
      await tester.drag(scrollable, const Offset(0, 2400));
      await tester.pump();
      expect(activeStressTiles(), lessThan(80));
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('${width.toInt()} 逻辑像素宽度稳定显示三列', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final photos = List.generate(
        9,
        (index) => _photo('$index', width: 100, height: 150),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: PhotoMasonryGrid(
                    photos: photos,
                    itemBuilder: (_, photo, _) => ColoredBox(
                      key: ValueKey('width-tile-${photo.id}'),
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final first = tester.getRect(
        find.byKey(const ValueKey('width-tile-0')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('width-tile-1')),
      );
      final third = tester.getRect(
        find.byKey(const ValueKey('width-tile-2')),
      );

      expect(first.top, second.top);
      expect(second.top, third.top);
      expect(first.left, lessThan(second.left));
      expect(second.left, lessThan(third.left));
      expect(first.width, closeTo(second.width, .01));
      expect(second.width, closeTo(third.width, .01));
      expect(third.right, lessThanOrEqualTo(width - 12));
    });
  }
}

PhotoSummary _photo(
  String id, {
  required int width,
  required int height,
}) => PhotoSummary(
  id: id,
  filename: '$id.jpg',
  format: 'JPEG',
  preview: PreviewRef(width: width, height: height),
  analysisState: AnalysisState.completed,
);
