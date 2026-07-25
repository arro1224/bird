import 'package:aves/bird_companion/features/review/presentation/widgets/comparison_review_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('对比操作区显示四个按钮并可保留两张', (tester) async {
    var keepBothCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ComparisonReviewActions(
              leftRetained: false,
              rightRetained: false,
              selectedFeatured: false,
              busy: false,
              onKeepLeft: () {},
              onKeepRight: () {},
              onKeepBoth: () => keepBothCount++,
              onFeatureSelected: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsNWidgets(4));
    expect(find.text('保留左图'), findsOneWidget);
    expect(find.text('保留右图'), findsOneWidget);
    expect(find.text('保留两张'), findsOneWidget);
    expect(find.text('设为精选'), findsOneWidget);

    await tester.tap(find.text('保留两张'));
    expect(keepBothCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同时保留时只高亮保留两张按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ComparisonReviewActions(
              leftRetained: true,
              rightRetained: true,
              selectedFeatured: false,
              busy: false,
              onKeepLeft: () {},
              onKeepRight: () {},
              onKeepBoth: () {},
              onFeatureSelected: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('保留左图'), findsOneWidget);
    expect(find.text('保留右图'), findsOneWidget);
    expect(find.text('保留两张（已选）'), findsOneWidget);
    expect(find.text('保留左图（已选）'), findsNothing);
    expect(find.text('保留右图（已选）'), findsNothing);
  });
}
