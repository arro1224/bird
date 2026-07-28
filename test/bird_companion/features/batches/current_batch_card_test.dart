import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/features/batches/presentation/batch_list_page.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/current_batch_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('当前批次卡显示统计并反馈正在打开照片主页', (tester) async {
    var openCount = 0;
    final batch = BatchSummary(
      id: 'batch-1',
      name: '崇明东滩',
      createdAt: DateTime(2026, 7, 16),
      totalFiles: 1200,
      analyzedCount: 1200,
      reviewCount: 428,
      keepCount: 612,
      discardCount: 160,
      pendingCopyCount: 0,
      copyState: 'idle',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentBatchCard(
              batch: batch,
              actionLabel: '继续挑选',
              onOpen: () => openCount += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('428'), findsOneWidget);
    expect(find.text('612'), findsOneWidget);
    expect(find.text('继续挑选'), findsOneWidget);
    await tester.tap(find.text('继续挑选'));
    expect(openCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentBatchCard(
              batch: batch,
              actionLabel: '继续挑选',
              loading: true,
              onOpen: () => openCount += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('正在打开照片…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('正在打开照片…'));
    expect(openCount, 1);
  });

  test('继续挑选只携带当前批次上下文，不恢复连拍位置', () {
    final batch = BatchSummary(
      id: 'batch-current',
      name: '本次拍摄',
      createdAt: DateTime(2026, 7, 28),
      totalFiles: 1200,
      analyzedCount: 1200,
      reviewCount: 428,
      keepCount: 612,
      discardCount: 160,
      pendingCopyCount: 0,
      copyState: 'idle',
    );

    final args = currentBatchGalleryArgs(batch);

    expect(args.batchId, 'batch-current');
    expect(args.totalCount, 1200);
    expect(args.reviewContext?.batchId, 'batch-current');
    expect(args.reviewContext?.sceneId, isNull);
    expect(args.reviewContext?.groupId, isNull);
    expect(args.reviewContext?.photoIds, isEmpty);
    expect(args.restoreSavedView, isFalse);
    expect(args.initialQuery.cursor, isNull);
    expect(args.initialQuery.sort, 'captured_at_desc');
    expect(args.initialQuery.activeLabels, isEmpty);
  });
}
