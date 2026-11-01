import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_section.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_preview_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_fixtures.dart';

void main() {
  late MetadataEnvironment env;
  late StreamController<void> signals;
  String? opened;
  int previews = 0;
  setUp(() {
    env = MetadataEnvironment();
    signals = StreamController<void>.broadcast();
    opened = null;
    previews = 0;
  });
  tearDown(() async {
    env.dispose();
    await signals.close();
  });
  Widget section() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SmartFollowMetadataSection(
          repository: env.repository,
          sessionId: 'sf_fake',
          readRecognition: env.controller.readRecognition,
          isCurrent: () => env.current,
          refreshSignals: signals.stream,
          onOpenPreview: () => ++previews,
          onOpenUpdate: (id) => opened = id,
        ),
      ),
    ),
  );
  Widget preview({String? font, GlobalKey? boundary}) => MaterialApp(
    theme: ThemeData(fontFamily: font),
    home: RepaintBoundary(
      key: boundary,
      child: SmartFollowMetadataPreviewPage(controller: env.controller, onOpenUpdate: (id) => opened = id, refreshSignals: signals.stream),
    ),
  );
  Future<void> mount(WidgetTester tester, Widget widget) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('capability off hides all executable metadata entries', (tester) async {
    env.backend.capability = false;
    await mount(tester, section());
    expect(find.byKey(const Key('sf-metadata-open-preview')), findsNothing);
    expect(find.byKey(const Key('sf-metadata-open-update')), findsNothing);
    expect(env.backend.availabilityReads, 0);
    expect(env.backend.creates, 0);
  });
  testWidgets('running hint becomes primary when independent recognition status finishes', (tester) async {
    env.recognitionState = BirdJobState.running;
    await mount(tester, section());
    expect(find.text('保存当前已有信息'), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('sf-metadata-open-preview'))), isA<OutlinedButton>());
    env.recognitionState = BirdJobState.completed;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('更新识别信息'), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('sf-metadata-open-preview'))), isA<FilledButton>());
    await tester.tap(find.byKey(const Key('sf-metadata-open-preview')));
    expect(previews, 1);
    expect(env.backend.previewReads, 0);
    expect(env.backend.creates, 0);
  });
  testWidgets('background pauses metadata reads and resume catches up', (tester) async {
    await mount(tester, section());
    final reads = env.backend.availabilityReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 12));
    expect(env.backend.availabilityReads, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(env.backend.availabilityReads, reads + 1);
  });
  testWidgets('existing parent shows only original task entry', (tester) async {
    env.backend.active = 'old-parent';
    await mount(tester, section());
    expect(find.byKey(const Key('sf-metadata-open-preview')), findsNothing);
    await tester.tap(find.byKey(const Key('sf-metadata-open-update')));
    expect(opened, 'old-parent');
    expect(env.backend.creates, 0);
  });
  testWidgets('partial preview requires checkbox and final click; checkbox alone does not write', (tester) async {
    env.backend.previewData.addAll({
      'blocked_count': 1,
      'requires_partial_confirmation': true,
      'blocked_reasons': ['副本已被外部修改'],
    });
    await mount(tester, preview());
    final confirm = find.byKey(const Key('sf-metadata-confirm'));
    await tester.scrollUntilVisible(confirm, 250);
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final consent = find.byKey(const Key('sf-metadata-partial-consent'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(env.backend.creates, 0);
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(env.backend.creates, 1);
    expect(env.backend.submitted!['confirm_partial'], true);
    expect(find.textContaining('提交成功不代表'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sf-metadata-view-existing')));
    expect(opened, 'update-1');
  });
  testWidgets('missing count renders unavailable and disables confirm', (tester) async {
    env.backend.previewData.remove('estimated_bytes');
    await mount(tester, preview());
    await tester.scrollUntilVisible(find.byKey(const Key('sf-metadata-preview-bytes')), 250);
    expect(tester.widget<Text>(find.byKey(const Key('sf-metadata-preview-bytes'))).data, '未提供');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-metadata-confirm')), 200);
    expect(tester.widget<FilledButton>(find.byKey(const Key('sf-metadata-confirm'))).onPressed, isNull);
  });
  testWidgets('expiry invalidates displayed preview until explicit refresh', (tester) async {
    env.backend.previewData['expires_at'] = env.clock.add(const Duration(seconds: 2)).toIso8601String();
    await mount(tester, preview());
    env.clock = env.clock.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sf-metadata-confirm')), findsNothing);
    expect(find.textContaining('重新获取预览'), findsWidgets);
    expect(env.backend.creates, 0);
  });
  testWidgets('device signals remove old preview facts and confirm button', (tester) async {
    await mount(tester, preview());
    env.current = false;
    signals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('盒子连接已变化，请重新打开原任务'), findsOneWidget);
    expect(find.byKey(const Key('sf-metadata-confirm')), findsNothing);
    expect(env.backend.creates, 0);
  });
  testWidgets('back from preview cancels without mutation', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await mount(
      tester,
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('origin')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SmartFollowMetadataPreviewPage(controller: env.controller, onOpenUpdate: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
    expect(env.backend.creates, 0);
  });
  testWidgets('parent page reads original parent and never creates another', (tester) async {
    env.backend.active = 'existing-parent';
    final state = SmartFollowMetadataUpdateController(repository: env.repository, sessionId: 'sf_fake', updateId: 'existing-parent', isCurrent: () => env.current);
    addTearDown(state.dispose);
    await mount(
      tester,
      MaterialApp(
        home: SmartFollowMetadataUpdatePage(controller: state, onOpenCopy: (_) {}, onOpenPreview: () {}, onOpenUpdate: (_) {}, refreshSignals: signals.stream),
      ),
    );
    expect(find.text('正在更新'), findsOneWidget);
    expect(env.backend.updateReads, 1);
    expect(env.backend.creates, 0);
    env.current = false;
    signals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('盒子连接已变化，请重新打开原任务'), findsOneWidget);
  });
  testWidgets('360dp 150 percent preview separates photos and files and fits partial consent', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = Platform.environment['SF_B5_CHINESE_FONT'];
    await tester.runAsync(() async {
      for (final entry in {'ChinesePreview': font, 'MaterialIcons': Platform.environment['SF_B5_ICON_FONT']}.entries) {
        if (entry.value == null) continue;
        final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value!).readAsBytes())));
        await loader.load();
      }
    });
    env.backend.previewData.addAll({
      'blocked_count': 1,
      'requires_partial_confirmation': true,
      'blocked_reasons': ['副本已被外部修改，需保留原文件'],
    });
    final boundary = GlobalKey();
    await mount(tester, preview(font: font == null ? null : 'ChinesePreview', boundary: boundary));
    Future<void> capture(String name) async {
      final directory = Platform.environment['SF_B5_SCREENSHOT_DIR'];
      if (directory == null) return;
      await tester.runAsync(() async {
        final rendered = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
        rendered.dispose();
      });
    }

    expect(tester.widget<Text>(find.byKey(const Key('sf-metadata-preview-photos'))).data, '3 张');
    expect(tester.widget<Text>(find.byKey(const Key('sf-metadata-preview-files'))).data, '5 个');
    await capture('metadata-preview-top-360dp-150pct');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-metadata-confirm')), 250);
    await tester.ensureVisible(find.byKey(const Key('sf-metadata-confirm')));
    await tester.pumpAndSettle();
    await capture('metadata-preview-consent-360dp-150pct');
    expect(tester.takeException(), isNull);
    expect(env.backend.creates, 0);
  });
}
