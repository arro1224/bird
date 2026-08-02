import 'package:aves/bird_companion/features/review/presentation/widgets/group_review_scope_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('窄屏可切换当前照片与整组操作范围', (tester) async {
    bool? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: GroupReviewScopeSelector(
              applyToWholeGroup: false,
              memberCount: 12,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('操作范围'), findsOneWidget);
    expect(find.text('当前照片'), findsOneWidget);
    expect(find.text('整组 12 张'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('整组 12 张'));
    await tester.pump();

    expect(selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
