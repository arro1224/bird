import 'dart:io';

import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/copy_backup_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/display_settings_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/help_center_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _phoneSize = Size(426, 923);

void main() {
  setUpAll(() async {
    await _loadFont(
      'Noto Sans SC',
      'test/bird_companion/goldens/fonts/NotoSansSC-Settings.ttf',
    );
    await _loadFont(
      'MaterialIcons',
      'test/bird_companion/goldens/fonts/MaterialIcons-Settings.otf',
    );
  });

  testWidgets('approved display and copy actions are visible on first phone screen', (
    tester,
  ) async {
    final controller = BirdSettingsController();
    addTearDown(controller.dispose);

    await _pumpPhone(
      tester,
      DisplaySettingsPage(controller: controller),
    );
    _expectInFirstScreen(tester, find.byKey(const Key('display-reset')));

    await _pumpPhone(
      tester,
      CopyBackupSettingsPage(controller: controller),
    );
    _expectInFirstScreen(tester, find.text('默认复制范围'));
  });

  testWidgets('approved support page endings are visible on first phone screen', (
    tester,
  ) async {
    await _pumpPhone(tester, const NetworkDiagnosticsPage());
    _expectInFirstScreen(
      tester,
      find.byKey(const Key('network-transfer-note')),
    );

    await _pumpPhone(tester, const SystemLogsPage());
    _expectInFirstScreen(
      tester,
      find.byKey(const Key('logs-export-package')),
    );

    await _pumpPhone(tester, const HelpCenterPage());
    _expectInFirstScreen(tester, find.byKey(const Key('help-support-hours')));
  });
}

Future<void> _pumpPhone(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = _phoneSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light().copyWith(
        textTheme: AppTheme.light().textTheme.apply(
          fontFamily: 'Noto Sans SC',
        ),
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void _expectInFirstScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(tester.getBottomRight(finder).dy, lessThanOrEqualTo(_phoneSize.height));
}
