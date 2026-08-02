import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_review_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('comparison actions support quick decisions and keeping all', (
    tester,
  ) async {
    var discardCount = 0;
    var keepCount = 0;
    var featureCount = 0;
    var keepAllCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: ComparisonReviewActions(
              selectedState: KeepState.pending,
              itemCount: 3,
              busy: false,
              onDiscardSelected: () => discardCount++,
              onKeepSelected: () => keepCount++,
              onKeepAll: () => keepAllCount++,
              onFeatureSelected: () => featureCount++,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsNWidgets(4));
    expect(find.text('弃用当前'), findsOneWidget);
    expect(find.text('保留当前'), findsOneWidget);
    expect(find.text('设为精选'), findsOneWidget);
    expect(find.text('保留全部 3 张'), findsOneWidget);

    await tester.tap(find.text('弃用当前'));
    await tester.tap(find.text('保留当前'));
    await tester.tap(find.text('设为精选'));
    await tester.tap(find.text('保留全部 3 张'));

    expect(discardCount, 1);
    expect(keepCount, 1);
    expect(featureCount, 1);
    expect(keepAllCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected comparison action is visibly labelled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: ComparisonReviewActions(
              selectedState: KeepState.featured,
              itemCount: 2,
              busy: false,
              onDiscardSelected: () {},
              onKeepSelected: () {},
              onKeepAll: () {},
              onFeatureSelected: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('设为精选（已选）'), findsOneWidget);
    expect(find.text('保留当前（已选）'), findsNothing);
    expect(find.text('弃用当前（已选）'), findsNothing);
  });
}
