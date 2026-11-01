import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_completion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'completion_fixtures.dart';

void main() {
  late CompletionEnvironment env;
  late StreamController<void> signals;
  String? openedChild;
  var openedRun = 0;
  setUp(() {
    env = CompletionEnvironment();
    signals = StreamController<void>.broadcast();
    openedChild = null;
    openedRun = 0;
  });
  tearDown(() async {
    env.dispose();
    await signals.close();
  });

  Widget host({String? font, GlobalKey? boundary}) => MaterialApp(
    theme: ThemeData(fontFamily: font),
    home: RepaintBoundary(
      key: boundary,
      child: SmartFollowCompletionPage(controller: env.controller, refreshSignals: signals.stream, onOpenRun: () => ++openedRun, onOpenChild: (id) => openedChild = id),
    ),
  );

  testWidgets('result preserves photo/file units and explicitly unavailable classifications', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('跟随复制已完成'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('sf-completion-recognition-review'))).data, '未提供');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-completion-copied-photos')), 250);
    expect(tester.widget<Text>(find.byKey(const Key('sf-completion-copied-photos'))).data, '1 张');
    expect(tester.widget<Text>(find.byKey(const Key('sf-completion-copied-files'))).data, '2 个');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-completion-copied-bytes')), 250);
    expect(tester.widget<Text>(find.byKey(const Key('sf-completion-copied-bytes'))).data, '128 B');
    expect(tester.widget<Text>(find.byKey(const Key('sf-completion-overwritten-files'))).data, '未提供');
    expect(env.backend.createMetadataCalls, 0);
  });

  testWidgets('nonterminal deep link returns to original run callback', (tester) async {
    env.backend.data['state'] = 'following';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('仍在处理'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sf-completion-open-run')));
    expect(openedRun, 1);
    expect(env.reportReads, isEmpty);
  });

  testWidgets('failed result shows reason without a success claim', (tester) async {
    env.backend.data.addAll({'state': 'failed', 'error_code': 'TARGET_LOST', 'error_message': '目标盘已断开'});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('跟随复制失败'), findsOneWidget);
    expect(find.text('结束原因：目标盘已断开'), findsOneWidget);
    expect(find.text('跟随复制已完成'), findsNothing);
  });

  testWidgets('unavailable report can be refreshed without writing or recreating', (tester) async {
    env.reportUnavailable = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('复制流程已结束，报告待补齐'), findsOneWidget);
    env.reportUnavailable = false;
    await tester.tap(find.byKey(const Key('sf-completion-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('跟随复制已完成'), findsOneWidget);
    expect(env.backend.startCalls, 0);
    expect(env.backend.createMetadataCalls, 0);
    expect(env.backend.actCalls, 0);
  });

  testWidgets('collapsed history expands and forwards original RC3 job ID', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final history = find.byKey(const Key('sf-completion-history'));
    await tester.scrollUntilVisible(history, 400);
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sf-completion-child-copy-1')), findsNothing);
    await tester.tap(history);
    await tester.pumpAndSettle();
    final child = find.byKey(const Key('sf-completion-child-copy-1'));
    await tester.ensureVisible(child);
    await tester.tap(child);
    expect(openedChild, 'copy-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume and reconnect signals reread reports; device change hides all old facts', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final reads = env.backend.reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    signals.add(null);
    await tester.pumpAndSettle();
    expect(env.backend.reads, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(env.backend.reads, reads + 2);
    env.current = false;
    signals.add(null);
    await tester.pumpAndSettle();
    expect(find.text('盒子连接已变化，请重新打开原任务'), findsOneWidget);
    expect(find.text('跟随复制已完成'), findsNothing);
    expect(find.byKey(const Key('sf-completion-history')), findsNothing);
  });

  testWidgets('leaving during report load cannot notify disposed page', (tester) async {
    env.gate = Completer<void>();
    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    env.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid formal completion route fails with a useful return page', (tester) async {
    await tester.pumpWidget(const MaterialApp(initialRoute: BirdRoutes.smartFollowCompletion, onGenerateRoute: BirdAppRouter.onGenerateRoute));
    await tester.pumpAndSettle();
    expect(find.text('缺少跟随任务编号'), findsOneWidget);
  });

  testWidgets('360dp at 150 percent text remains scrollable including expanded reports', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = Platform.environment['SF_B4_CHINESE_FONT'];
    await tester.runAsync(() async {
      for (final entry in {'ChinesePreview': font, 'MaterialIcons': Platform.environment['SF_B4_ICON_FONT']}.entries) {
        if (entry.value == null) continue;
        final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value!).readAsBytes())));
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(host(font: font == null ? null : 'ChinesePreview', boundary: boundary));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Future<void> capture(String name) async {
      final directory = Platform.environment['SF_B4_SCREENSHOT_DIR'];
      if (directory == null) return;
      await tester.runAsync(() async {
        final rendered = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    }

    await capture('completion-top-360dp-150pct');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-completion-copied-bytes')), 300);
    await tester.pumpAndSettle();
    await capture('completion-counts-360dp-150pct');
    await tester.scrollUntilVisible(find.byKey(const Key('sf-completion-history')), 300);
    await tester.tap(find.byKey(const Key('sf-completion-history')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-completion-child-copy-1')));
    await tester.pumpAndSettle();
    await capture('completion-history-360dp-150pct');
    expect(tester.takeException(), isNull);
  });
}
