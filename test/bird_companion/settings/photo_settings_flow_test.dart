import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/display_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/photo_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  testWidgets('display settings update controls and reset to approved defaults', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(DisplaySettingsPage(controller: controller)));

    await tester.tap(find.text('5列'));
    await tester.pump();
    expect(controller.gridColumns, 5);

    await tester.tap(find.byKey(const Key('display-subject-box')));
    await tester.pump();
    expect(controller.showSubjectBox, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const Key('display-reset')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('恢复默认显示设置'));
    await tester.pump();
    expect(controller.gridColumns, 4);
    expect(controller.showSubjectBox, isTrue);
  });

  testWidgets('display segmented controls animate without text interpolation errors', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(DisplaySettingsPage(controller: controller)));

    await tester.tap(find.text('5列'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('photo settings sort sheet updates selected sort order', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(PhotoSettingsPage(controller: controller)));

    await tester.tap(find.byKey(const Key('photo-sort')));
    await tester.pumpAndSettle();
    expect(find.text('默认照片排序'), findsWidgets);

    for (final option in BirdPhotoSortOrder.values) {
      expect(find.text(option.label), findsWidgets);
    }
    expect(find.textContaining('文件名'), findsNothing);
    expect(find.textContaining('文件大小'), findsNothing);

    await tester.tap(find.text(BirdPhotoSortOrder.recommendedFirst.label));
    await tester.pumpAndSettle();
    expect(controller.sortOrder, BirdPhotoSortOrder.recommendedFirst);
    expect(
      find.text(BirdPhotoSortOrder.recommendedFirst.label),
      findsOneWidget,
    );
  });

  testWidgets('photo settings persist a default album filter', (tester) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(PhotoSettingsPage(controller: controller)));

    await tester.tap(find.byKey(const Key('photo-default-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('default-filter-pendingReview')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.defaultPhotoFilter,
      BirdDefaultPhotoFilter.pendingReview,
    );
    expect(find.text('待确认照片'), findsOneWidget);
  });
}
