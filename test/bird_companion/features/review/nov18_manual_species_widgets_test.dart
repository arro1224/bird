import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/presentation/version_history_page.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/recognition_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unverified legacy AI cache does not display a borrowed confidence', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecognitionPanel(
            value: RecognitionResult(candidates: [SpeciesCandidate(name: '白鹭', confidence: .42)], isOriginalVerified: false),
            currentSpecies: '白鹭',
          ),
        ),
      ),
    );
    expect(find.text('42%'), findsNothing);
    expect(find.textContaining('需联网刷新'), findsOneWidget);
    expect(find.byKey(const ValueKey('recognition-current-species')), findsOneWidget);
  });
  testWidgets('manual result has no probability while AI candidates retain rank, 42/37 and long scientific names', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RecognitionPanel(
                value: RecognitionResult(
                  candidates: [
                    SpeciesCandidate(name: '普通翠鸟', confidence: .42, latinName: 'Alcedo atthis long scientific subspecies name'),
                    SpeciesCandidate(name: '白鹭', confidence: .37, latinName: 'Egretta garzetta'),
                  ],
                  isLowConfidence: true,
                ),
                currentSpeciesId: 'little-egret',
                currentSpecies: '白鹭',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('人工修正'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('37%'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('ai-candidate-confidence-0'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('ai-candidate-confidence-1'))).dy));
    expect(find.textContaining('没有模型置信度'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('history explains manual fields and clears in Chinese', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VersionHistoryPage(
          items: [VersionHistory(version: 2, source: 'app', updatedAt: DateTime.utc(2026, 11, 18), summary: 'user_species_id=null; user_species=null; user_score=4; user_tags=[]; keep_state=keep')],
        ),
      ),
    );
    expect(find.textContaining('人工鸟种编号=已清除'), findsOneWidget);
    expect(find.textContaining('人工评分=4'), findsOneWidget);
    expect(find.textContaining('user_species'), findsNothing);
  });
}
