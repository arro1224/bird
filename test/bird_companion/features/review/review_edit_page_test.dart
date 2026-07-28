import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/presentation/review_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('识别修改页支持候选鸟种和人工标签', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewEditPage(
          keepState: KeepState.keep,
          species: '普通翠鸟',
          score: '4.5',
          tags: '湿地, 翠鸟',
          initialCandidates: [
            SpeciesCandidate(
              speciesId: 'kingfisher',
              name: '普通翠鸟',
              confidence: .92,
            ),
            SpeciesCandidate(
              speciesId: 'egret',
              name: '白鹭',
              confidence: .73,
            ),
          ],
        ),
      ),
    );

    expect(find.text('普通翠鸟'), findsWidgets);
    expect(find.text('白鹭'), findsOneWidget);
    expect(find.text('湿地'), findsOneWidget);
    expect(find.text('翠鸟'), findsOneWidget);

    await tester.tap(find.text('白鹭'));
    await tester.pump();
    expect(
      find.byIcon(Icons.radio_button_checked_rounded),
      findsOneWidget,
    );

    await tester.tap(find.text('添加标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '飞行');
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();

    expect(find.text('飞行'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
  });
}
