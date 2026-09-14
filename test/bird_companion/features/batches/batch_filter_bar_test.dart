import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/batches/presentation/widgets/batch_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history filter has a strong themed single-selection state', (tester) async {
    final changes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchFilterBar(
            value: 'review',
            onChanged: changes.add,
          ),
        ),
      ),
    );

    final control = tester.widget<SegmentedButton<String?>>(
      find.byType(SegmentedButton<String?>),
    );
    final style = control.style!;
    const selected = {WidgetState.selected};

    expect(control.selected, {'review'});
    expect(control.emptySelectionAllowed, isFalse);
    expect(style.backgroundColor?.resolve(selected), AppColors.brand);
    expect(style.foregroundColor?.resolve(selected), AppColors.cream);
    expect(style.side?.resolve(selected)?.color, AppColors.brand);
    expect(style.side?.resolve(selected)?.width, 1.5);
    expect(style.textStyle?.resolve(selected)?.fontWeight, FontWeight.w800);
    expect(style.backgroundColor?.resolve(const {}), AppColors.paperStrong);
    expect(style.foregroundColor?.resolve(const {}), AppColors.brandDark);

    expect(find.byKey(const Key('batch-filter-all')), findsOneWidget);
    expect(find.byKey(const Key('batch-filter-in-progress')), findsOneWidget);
    expect(find.byKey(const Key('batch-filter-review')), findsOneWidget);
    expect(find.byKey(const Key('batch-filter-failed')), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch-filter-failed')));
    await tester.pump();
    expect(changes, ['failed']);
  });

  testWidgets('all is represented by a selected null segment', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchFilterBar(value: null, onChanged: (_) {}),
        ),
      ),
    );

    final control = tester.widget<SegmentedButton<String?>>(
      find.byType(SegmentedButton<String?>),
    );
    expect(control.selected, {null});
    expect(control.emptySelectionAllowed, isFalse);
  });
}
