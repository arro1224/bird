import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_section.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_mode_panel.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/recognition/recognition_repository.dart';
import 'package:aves/bird_companion/features/recognition/recognition_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../copy/fakes/fake_copy_environment.dart';
import 'smart_follow_entry_decision_test.dart' as fixtures;

void main() {
  Future<void> showPanel(WidgetTester tester, SmartFollowEntryDecision decision, {void Function(String)? open}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestModeState(decision: decision, onOpen: open ?? (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SmartFollowEntryDecision decision(BirdJobState? state) => SmartFollowEntryDecision.resolve(batchId: 'batch-1', jobs: state == null ? [] : [fixtures.analysis(state)], capabilities: fixtures.enabled);

  testWidgets('not started offers identify-and-copy without silently starting it', (tester) async {
    await showPanel(tester, decision(null));
    expect(find.text('识别并复制已识别照片'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-start-unconfigured')), findsNothing);
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('smart-follow-start-unconfigured'))).onPressed, isNull);
    expect(find.textContaining('后续本轮符合条件的结果也会加入'), findsOneWidget);
  });

  testWidgets('running has explicit follow and frozen snapshot choices', (tester) async {
    await showPanel(tester, decision(BirdJobState.running));
    expect(find.text('边识别边复制'), findsOneWidget);
    expect(find.text('仅复制当前已识别结果'), findsOneWidget);
    expect(find.textContaining('识别中·仅复制当前结果'), findsOneWidget);
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-select-snapshot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-start-unconfigured')), findsNothing);
  });

  testWidgets('completed recognition only offers snapshot; interrupted directs to original job', (tester) async {
    await showPanel(tester, decision(BirdJobState.completed));
    expect(find.text('复制已识别照片'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-select-mode')), findsNothing);
    await showPanel(tester, decision(BirdJobState.failed));
    expect(find.text('复制当前已完成结果'), findsOneWidget);
    expect(find.textContaining('识别已失败或中断'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-select-mode')), findsNothing);
  });

  testWidgets('missing capability and old box have no executable follow control', (tester) async {
    await showPanel(tester, const SmartFollowEntryDecision(phase: RecognitionEntryPhase.running));
    expect(find.text('当前盒子版本暂不支持边识别边复制。'), findsOneWidget);
    expect(find.byKey(const Key('smart-follow-select-mode')), findsNothing);
    expect(find.byKey(const Key('smart-follow-start-unconfigured')), findsNothing);
  });

  testWidgets('existing session opens original ID and never offers a new follow', (tester) async {
    String? opened;
    await showPanel(
      tester,
      SmartFollowEntryDecision.resolve(batchId: 'batch-1', jobs: [fixtures.analysis(BirdJobState.running)], capabilities: fixtures.enabled, session: fixtures.session()),
      open: (id) => opened = id,
    );
    expect(find.byKey(const Key('smart-follow-select-mode')), findsNothing);
    await tester.tap(find.byKey(const Key('smart-follow-open-existing')));
    expect(opened, 'sf-1');
  });

  testWidgets('mode section drops a previous device response on session change', (tester) async {
    final changes = StreamController<void>.broadcast(sync: true);
    final first = Completer<JobPage>();
    var calls = 0;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => null,
      readPage: (_) {
        calls++;
        return calls == 1 ? first.future : Future.value(JobPage(items: [fixtures.analysis(BirdJobState.completed)], hasMore: false));
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartFollowEntrySection(batchId: 'batch-1', reader: reader, sessionChanges: changes.stream, onModeChanged: (_) {}),
        ),
      ),
    );
    await tester.pump();
    changes.add(null);
    await tester.pumpAndSettle();
    first.complete(JobPage(items: [fixtures.analysis(BirdJobState.running)], hasMore: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('smart-follow-select-mode')), findsNothing);
    expect(find.textContaining('本轮识别已完成'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });

  testWidgets('task recognition dialog keeps unconfigured follow blocked and reuses the original job', (tester) async {
    RecognitionChoice? choice;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => null,
      readPage: (_) async => JobPage(items: [fixtures.analysis(BirdJobState.running)], hasMore: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await chooseRecognitionMode(context, _UnusedRecognitionRepository(), entryReader: reader);
              },
              child: const Text('打开入口'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('recognition-mode-confirm'))).onPressed, isNull);
    expect(choice, isNull);
    await tester.ensureVisible(find.byKey(const Key('smart-follow-select-snapshot')));
    await tester.tap(find.byKey(const Key('smart-follow-select-snapshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recognition-mode-confirm')));
    await tester.pumpAndSettle();
    expect(choice!.config, isNull);
    expect(choice!.existingRecognitionJobId, 'rec-1');
  });

  testWidgets('task recognition dialog adopts an existing session without creating recognition', (tester) async {
    RecognitionChoice? choice;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => fixtures.session(),
      readPage: (_) async => JobPage(items: [fixtures.analysis(BirdJobState.running)], hasMore: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await chooseRecognitionMode(context, _UnusedRecognitionRepository(), entryReader: reader);
              },
              child: const Text('打开入口'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开入口'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-open-existing')));
    await tester.pumpAndSettle();
    expect(choice!.existingSessionId, 'sf-1');
    expect(choice!.config, isNull);
  });

  testWidgets('device change while a task dialog is open discards the old choice', (tester) async {
    var current = true;
    var completed = false;
    RecognitionChoice? choice;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => current,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => null,
      readPage: (_) async => const JobPage(items: [], hasMore: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await chooseRecognitionMode(context, _UnusedRecognitionRepository(), entryReader: reader);
                completed = true;
              },
              child: const Text('打开入口'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开入口'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.byKey(const Key('recognition-mode-confirm')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(choice, isNull);
  });

  testWidgets('refreshing a follow choice never navigates to snapshot without a user click', (tester) async {
    final changes = StreamController<void>.broadcast(sync: true);
    var opened = 0;
    var following = false;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => null,
      readPage: (_) async => JobPage(items: [fixtures.analysis(BirdJobState.running)], hasMore: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartFollowEntrySection(batchId: 'batch-1', reader: reader, sessionChanges: changes.stream, onModeChanged: (value) => following = value, onSnapshot: () => opened++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    expect(following, isTrue);
    changes.add(null);
    changes.add(null);
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(following, isFalse);
    await tester.tap(find.byKey(const Key('smart-follow-select-snapshot')));
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await changes.close();
  });

  testWidgets('copy mode cannot submit static preview while follow is selected', (tester) async {
    final repository = FakeCopyEnvironment();
    final cubit = CopyConfigCubit(repository, batchId: 'batch-1', scope: CopyScope.recognizedAssets, pollInterval: Duration.zero);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => fixtures.enabled,
      readSession: (_) async => null,
      readPage: (_) async => JobPage(items: [fixtures.analysis(BirdJobState.running)], hasMore: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: CopyConfigFlow(
            batchId: 'batch-1',
            recognizedModeBuilder: (_, onMode) => SmartFollowEntrySection(batchId: 'batch-1', reader: reader, onModeChanged: onMode),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('smart-follow-select-mode')));
    await tester.tap(find.byKey(const Key('smart-follow-select-mode')));
    await tester.pumpAndSettle();
    expect(cubit.state.pageActive, isFalse);
    expect(find.byKey(const Key('copy-content-next')), findsNothing);
    expect(repository.previewCalls, 0);
    expect(repository.createCalls, 0);
    await tester.tap(find.byKey(const Key('smart-follow-select-snapshot')));
    await tester.pumpAndSettle();
    expect(cubit.state.scope, CopyScope.recognizedAssets);
    expect(cubit.state.pageActive, isTrue);
    expect(find.byKey(const Key('copy-content-next')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('explicit static scopes never mount the whole-run follow selector', (tester) async {
    for (final scope in [CopyScope.selectedAssets, CopyScope.filteredAssets, CopyScope.batchAllAssets, CopyScope.mediaFullBackup]) {
      final cubit = CopyConfigCubit(FakeCopyEnvironment(), batchId: 'batch-1', scope: scope, pollInterval: Duration.zero);
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: cubit,
            child: CopyConfigFlow(
              batchId: 'batch-1',
              recognizedModeBuilder: (_, _) {
                built++;
                return const Text('unexpected');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(built, 0);
      expect(cubit.state.scope, scope);
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    }
    const args = CopyConfirmationArgs('batch-1', scope: 'filtered_assets', filter: {'contract': 'gallery-filter-v1'});
    expect(args.enableSmartFollow, isFalse);
    expect(CopyConfirmationPage.fromArgs(args: args).enableSmartFollow, isFalse);
  });

  testWidgets('360dp mode panel remains readable at 1.5 text scale', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    final chineseFont = Platform.environment['SF_B1_CHINESE_FONT'];
    if (chineseFont != null) {
      await tester.runAsync(() async {
        final font = FontLoader('SFTestChinese')..addFont(Future.value(ByteData.sublistView(File(chineseFont).readAsBytesSync())));
        await font.load();
        final iconPath = Platform.environment['SF_B1_ICON_FONT'];
        if (iconPath != null) {
          final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File(iconPath).readAsBytesSync())));
          await icons.load();
        }
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: chineseFont == null ? null : 'SFTestChinese'),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: RepaintBoundary(
              key: boundaryKey,
              child: SingleChildScrollView(
                child: _TestModeState(decision: decision(BirdJobState.running), onOpen: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final output = Platform.environment['SF_B1_SCREENSHOT_DIR'];
    if (output != null) {
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$output/modes-running.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}

class _TestModeState extends StatefulWidget {
  const _TestModeState({required this.decision, required this.onOpen});
  final SmartFollowEntryDecision decision;
  final ValueChanged<String> onOpen;
  @override
  State<_TestModeState> createState() => _TestModeStateState();
}

class _UnusedRecognitionRepository implements RecognitionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Mode selection must not read the legacy recognition repository or write a task');
}

class _TestModeStateState extends State<_TestModeState> {
  bool follow = false;
  @override
  Widget build(BuildContext context) => SmartFollowModePanel(decision: widget.decision, followSelected: follow, onModeChanged: (value) => setState(() => follow = value), onOpenSession: widget.onOpen);
}
