import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy settings retain mode and selected storage target', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyBackupSettingsPage(controller: controller),
      ),
    );

    await tester.tap(find.text('双轨复制'));
    await tester.pump();
    expect(controller.copyMode, BirdCopyMode.dualTrack);

    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-target')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('copy-target')));
    await tester.pumpAndSettle();
    expect(find.text('选择目标位置'), findsOneWidget);

    await tester.tap(find.byKey(const Key('storage-local')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('storage-confirm')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('设为默认目标位置'));
    await tester.pumpAndSettle();

    expect(controller.selectedStorageId, 'local');
    expect(find.text('本机存储'), findsOneWidget);
  });
}
