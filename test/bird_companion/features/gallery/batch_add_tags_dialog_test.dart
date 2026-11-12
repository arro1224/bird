import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/features/gallery/presentation/widgets/batch_add_tags_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('标签读取失败可重试，确认没有标签后只显示输入框', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BatchAddTagsDialog(
          loadPhotos: () async {
            if (++attempts == 1) throw StateError('offline');
            return const [
              PhotoSummary(
                id: 'photo-1',
                filename: 'photo-1.jpg',
                format: 'JPEG',
                preview: PreviewRef(),
                analysisState: AnalysisState.completed,
                version: 1,
              ),
            ];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final apply = find.widgetWithText(FilledButton, '应用');
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('所选照片已有标签'), findsNothing);
    expect(find.byType(Chip), findsNothing);
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '水鸟');
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  });
}
