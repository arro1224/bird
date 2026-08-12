import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings controller exposes approved defaults and updates values', () {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);

    expect(controller.gridColumns, 4);
    expect(controller.sortOrder, BirdPhotoSortOrder.newest);
    expect(controller.copyMode, BirdCopyMode.keptOnly);
    expect(controller.selectedStorageId, 'removable-e');

    controller
      ..setGridColumns(5)
      ..setSortOrder(BirdPhotoSortOrder.recommendedFirst)
      ..setCopyMode(BirdCopyMode.dualTrack)
      ..setStorageTarget('local');

    expect(controller.gridColumns, 5);
    expect(controller.sortOrder, BirdPhotoSortOrder.recommendedFirst);
    expect(controller.copyMode, BirdCopyMode.dualTrack);
    expect(controller.selectedStorageId, 'local');
  });

  test('default photo sorts match the gallery sort protocol', () {
    expect(BirdPhotoSortOrder.values, [
      BirdPhotoSortOrder.newest,
      BirdPhotoSortOrder.qualityDescending,
      BirdPhotoSortOrder.recommendedFirst,
      BirdPhotoSortOrder.confidenceDescending,
    ]);
    expect(
      BirdPhotoSortOrder.values.map((value) => value.querySort),
      [
        'captured_at_desc',
        'score_desc',
        'recommended_desc',
        'confidence_desc',
      ],
    );
  });

  testWidgets('settings scaffold provides a 48dp back target and centered title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const BirdSettingsScaffold(
          title: '显示设置',
          body: SizedBox.shrink(),
        ),
      ),
    );

    expect(find.text('显示设置'), findsOneWidget);
    final back = tester.getSize(find.byKey(const Key('settings-back')));
    expect(back.width, greaterThanOrEqualTo(48));
    expect(back.height, greaterThanOrEqualTo(48));
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('settings device icon uses the v1 K7 line illustration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BirdSettingsDeviceIcon())),
    );

    expect(find.byKey(const Key('v1-device-illustration')), findsOneWidget);
    expect(find.bySemanticsLabel('拍鸟伴侣 K7 设备'), findsOneWidget);
    expect(find.byIcon(Icons.router_rounded), findsNothing);
  });
}
