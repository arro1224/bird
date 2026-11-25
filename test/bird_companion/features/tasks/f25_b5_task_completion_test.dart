import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nov18_navigation_test_support.dart';

void main() {
  testWidgets('current visible analysis completion navigates once and late old completion cannot re-emit', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    final opened = <String>[];
    await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add), deps);
    deps.eventClient.send(_job(version: 2, done: true));
    await tester.pumpAndSettle();
    expect(opened, ['project-1']);
    deps.eventClient.send(_job(version: 1));
    deps.eventClient.send(_job(version: 2, done: true));
    await tester.pumpAndSettle();
    final controller = tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
    expect(controller.jobs.single.state, BirdJobState.completed);
    expect(opened, ['project-1']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed event from another project only updates that project and never opens its album', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    final opened = <String>[];
    await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add), deps);
    deps.eventClient.send(_job(version: 2, done: true, id: 'other-job', project: 'project-2'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    final controller = tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
    expect(controller.jobs.where((j) => j.sourceProjectId == 'project-2').single.state, BirdJobState.completed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden task tab receives final state without taking the user away', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    final opened = <String>[];
    await pumpB4(
      tester,
      TickerMode(
        enabled: false,
        child: TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add),
      ),
      deps,
    );
    deps.eventClient.send(_job(version: 2, done: true));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    final controller = tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
    expect(controller.jobs.single.state, BirdJobState.completed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final change in ['page', 'device']) {
    testWidgets('completion lookup finishing after $change change cannot navigate', (tester) async {
      final deps = _Dependencies();
      addTearDown(deps.close);
      final opened = <String>[];
      await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add), deps);
      deps.backend.lookup = Completer<String?>();
      deps.eventClient.send(_job(version: 2, done: true));
      await tester.pump();
      await tester.pump();
      expect(deps.backend.lookups, greaterThan(0));
      if (change == 'page') {
        final context = tester.element(find.byType(TaskExperienceRoot));
        unawaited(Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('正在查看其他内容')))));
        await tester.pumpAndSettle();
      } else {
        deps.creation.context = 'box-b|http://new-box';
        deps.deviceSessionCubit.switchDevice();
        await tester.pump();
      }
      deps.backend.lookup!.complete(null);
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      if (change == 'page') expect(find.text('正在查看其他内容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('REST racing with an accepted event keeps newer progress and stale completion has no navigation side effect', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    final opened = <String>[];
    await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add), deps);
    final controller = tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
    deps.jobRepository.gate = Completer<JobPage>();
    final refresh = controller.refreshFromBox();
    deps.eventClient.send(_job(version: 5, progress: .8));
    await tester.pump();
    deps.jobRepository.gate!.complete(JobPage(items: [_job(version: 2, progress: .3)], hasMore: false));
    await tester.pumpAndSettle();
    await refresh;
    deps.eventClient.send(_job(version: 3, done: true));
    await tester.pumpAndSettle();
    expect(controller.jobs.single.version, 5);
    expect(controller.jobs.single.progress, .8);
    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completion lookup cannot navigate after the same job has entered a higher-version retry', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    final opened = <String>[];
    await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}, onAnalysisCompleted: opened.add), deps);
    deps.backend.lookup = Completer<String?>();
    deps.eventClient.send(_job(version: 2, done: true));
    await tester.pump();
    await tester.pump();
    deps.eventClient.send(_job(version: 3));
    await tester.pump();
    deps.backend.lookup!.complete(null);
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('older device current_job cannot overwrite newer terminal from the REST job page', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    deps.deviceRepository.staleJob = _job(version: 1);
    deps.jobRepository.value = _job(version: 5, done: true);
    await pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}), deps);
    final controller = tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
    expect(controller.jobs.single.version, 5);
    expect(controller.jobs.single.state, BirdJobState.completed);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

BirdJobStatus _job({String id = 'job-navigation', String project = 'project-1', int version = 1, bool done = false, double progress = .2}) => BirdJobStatus(
  id: id,
  type: BirdJobType.analysis,
  state: done ? BirdJobState.completed : BirdJobState.running,
  progress: done ? 1 : progress,
  sourceProjectId: project,
  version: version,
  totalCount: 10,
  finishedCount: done ? 10 : (progress * 10).round(),
);

class _Dependencies extends B4Dependencies {
  final _NavigationJobs _jobs = _NavigationJobs();
  final _NavigationEvents _updates = _NavigationEvents();
  @override
  _NavigationJobs get jobRepository => _jobs;
  @override
  _NavigationEvents get eventClient => _updates;
  final backend = _Backend();
  _NavigationDevice? _device;
  @override
  _NavigationDevice get deviceRepository => _device ??= _NavigationDevice(deviceSessionCubit);
  late final _follows = SmartFollowRepository(backend);
  @override
  SmartFollowRepository get smartFollowRepository => _follows;
  @override
  Future<void> close() async {
    _follows.dispose();
    await super.close();
  }
}

class _NavigationJobs extends B4Jobs {
  Completer<JobPage>? gate;
  BirdJobStatus value = _job();
  @override
  Future<JobPage> page({String? state, String? type, String? cursor, int pageSize = 50}) async => gate?.future ?? JobPage(items: [value], hasMore: false);
}

class _NavigationDevice extends B4Device {
  _NavigationDevice(super.session);
  BirdJobStatus? staleJob;
  @override
  Future<DeviceStatus> fetchStatus() async => DeviceStatus(connection: session.state.device!, card: const CardStatus(inserted: true, readable: true), batteryPercent: 80, storageFreeBytes: 1000000, currentJob: staleJob);
}

class _Backend extends FakeSmartFollowBackend {
  Completer<String?>? lookup;
  var lookups = 0;
  @override
  Future<String?> sessionIdForRecognitionJob(String jobId) async {
    lookups++;
    return lookup?.future;
  }
}

class _NavigationEvents extends EventClient {
  final _events = StreamController<DeviceEvent>.broadcast();
  @override
  Stream<DeviceEvent> get events => _events.stream;
  @override
  EventConnectionState get currentState => EventConnectionState.connected;
  void send(BirdJobStatus job) => _events.add(DeviceEvent(type: 'job_updated', payload: job.toJson(), timestamp: DateTime.now()));
  @override
  Future<void> dispose() async {
    await _events.close();
    await super.dispose();
  }
}
