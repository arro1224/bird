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

  testWidgets('copy confirmation actions remain on one row on a phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CopyConfirmDialog(
                    fileCount: 17,
                    requiredBytes: 408 * 1024 * 1024,
                    targetName: 'MOCK-USB',
                    xmpEnabled: true,
                    onConfirm: () {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final cancel = tester.getTopLeft(find.byKey(const Key('copy-confirm-cancel')));
    final submit = tester.getTopLeft(find.byKey(const Key('copy-confirm-submit')));
    expect(cancel.dy, submit.dy);
    expect(cancel.dx, lessThan(submit.dx));
  });
}
