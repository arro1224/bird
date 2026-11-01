import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'completion_fixtures.dart';

void main() {
  testWidgets('production run route opens completion and forwards device-bound RC3 detail', (tester) async {
    final env = CompletionEnvironment();
    final deps = _Dependencies(env);
    CopyJobDetailArgs? opened;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: deps,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(),
          onGenerateRoute: (settings) {
            if (settings.name == BirdRoutes.copyJobDetail) {
              opened = settings.arguments! as CopyJobDetailArgs;
              return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Existing RC3 detail')));
            }
            return BirdAppRouter.onGenerateRoute(settings);
          },
        ),
      ),
    );
    unawaited(navigator.currentState!.pushNamed(BirdRoutes.smartFollowRun, arguments: const SmartFollowRunArgs('sf_fake')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('smart-follow-open-completion')), 300);
    await tester.tap(find.byKey(const Key('smart-follow-open-completion')));
    await tester.pumpAndSettle();
    expect(find.text('跟随复制已完成'), findsOneWidget);
    final history = find.byKey(const Key('sf-completion-history'));
    await tester.scrollUntilVisible(history, 300);
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-completion-child-copy-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-completion-child-copy-1')));
    await tester.pumpAndSettle();
    expect(opened!.copyJobId, 'copy-1');
    expect(opened!.deviceId, 'box-1');
    expect(find.text('Existing RC3 detail'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    deps.deviceSessionCubit.disconnectForTest();
    env.repository.resetForDeviceChange();
    await tester.pumpAndSettle();
    expect(find.text('盒子连接已变化，请重新打开原任务'), findsOneWidget);
    expect(find.text('跟随复制已完成'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
    env.dispose();
  });
}

class _Dependencies implements BirdCompanionDependencies {
  _Dependencies(this.env);
  final CompletionEnvironment env;
  @override
  SmartFollowRepository get smartFollowRepository => env.repository;
  @override
  late final CopyJobRepository copyJobRepository = _CopyJobs(env);
  @override
  late final JobRepository jobRepository = _Jobs(env);
  @override
  final _Session deviceSessionCubit = _Session();
  @override
  final refreshCoordinator = SessionRefreshCoordinator();
  @override
  final apiClient = ApiClient()..configure(Uri.parse('http://127.0.0.1:12345'));
  @override
  Future<void> dispose() async {
    await deviceSessionCubit.events.close();
    await refreshCoordinator.dispose();
    await apiClient.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class _Session implements DeviceSessionCubit {
  final events = StreamController<DeviceSessionState>.broadcast();
  @override
  DeviceSessionState state = DeviceSessionState(
    phase: DeviceSessionPhase.connected,
    device: DeviceConnection(id: 'box-1', name: 'BirdBox', baseUri: Uri.parse('http://127.0.0.1:12345'), networkMode: NetworkMode.lan),
  );
  @override
  Stream<DeviceSessionState> get stream => events.stream;
  void disconnectForTest() {
    state = const DeviceSessionState();
    events.add(state);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _CopyJobs implements CopyJobRepository {
  _CopyJobs(this.env);
  final CompletionEnvironment env;
  @override
  Future<CopyJobDetail> getJob(String id) => env.controller.readChild(id);
  @override
  Future<CopyReport> jobReport(String id) => env.controller.readCopyReport(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Jobs implements JobRepository {
  _Jobs(this.env);
  final CompletionEnvironment env;
  @override
  Future<BirdJobStatus> detail(String id) => env.controller.readRecognition(id);
  @override
  Future<JobReport> report(String id) => env.controller.readRecognitionReport(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
