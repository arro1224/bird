import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy settings changes persist immediately on the controller', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyBackupSettingsPage(controller: controller),
      ),
    );

    await tester.tap(find.text('复制全部'));
    await tester.pump();
    expect(controller.copyMode, BirdCopyMode.batchAllAssets);

    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-naming-policy')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(controller.reviewExportEnabled, isFalse);
  });

  testWidgets('copy settings use readable phone typography', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyBackupSettingsPage(controller: controller),
      ),
    );

    final exportTitle = tester.widget<Text>(find.text('随副本保存审阅信息'));
    final exportSubtitle = tester.widget<Text>(find.text('向目标盘输出 XMP 与审阅 CSV'));
    expect(exportTitle.style?.fontSize, greaterThanOrEqualTo(16));
    expect(exportSubtitle.style?.fontSize, greaterThanOrEqualTo(14));
  });

  testWidgets('review export off disables the embed-into-copy switch', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CopyBackupSettingsPage(controller: controller),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-naming-policy')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final embed = tester.widget<Switch>(find.byType(Switch).at(1));
    expect(embed.onChanged, isNull);
  });
}
