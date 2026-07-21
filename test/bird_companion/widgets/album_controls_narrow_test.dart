import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/filter_sheet.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/selection_action_bar.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> setNarrowView(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('照片筛选抽屉在 320dp 宽度可滚动且不溢出', (tester) async {
    await setNarrowView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterSheet(initial: const PhotoQuery(), onApply: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('筛选照片'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('应用筛选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量操作面板在 320dp 宽度保留全部现有动作', (tester) async {
    await setNarrowView(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SelectionActionBar(
              count: 12,
              busy: false,
              onAction: (_) {},
              onAddTags: () {},
              onRemoveTags: () {},
              onClear: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认保留'), findsOneWidget);
    expect(find.text('确认弃用'), findsOneWidget);
    expect(find.text('添加标签'), findsOneWidget);
    expect(find.text('更多操作'), findsOneWidget);
    expect(find.text('确认操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前批次主卡在 320dp 宽度不溢出', (tester) async {
    await setNarrowView(tester);
    final batch = BatchSummary(
      id: 'batch-1',
      name: '2026.07.16 崇明东滩超长批次名称',
      createdAt: DateTime(2026, 7, 16),
      totalFiles: 3672,
      analyzedCount: 2384,
      reviewCount: 1284,
      keepCount: 2012,
      discardCount: 376,
      pendingCopyCount: 0,
      copyState: 'pending',
      sceneCount: 4,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentBatchCard(batch: batch, onOpen: () {}, onBrowseScenes: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('进入本次拍摄'), findsOneWidget);
    expect(find.text('按场景浏览 · 4 个'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
