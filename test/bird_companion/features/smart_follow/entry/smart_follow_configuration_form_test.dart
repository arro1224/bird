import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/recognition/recognition_widgets.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_form.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'configuration_fixtures.dart';

const confirmKey = Key('smart-follow-confirm-configuration');

Future<void> chooseConflict(WidgetTester tester, [ConflictStrategy strategy = ConflictStrategy.skip]) async {
  final field = find.byType(DropdownButtonFormField<ConflictStrategy>);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(strategy.label).last);
  await tester.pumpAndSettle();
}

Future<void> selectAndConfirm(WidgetTester tester) async {
  final target = find.byKey(const Key('storage-device-target-目标设备'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  await chooseConflict(tester);
  await tester.ensureVisible(find.byKey(confirmKey));
  await tester.tap(find.byKey(confirmKey));
  await tester.pumpAndSettle();
}

Widget configurationHost(SmartFollowConfigurationReader reader, {ValueChanged<SmartFollowConfiguredIntent?>? onChanged, GlobalKey? boundary, ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: SingleChildScrollView(
      child: RepaintBoundary(
        key: boundary,
        child: Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SmartFollowConfigurationForm(reader: reader, onChanged: onChanged),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  SmartFollowEntryReader entryReader(ConfigurationFixture fixture) => SmartFollowEntryReader(
    batchId: 'batch-1',
    isCurrent: () => fixture.current,
    readCapabilities: () async => fixture.snapshot().entry.capabilities,
    readSession: (_) async => null,
    readPage: (_) async => JobPage(items: [fixture.snapshot().entry.job!], hasMore: false),
  );

  testWidgets('returning to snapshot discards the follow configuration', (tester) async {
    final fixture = ConfigurationFixture();
    SmartFollowConfiguredIntent? configured;
    var following = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartFollowEntrySection(
              batchId: 'batch-1',
              reader: entryReader(fixture),
              configurationReader: fixture.reader(),
              onModeChanged: (value) => following = value,
              onConfigurationChanged: (value) => configured = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(configured, isNotNull);
    expect(following, isTrue);
    final snapshot = find.byKey(const Key('smart-follow-select-snapshot'));
    await tester.ensureVisible(snapshot);
    await tester.tap(snapshot);
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(following, isFalse);
    expect(find.byKey(const Key('smart-follow-configuration')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('task dialog mounts full config and keeps session creation for SF-B3', (tester) async {
    final fixture = ConfigurationFixture();
    RecognitionChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => choice = await chooseRecognitionMode(context, _UnusedRecognitionRepository(), entryReader: entryReader(fixture), configurationReader: fixture.reader()),
              child: const Text('打开识别配置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开识别配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(find.byKey(const Key('smart-follow-configuration-confirmed')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('recognition-mode-confirm'))).onPressed, isNull);
    expect(choice, isNull);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(choice, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no target gives guidance and disables confirmation', (tester) async {
    final fixture = ConfigurationFixture()..devices = [configDevice('source', source: true)];
    await tester.pumpWidget(configurationHost(fixture.reader()));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有可用的目标设备'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('target and conflict must be explicit; complete frozen config is returned', (tester) async {
    final fixture = ConfigurationFixture()..preferred = PairPolicy.jpegOnly;
    SmartFollowConfiguredIntent? configured;
    await tester.pumpWidget(configurationHost(fixture.reader(), onChanged: (value) => configured = value));
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    expect(find.text(PairPolicy.jpegOnly.label), findsOneWidget);
    await selectAndConfirm(tester);
    expect(configured!.request.toJson(), {
      'target_media_id': 'target',
      'eligibility_mode': 'recognized_only_v1',
      'pair_policy': 'jpeg_only',
      'conflict_strategy': 'skip',
      'review_export': {'enabled': false, 'prefer_embedded': true},
    });
    expect(find.byKey(const Key('smart-follow-configuration-confirmed')), findsOneWidget);
    expect(fixture.reads, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unwritable candidates explain why and cannot be selected', (tester) async {
    final fixture = ConfigurationFixture()
      ..devices = [
        configDevice('source', source: true),
        configDevice('target', writable: false, reasons: ['COPY_TARGET_READ_ONLY']),
      ];
    await tester.pumpWidget(configurationHost(fixture.reader()));
    await tester.pumpAndSettle();
    expect(find.textContaining('设备为只读'), findsWidgets);
    expect(tester.widget<InkWell>(find.byKey(const Key('storage-device-target-目标设备'))).onTap, isNull);
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing export invalidates confirmation; only one export toggle exists', (tester) async {
    SmartFollowConfiguredIntent? configured;
    await tester.pumpWidget(configurationHost(ConfigurationFixture().reader(), onChanged: (value) => configured = value));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(configured, isNotNull);
    final toggle = find.byKey(const Key('smart-follow-review-export'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.ensureVisible(find.byKey(confirmKey));
    await tester.tap(find.byKey(confirmKey));
    await tester.pumpAndSettle();
    expect(configured!.request.toJson()['review_export'], {'enabled': true, 'prefer_embedded': true});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing initial-copy export capability disables its switch', (tester) async {
    final fixture = ConfigurationFixture()..exports = false;
    await tester.pumpWidget(configurationHost(fixture.reader()));
    await tester.pumpAndSettle();
    final toggle = tester.widget<SwitchListTile>(find.byKey(const Key('smart-follow-review-export')));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
    expect(find.textContaining('本次只复制照片'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device change clears a confirmed config and requires detection again', (tester) async {
    final changes = StreamController<void>.broadcast();
    final fixture = ConfigurationFixture();
    SmartFollowConfiguredIntent? configured;
    await tester.pumpWidget(configurationHost(fixture.reader(changes: changes.stream), onChanged: (value) => configured = value));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(configured, isNotNull);
    changes.add(null);
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });

  testWidgets('replacing a reader cannot retain a previous confirmed config', (tester) async {
    final fixture = ConfigurationFixture();
    SmartFollowConfiguredIntent? configured;
    void changed(SmartFollowConfiguredIntent? value) => configured = value;
    await tester.pumpWidget(configurationHost(fixture.reader(), onChanged: changed));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(configured, isNotNull);
    await tester.pumpWidget(configurationHost(ConfigurationFixture().reader(), onChanged: changed));
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding invalidates config instead of silently reusing it', (tester) async {
    SmartFollowConfiguredIntent? configured;
    await tester.pumpWidget(configurationHost(ConfigurationFixture().reader(), onChanged: (value) => configured = value));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(configured, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(confirmKey)).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explicit cancellation discards config', (tester) async {
    SmartFollowConfiguredIntent? configured;
    await tester.pumpWidget(configurationHost(ConfigurationFixture().reader(), onChanged: (value) => configured = value));
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    final cancel = find.byKey(const Key('smart-follow-cancel-configuration'));
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(configured, isNull);
    expect(find.byKey(const Key('smart-follow-configuration-confirmed')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('configuration fits a 360dp screen at 1.5 text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = Platform.environment['SF_B2_CHINESE_FONT'];
    final icons = Platform.environment['SF_B2_ICON_FONT'];
    await tester.runAsync(() async {
      for (final entry in {'ChinesePreview': font, 'MaterialIcons': icons}.entries) {
        if (entry.value == null) continue;
        final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value!).readAsBytes())));
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      configurationHost(
        ConfigurationFixture().reader(),
        boundary: boundary,
        theme: ThemeData(fontFamily: font == null ? null : 'ChinesePreview'),
      ),
    );
    await tester.pumpAndSettle();
    await selectAndConfirm(tester);
    expect(tester.takeException(), isNull);
    final directory = Platform.environment['SF_B2_SCREENSHOT_DIR'];
    if (directory != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/configuration-360dp-150pct.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class _UnusedRecognitionRepository implements RecognitionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('configuration must not call a creation API');
}
