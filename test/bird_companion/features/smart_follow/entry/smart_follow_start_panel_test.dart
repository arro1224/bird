import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_start_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'creation_fixtures.dart';
import 'configuration_fixtures.dart';

Future<void> configureFollow(WidgetTester tester) async {
  final target = find.byKey(const Key('storage-device-media_usb_fake-目标设备'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  final conflict = find.byType(DropdownButtonFormField<ConflictStrategy>);
  await tester.ensureVisible(conflict);
  await tester.tap(conflict);
  await tester.pumpAndSettle();
  await tester.tap(find.text(ConflictStrategy.skip.label).last);
  await tester.pumpAndSettle();
  final confirm = find.byKey(const Key('smart-follow-confirm-configuration'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('changed device space drops the stale confirmation and requires another review', (tester) async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartFollowStartPanel(reader: env.reader(), service: env.service, onCreated: (_) => fail('stale config submitted')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await configureFollow(tester);
    env.configuration.devices[1] = configDevice('media_usb_fake', free: 1, displayName: '旅行备份盘');
    await tester.ensureVisible(find.byKey(const Key('smart-follow-submit')));
    await tester.tap(find.byKey(const Key('smart-follow-submit')));
    await tester.pumpAndSettle();
    expect(env.jobs.requests, isEmpty);
    expect(find.byKey(const Key('smart-follow-configuration-confirmed')), findsNothing);
    expect(find.textContaining('设备或策略已变化'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('smart-follow-submit'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('configuration confirmation does not POST; explicit start opens the returned session', (tester) async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    SmartFollowSession? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartFollowStartPanel(
              reader: env.reader(),
              service: env.service,
              expectedPhase: RecognitionEntryPhase.notStarted,
              onCreated: (session) => opened = session,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('smart-follow-submit'))).onPressed, isNull);
    await configureFollow(tester);
    expect(env.jobs.requests, isEmpty);
    final start = find.byKey(const Key('smart-follow-submit'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(opened!.sessionId, 'sf-1');
    expect(env.jobs.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown creation offers query-only recovery; it never substitutes a new request', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final font = Platform.environment['SF_B3_CHINESE_FONT'];
    await tester.runAsync(() async {
      for (final entry in {'ChinesePreview': font, 'MaterialIcons': Platform.environment['SF_B3_ICON_FONT']}.entries) {
        if (entry.value == null) continue;
        final loader = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value!).readAsBytes())));
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.timeoutBeforeCommit = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: font == null ? null : 'ChinesePreview'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: boundary,
              child: Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SmartFollowStartPanel(reader: env.reader(), service: env.service, onCreated: (_) {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await configureFollow(tester);
    await tester.ensureVisible(find.byKey(const Key('smart-follow-submit')));
    await tester.tap(find.byKey(const Key('smart-follow-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('结果仍待确认'), findsWidgets);
    final query = find.byKey(const Key('smart-follow-recover-create'));
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pumpAndSettle();
    expect(env.jobs.requests, hasLength(1));
    env.jobs.timeoutBeforeCommit = false;
    expect(tester.takeException(), isNull);
    final directory = Platform.environment['SF_B3_SCREENSHOT_DIR'];
    if (directory != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/creation-pending-360dp-150pct.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.ensureVisible(find.byKey(const Key('smart-follow-submit')));
    await tester.tap(find.byKey(const Key('smart-follow-submit')));
    await tester.pumpAndSettle();
    expect(env.jobs.requests, hasLength(2));
    expect(env.jobs.requests.last.idempotencyKey, env.jobs.requests.first.idempotencyKey);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving during validation cannot send a create request after dispose', (tester) async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartFollowStartPanel(reader: env.reader(), service: env.service, onCreated: (_) => fail('disposed page navigated')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await configureFollow(tester);
    final pending = Completer<void>();
    env.configuration.pending = () async {
      await pending.future;
      return env.configuration.snapshot();
    };
    await tester.ensureVisible(find.byKey(const Key('smart-follow-submit')));
    await tester.tap(find.byKey(const Key('smart-follow-submit')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pumpAndSettle();
    expect(env.jobs.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending request remains queryable after recognition has finished and page reopened', (tester) async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.timeoutBeforeCommit = true;
    try {
      await env.service.start(await env.intent(), env.reader());
    } catch (_) {}
    env.backend.start();
    env.backend.finishRecognition();
    env.jobs.rows.add(env.job(session: 'sf-1'));
    SmartFollowSession? recovered;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartFollowPendingCreation(service: env.newService(), batchId: 'batch-1', isCurrent: () => true, onRecovered: (session) => recovered = session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-pending-query')));
    await tester.pumpAndSettle();
    expect(recovered!.sessionId, 'sf-1');
    expect(env.jobs.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
