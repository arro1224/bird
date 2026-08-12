import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saving backup settings stays on the copy settings page', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    final observer = _RouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        navigatorObservers: [observer],
        home: CopyBackupSettingsPage(controller: controller),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-save')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final pushesBeforeSave = observer.pushCount;
    await tester.tap(find.byKey(const Key('copy-save')));
    await tester.pump();

    expect(observer.pushCount, pushesBeforeSave);
    expect(find.byType(CopyBackupSettingsPage), findsOneWidget);
    expect(find.text('备份设置已保存'), findsOneWidget);
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

    final xmpTitle = tester.widget<Text>(find.text('XMP / 后期标记策略'));
    final xmpSubtitle = tester.widget<Text>(find.text('保存审阅结果的 XMP 与标记'));
    expect(xmpTitle.style?.fontSize, greaterThanOrEqualTo(16));
    expect(xmpSubtitle.style?.fontSize, greaterThanOrEqualTo(14));
  });

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

class _RouteObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount += 1;
    super.didPush(route, previousRoute);
  }
}
