import 'package:aves/bird_companion/features/review/presentation/widgets/tag_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('没有已有标签时隐藏展示区，可从键盘保存第一组标签', (tester) async {
    List<String>? savedTags;
    await _openSheet(tester, tags: const [], onSaved: (tags) => savedTags = tags);
    expect(find.text('已有标签'), findsNothing);
    expect(find.byType(Chip), findsNothing);

    await tester.enterText(find.byType(TextField), '， , ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TagEditorSheet), findsOneWidget);
    expect(savedTags, isNull);

    await tester.enterText(find.byType(TextField), '水鸟， 水鸟, 晨拍');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(savedTags, ['水鸟', '晨拍']);
  });

  testWidgets('小屏打开键盘时，多行已有标签可滚动且仍可保存', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    List<String>? savedTags;
    final tags = List.generate(24, (index) => '已有标签 ${index + 1}');
    await _openSheet(tester, tags: tags, onSaved: (tags) => savedTags = tags);
    expect(tester.getTopLeft(find.text(tags.last)).dy, greaterThan(tester.getTopLeft(find.text(tags.first)).dy));

    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '水鸟');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存标签'));
    await tester.pumpAndSettle();

    expect(savedTags, ['水鸟']);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSheet(
  WidgetTester tester, {
  required List<String> tags,
  required ValueChanged<List<String>?> onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              onSaved(
                await showModalBottomSheet<List<String>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TagEditorSheet(existingTags: tags),
                ),
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
}
