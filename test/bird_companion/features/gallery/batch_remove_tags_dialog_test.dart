import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/domain/batch_tag_removal.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/batch_remove_tags_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PhotoSummary _photo(String id, List<String> tags) => PhotoSummary(id: id, filename: '$id.jpg', format: 'JPEG', preview: const PreviewRef(), analysisState: AnalysisState.completed, userTags: tags);

void main() {
  testWidgets('shows deduplicated detail tags; removal needs confirmation and can be undone', (tester) async {
    final loaded = Completer<List<PhotoSummary>>();
    BatchTagRemoval? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showDialog<BatchTagRemoval>(
                context: context,
                builder: (_) => BatchRemoveTagsDialog(loadPhotos: () => loaded.future),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loaded.complete([
      _photo('p1', ['湿地', '水鸟']),
      _photo('p2', ['湿地', '晨拍']),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(InputChip, '湿地'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认删除')).onPressed, isNull);
    await tester.tap(find.byTooltip('删除标签：水鸟'));
    await tester.pump();
    expect(find.widgetWithText(InputChip, '水鸟'), findsNothing);
    expect(result, isNull);
    await tester.tap(find.text('撤销选择'));
    await tester.pump();
    expect(find.widgetWithText(InputChip, '水鸟'), findsOneWidget);
    await tester.tap(find.byTooltip('删除标签：水鸟'));
    await tester.pump();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(result!.tags, ['水鸟']);
    expect(result!.groups.single.ids, ['p1']);
  });

  testWidgets('empty tags disable deletion', (tester) async {
    await tester.pumpWidget(MaterialApp(home: BatchRemoveTagsDialog(loadPhotos: () async => [_photo('p1', [])])));
    await tester.pumpAndSettle();
    expect(find.text('所选照片没有可删除的人工标签。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('failed detail load offers retry and never enables deletion', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BatchRemoveTagsDialog(
          loadPhotos: () async {
            if (++attempts == 1) throw StateError('offline');
            return [
              _photo('p1', ['水鸟']),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '水鸟'), findsOneWidget);
  });

  test('removal and undo groups preserve each photo original tags', () {
    final plan = BatchTagRemoval(
      photos: [
        _photo('p1', ['湿地', '水鸟']),
        _photo('p2', ['湿地']),
        _photo('p3', ['晨拍']),
      ],
      tags: ['水鸟', '湿地'],
    );
    expect(plan.groups.map((g) => g.ids), [
      ['p1'],
      ['p2'],
    ]);
    expect(plan.groups[0].tags, ['水鸟', '湿地']);
    expect(plan.groups[1].tags, ['湿地']);
  });
}
