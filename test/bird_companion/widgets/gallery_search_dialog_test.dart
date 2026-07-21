import 'package:aves/bird_companion/features/gallery/presentation/widgets/gallery_search_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('搜索弹窗提交后安全关闭并返回输入内容', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async => result = await showDialog<String>(
                context: context,
                builder: (_) => const GallerySearchDialog(initialValue: '白鹭'),
              ),
              child: const Text('打开搜索'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    expect(find.text('白鹭'), findsOneWidget);

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(result, '白鹭');
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索弹窗支持清空后提交', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async => result = await showDialog<String>(
                context: context,
                builder: (_) => const GallerySearchDialog(initialValue: '白鹭'),
              ),
              child: const Text('打开搜索'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(result, '');
    expect(tester.takeException(), isNull);
  });
}
