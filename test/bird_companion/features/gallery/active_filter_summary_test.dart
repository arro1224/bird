import 'package:aves/bird_companion/features/gallery/presentation/widgets/active_filter_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active filters stay on one row until expanded', (tester) async {
    var clearCount = 0;
    const labels = [
      '照片质量 ≥ 4.0 星',
      '照片状态：待确认',
      '清晰度：清晰',
      '识别结果：已识别',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ActiveFilterSummary(
                labels: labels,
                onClear: () => clearCount++,
              ),
            ),
          ),
        ),
      ),
    );

    final summary = find.byKey(const ValueKey('active-filter-summary'));
    expect(summary, findsOneWidget);
    expect(tester.getSize(summary).height, 48);
    expect(find.text('筛选条件 · 已选 4 项'), findsOneWidget);
    for (final label in labels) {
      expect(find.text(label), findsNothing);
    }

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();

    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.getSize(summary).height, greaterThan(48));

    await tester.tap(find.text('清除全部'));
    expect(clearCount, 1);
  });
}
