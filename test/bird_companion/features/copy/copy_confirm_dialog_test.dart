import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy confirmation shows a low battery reminder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyConfirmDialog(
            fileCount: 12,
            requiredBytes: 1024,
            targetName: 'USB',
            xmpEnabled: true,
            lowBatteryPercent: 15,
            onConfirm: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('copy-low-battery-warning')), findsOneWidget);
    expect(find.textContaining('15%'), findsOneWidget);
  });

  testWidgets('copy confirmation omits the warning without low battery', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopyConfirmDialog(
            fileCount: 12,
            requiredBytes: 1024,
            targetName: 'USB',
            xmpEnabled: true,
            onConfirm: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('copy-low-battery-warning')), findsNothing);
  });
}
