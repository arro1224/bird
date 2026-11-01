import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecoveryBackend extends FakeSmartFollowBackend {
  int reads = 0;
  bool failReads = false;
  Completer<SmartFollowSession>? gate;
  @override
  Future<SmartFollowSession> session(String sessionId) async {
    ++reads;
    if (failReads) throw StateError('offline');
    return gate == null ? super.session(sessionId) : gate!.future;
  }
}

void main() {
  late RecoveryBackend backend;
  late SmartFollowRepository repository;
  late StreamController<void> wakeups;
  late bool current;
  var processed = 1;
  setUp(() {
    backend = RecoveryBackend()..start();
    repository = SmartFollowRepository(backend);
    wakeups = StreamController<void>.broadcast();
    current = true;
    processed = 1;
  });
  tearDown(() async {
    repository.dispose();
    await wakeups.close();
  });
  Widget host() => MaterialApp(
    home: SmartFollowRunPage(
      repository: repository,
      sessionId: 'sf_fake',
      isCurrent: () => current,
      refreshSignals: wakeups.stream,
      pollInterval: const Duration(seconds: 1),
      readRecognition: (id) async => BirdJobStatus(id: id, type: BirdJobType.analysis, state: BirdJobState.running, totalCount: 10, finishedCount: processed),
    ),
  );

  testWidgets('polling updates recognition progress from job facts, not opening args', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('识别 1 / 10'), findsOneWidget);
    processed = 7;
    backend.commitPhoto();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('识别 7 / 10'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('smart-follow-eligible'))).data, '1 张');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background stops polling; resume immediately catches up', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final before = backend.reads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 30));
    expect(backend.reads, before);
    processed = 9;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('识别 9 / 10'), findsOneWidget);
    expect(backend.reads, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening a child route pauses polling and returning refreshes current facts', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(SmartFollowRunPage)));
    unawaited(navigator.push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('复制批次详情')))));
    await tester.pumpAndSettle();
    final before = backend.reads;
    processed = 8;
    await tester.pump(const Duration(seconds: 20));
    expect(backend.reads, before);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('识别 8 / 10'), findsOneWidget);
    expect(backend.reads, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed reads back off and stale actions are disabled until successful reload', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    backend.failReads = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-stale')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('smart-follow-action-pause'))).onPressed, isNull);
    final afterFailure = backend.reads;
    await tester.pump(const Duration(seconds: 1));
    expect(backend.reads, afterFailure);
    backend.failReads = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-stale')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reconnect signals refresh without duplicate concurrent reads', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    backend.gate = Completer();
    final before = backend.reads;
    wakeups.add(null);
    wakeups.add(null);
    wakeups.add(null);
    await tester.pump();
    expect(backend.reads, before + 1);
    backend.gate!.complete(backend.current);
    backend.gate = null;
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device change hides old facts and disables access to old actions', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    current = false;
    wakeups.add(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('盒子连接已变化'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-action-pause')), findsNothing);
    final before = backend.reads;
    await tester.pump(const Duration(seconds: 20));
    expect(backend.reads, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recognition ending retains draining until backend completes the queue', (tester) async {
    backend.commitPhoto();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    backend.finishRecognition();
    processed = 10;
    wakeups.add(null);
    await tester.pumpAndSettle();
    expect(find.text('识别结束·正在完成剩余复制'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-open-completion')), findsNothing);
    backend.completeChildJobs();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
