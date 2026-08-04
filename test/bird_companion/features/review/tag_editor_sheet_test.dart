import 'package:aves/bird_companion/features/review/presentation/widgets/tag_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tag editor keeps its controller alive until the sheet closes', (
    tester,
  ) async {
    String? savedTags;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                savedTags = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const TagEditorSheet(initialTags: '湿地'),
                );
              },
              child: const Text('打开标签编辑'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开标签编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '湿地, 水鸟');
    await tester.tap(find.text('保存标签'));
    await tester.pumpAndSettle();

    expect(savedTags, '湿地, 水鸟');
    expect(tester.takeException(), isNull);
  });
}
