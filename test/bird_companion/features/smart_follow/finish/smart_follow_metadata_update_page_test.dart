import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_update_fixtures.dart';

void main() {
  late MetadataUpdateEnvironment env;
  late StreamController<void> signals;
  String? copy, opened;
  int previews = 0;
  setUp(() {
    env = MetadataUpdateEnvironment();
    signals = StreamController<void>.broadcast();
    copy = opened = null;
    previews = 0;
  });
  tearDown(() async {
    env.dispose();
    await signals.close();
  });
  Widget host({String? font, GlobalKey? boundary}) => MaterialApp(
    theme: ThemeData(fontFamily: font),
    home: RepaintBoundary(
      key: boundary,
      child: SmartFollowMetadataUpdatePage(
        controller: env.controller,
        refreshSignals: signals.stream,
        pollInterval: const Duration(seconds: 1),
        onOpenCopy: (id) => copy = id,
        onOpenPreview: () => ++previews,
        onOpenUpdate: (id) => opened = id,
      ),
    ),
  );
  Future<void> mount(WidgetTester tester, Widget child) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
  }

  testWidgets('terminal report distinguishes updated photos and files', (tester) async {
    await mount(tester, host());
    expect(find.text('识别信息更新完成'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('sf-update-files')), 200);
    expect(tester.widget<Text>(find.byKey(const Key('sf-update-photos'))).data, '3 张');
    expect(tester.widget<Text>(find.byKey(const Key('sf-update-files'))).data, '5 个');
    expect(env.backend.creates, 0);
  });
  testWidgets('partial failure shows reasons and original copy mapping', (tester) async {
    env.backend.updateData.addAll({'state': 'completed_partial', 'failed_count': 1, 'error_message': '副本已被外部修改'});
    ((env.backend.updateData['child_jobs'] as List)[1] as Map<String, dynamic>).addAll({'state': 'failed', 'failed_file_count': 1, 'error_code': 'TARGET_HASH_MISMATCH', 'error_message': '目标副本已变化'});
    await mount(tester, host());
    expect(find.text('识别信息部分更新'), findsOneWidget);
    expect(find.text('原因：副本已被外部修改'), findsOneWidget);
    final button = find.byKey(const Key('sf-update-copy-1'));
    await tester.scrollUntilVisible(button, 250);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(find.text('原因：目标副本已变化'), findsOneWidget);
    await tester.tap(button);
    expect(copy, 'copy-2');
    expect(env.backend.actCalls, 0);
    expect(env.backend.creates, 0);
  });
  testWidgets('missing fields show unavailable instead of success or zero', (tester) async {
    env.backend.updateData.remove('updated_file_count');
    await mount(tester, host());
    expect(find.text('更新任务已结束，报告待补齐'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('sf-update-files')), 200);
    expect(tester.widget<Text>(find.byKey(const Key('sf-update-files'))).data, '未提供');
  });
  testWidgets('unknown state keeps polling until an explicit terminal response', (tester) async {
    env.backend.updateData['state'] = 'new-unknown-state';
    await mount(tester, host());
    expect(find.text('状态待确认'), findsOneWidget);
    env.backend.updateData.addAll({'state': 'completed', 'state_version': 2});
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('识别信息更新完成'), findsOneWidget);
    expect(env.backend.parentReads, ['update-1', 'update-1']);
  });
  testWidgets('background pauses polling and resume reads same parent', (tester) async {
    env.backend.updateData['state'] = 'running';
    await mount(tester, host());
    final reads = env.backend.updateReads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 20));
    expect(env.backend.updateReads, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(env.backend.updateReads, reads + 1);
    expect(env.backend.creates, 0);
  });
  testWidgets('read errors back off and reconnect retries without submission', (tester) async {
    env.backend.parentFails = true;
    await mount(tester, host());
    expect(find.byKey(const Key('sf-update-error')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(env.backend.updateReads, 1);
    env.backend.parentFails = false;
    signals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('识别信息更新完成'), findsOneWidget);
    expect(env.backend.creates, 0);
  });
  testWidgets('later availability enables preview only and old success does not suppress it', (tester) async {
    await mount(tester, host());
    expect(find.byKey(const Key('sf-update-preview-again')), findsNothing);
    env.backend.available = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('sf-update-preview-again'));
    await tester.scrollUntilVisible(button, 250);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect(previews, 1);
    expect(env.backend.creates, 0);
    expect(env.backend.previewReads, 0);
  });
  testWidgets('a different active parent is offered without replacing current report', (tester) async {
    env.backend.active = 'update-2';
    await env.repository.rememberMetadataUpdate('sf_fake', 'update-1');
    await mount(tester, host());
    final button = find.byKey(const Key('sf-update-other-active'));
    await tester.scrollUntilVisible(button, 250);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect(opened, 'update-2');
    expect(env.controller.updateId, 'update-1');
  });
  testWidgets('device change hides all old report facts and links', (tester) async {
    await mount(tester, host());
    env.current = false;
    signals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('盒子连接已变化，请重新打开原任务'), findsOneWidget);
    expect(find.byKey(const Key('sf-update-title')), findsNothing);
    expect(find.byKey(const Key('sf-update-copy-0')), findsNothing);
  });
  testWidgets('covering a report route pauses polling and returning rereads', (tester) async {
    await mount(tester, host());
    final navigator = Navigator.of(tester.element(find.byType(SmartFollowMetadataUpdatePage)));
    unawaited(navigator.push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('RC3 detail')))));
    await tester.pumpAndSettle();
    final reads = env.backend.updateReads;
    await tester.pump(const Duration(seconds: 20));
    expect(env.backend.updateReads, reads);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(env.backend.updateReads, reads + 1);
  });
  testWidgets('360dp 150 percent partial report and child reasons remain scrollable', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = Platform.environment['SF_B6_CHINESE_FONT'];
    await tester.runAsync(() async {
      for (final entry in {'ChinesePreview': font, 'MaterialIcons': Platform.environment['SF_B6_ICON_FONT']}.entries) {
        if (entry.value == null) continue;
        final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value!).readAsBytes())));
        await loader.load();
      }
    });
    env.backend.updateData.addAll({'state': 'completed_partial', 'failed_count': 1, 'blocked_count': 1, 'error_message': '部分副本已被外部修改，已更新项目保留'});
    ((env.backend.updateData['child_jobs'] as List)[1] as Map<String, dynamic>).addAll({'state': 'failed', 'failed_file_count': 1, 'error_code': 'TARGET_HASH_MISMATCH', 'error_message': '目标副本已变化，需要人工核对'});
    env.backend.available = true;
    final boundary = GlobalKey();
    await mount(tester, host(font: font == null ? null : 'ChinesePreview', boundary: boundary));
    Future<void> capture(String name) async {
      final directory = Platform.environment['SF_B6_SCREENSHOT_DIR'];
      if (directory == null) return;
      await tester.runAsync(() async {
        final rendered = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    }

    await capture('metadata-update-top-360dp-150pct');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-update-copy-1')), 250);
    await tester.ensureVisible(find.byKey(const Key('sf-update-copy-1')));
    await tester.pumpAndSettle();
    await capture('metadata-update-children-360dp-150pct');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-update-preview-again')), 250);
    await tester.ensureVisible(find.byKey(const Key('sf-update-preview-again')));
    await tester.pumpAndSettle();
    await capture('metadata-update-new-information-360dp-150pct');
    expect(tester.takeException(), isNull);
    expect(env.backend.creates, 0);
  });
}
