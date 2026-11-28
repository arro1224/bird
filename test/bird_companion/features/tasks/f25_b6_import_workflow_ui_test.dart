import 'dart:async';

import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/jobs/data/import_analysis_service.dart';
import 'package:aves/bird_companion/features/jobs/domain/import_analysis_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/presentation/job_center_cubit.dart';
import 'package:aves/bird_companion/features/jobs/presentation/widgets/job_card.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/adapters/job_status_view_adapter.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_detail_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/pages/task_home_page.dart';
import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:aves/bird_companion/features/tasks/presentation/repository_task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nov18_navigation_test_support.dart';
import 'import_analysis_service_test.dart' as fixture;

void main() {
  RepositoryTaskExperienceController controller(WidgetTester tester) => tester.widget<TaskHomePage>(find.byType(TaskHomePage)).controller as RepositoryTaskExperienceController;
  Future<void> mount(WidgetTester tester, _Dependencies deps) => pumpB4(tester, TaskExperienceRoot(onOpenGallery: (_) {}), deps);

  testWidgets('cold production root queries unrecorded owner, merges missing analysis, and never creates analysis on events, polls or reopen', (tester) async {
    final deps = _Dependencies()..existing();
    addTearDown(deps.close);
    deps.jobRepository.omitAnalysis = true;
    await mount(tester, deps);
    expect(deps.importAnalysisService.owns('project-1'), isTrue);
    expect(controller(tester).jobs, hasLength(2));
    expect(controller(tester).currentTaskOrNull!.id, 'import-project-1');
    expect(find.textContaining('AI 识别 · 等待导入完成'), findsOneWidget);
    expect(find.textContaining('导入与索引 · 进行中'), findsOneWidget);
    expect(find.text('0 / 0 张'), findsNothing);
    deps.jobRepository.backend.current['project-1'] = fixture.result('project-1', version: 2, state: BirdJobState.running, dispatch: 'dispatched');
    deps.eventClient.send(deps.jobRepository.backend.current['project-1']!.importJob);
    deps.eventClient.send(deps.jobRepository.backend.current['project-1']!.importJob);
    await tester.pumpAndSettle();
    final refresh = controller(tester).refreshFromBox();
    await tester.pumpAndSettle();
    await refresh;
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, deps);
    expect(controller(tester).jobs.map((j) => j.id).toSet(), {'import-project-1', 'analysis-project-1'});
    expect(deps.jobRepository.legacyAnalysis, 0);
    expect(deps.jobRepository.backend.submissions, isEmpty);
    expect(deps.creation.jobs.requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production start sends one durable automatic import and a delayed duplicate callback reuses it', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    await mount(tester, deps);
    final home = controller(tester);
    final started = home.startImportBatch(' One start ');
    await tester.pumpAndSettle();
    expect(await started, 'project-1');
    final repeated = home.startImportBatch('One start');
    await tester.pumpAndSettle();
    await repeated;
    expect(deps.batchRepository.requests.created, hasLength(1));
    expect(deps.jobRepository.backend.submissions, hasLength(1));
    expect(deps.jobRepository.backend.submissions.single.$2['auto_analysis'], const AutoAnalysisRequest().toJson());
    expect(deps.jobRepository.legacyImport, 0);
    expect(deps.jobRepository.legacyAnalysis, 0);
    expect(home.currentTaskOrNull!.id, 'import-project-1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unqueryable owner blocks legacy cascade and writes instead of assuming no registered analysis', (tester) async {
    final deps = _Dependencies()..existing();
    addTearDown(deps.close);
    deps.jobRepository.omitAnalysis = true;
    deps.jobRepository.backend.current['project-1'] = fixture.result('project-1', version: 2, state: BirdJobState.running, dispatch: 'dispatched');
    deps.jobRepository.backend.readError = StateError('workflow GET unavailable');
    await mount(tester, deps);
    expect(controller(tester).homeInputsReady, isFalse);
    expect(deps.jobRepository.legacyAnalysis, 0);
    expect(deps.jobRepository.backend.submissions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('capability absent keeps legacy import and creates exactly one legacy analysis after import event', (tester) async {
    final deps = _Dependencies()..caps = {};
    addTearDown(deps.close);
    await mount(tester, deps);
    final started = controller(tester).startImportBatch('Legacy');
    await tester.pumpAndSettle();
    await started;
    expect(deps.jobRepository.legacyImport, 1);
    expect(deps.jobRepository.lastLegacyImport!.toJson().containsKey('auto_analysis'), isFalse);
    final completed = fixture.result('project-1', version: 1, dispatch: 'dispatched').importJob;
    deps.eventClient.send(completed);
    deps.eventClient.send(completed);
    await tester.pumpAndSettle();
    expect(deps.jobRepository.legacyAnalysis, 1);
    expect(deps.jobRepository.backend.submissions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown start displays original-request recovery and restores it without another project', (tester) async {
    final deps = _Dependencies();
    addTearDown(deps.close);
    await mount(tester, deps);
    deps.jobRepository.backend.beforeStartError = StateError('lost connection');
    final started = controller(tester).startImportBatch('One start');
    final assertion = expectLater(started, throwsA(isA<ImportAnalysisPending>()));
    await tester.pumpAndSettle();
    await assertion;
    expect(find.text('查询并恢复原开始'), findsOneWidget);
    await tester.tap(find.text('查询并恢复原开始'));
    await tester.pumpAndSettle();
    expect(find.text('查询并恢复原开始'), findsNothing);
    expect(deps.batchRepository.requests.created, hasLength(1));
    expect(deps.jobRepository.backend.submissions.map((s) => s.$3).toSet(), hasLength(1));
    expect(controller(tester).jobs, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('production cancellation with lost ACK retains queued task and pending state instead of local cancelled', (tester) async {
    final deps = _Dependencies()..existing();
    addTearDown(deps.close);
    await mount(tester, deps);
    deps.jobRepository.backend.beforeControlError = const ApiException(message: 'offline after send');
    final cancelled = controller(tester).controlJob('analysis-project-1', TaskAction.cancel);
    final assertion = expectLater(cancelled, throwsA(isA<ImportAnalysisPending>()));
    await tester.pumpAndSettle();
    await assertion;
    final task = controller(tester).taskById('analysis-project-1');
    expect(task.state, TaskRunState.queued);
    expect(task.pendingCancellation, isTrue);
    expect(deps.jobRepository.legacyControl, 0);
    expect(deps.jobRepository.backend.controls.single.$3, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('version changes refresh UI and require a second user operation, never automatic cancellation with newer CAS', (tester) async {
    final deps = _Dependencies()..existing();
    addTearDown(deps.close);
    await mount(tester, deps);
    deps.jobRepository.backend.current['project-1'] = fixture.result('project-1', version: 3, state: BirdJobState.running, dispatch: 'dispatched');
    final cancelled = controller(tester).controlJob('analysis-project-1', TaskAction.cancel);
    final assertion = expectLater(cancelled, throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    await tester.pumpAndSettle();
    await assertion;
    expect(deps.jobRepository.backend.controls, isEmpty);
    expect(controller(tester).jobs.singleWhere((j) => j.id == 'analysis-project-1').version, 3);
    final confirmedAgain = controller(tester).controlJob('analysis-project-1', TaskAction.cancel);
    await tester.pumpAndSettle();
    await confirmedAgain;
    expect(deps.jobRepository.backend.controls.single.$3, 3);
    expect(controller(tester).taskById('analysis-project-1').state, TaskRunState.cancelled);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('waiting-import detail hides percentages and pending cancellation provides query without claiming cancelled', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final task = JobStatusViewAdapter.toTaskSummary(fixture.result('p-1').analysisJob)!.copyWith(pendingCancellation: true);
    final home = TaskExperienceController(const ProductionTaskExperienceDataSource())..replaceRepositoryTasks([task]);
    addTearDown(home.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailPage(controller: home, taskId: task.id),
      ),
    );
    expect(find.textContaining('等待导入完成'), findsWidgets);
    expect(find.text('核对取消结果'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
    expect(find.text('0 / 0'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('已取消'), findsNothing);
  });

  testWidgets('secondary job card also explains waiting import and uncertain cancellation without 0/0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobCard(job: fixture.result('p-1').analysisJob, pendingCancellation: true, onTap: () {}),
        ),
      ),
    );
    expect(find.text('导入完成后由盒子自动开始识别'), findsOneWidget);
    expect(find.text('取消待确认'), findsOneWidget);
    expect(find.text('核对取消结果'), findsOneWidget);
    expect(find.text('0 / 0'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  test('secondary job center uses same durable cancellation service and reconciles unknown ACK', () async {
    final deps = _Dependencies()..existing();
    addTearDown(deps.close);
    final cubit = JobCenterCubit(deps.jobRepository, null, null, null, deps.importAnalysisService);
    addTearDown(cubit.close);
    await cubit.load();
    deps.jobRepository.backend.beforeControlError = const ApiException(message: 'lost');
    await cubit.control('analysis-project-1', 'cancel');
    expect(cubit.state.error, isA<ImportAnalysisPending>());
    expect(cubit.cancellationPending('analysis-project-1'), isTrue);
    expect(deps.jobRepository.legacyControl, 0);
    deps.jobRepository.backend.current['project-1'] = fixture.result('project-1', version: 1, state: BirdJobState.cancelled);
    await cubit.load();
    expect(cubit.cancellationPending('analysis-project-1'), isFalse);
    expect(cubit.state.jobs.singleWhere((j) => j.id == 'analysis-project-1').state, BirdJobState.cancelled);
  });
}

class _Dependencies extends B4Dependencies {
  final _jobs = _Jobs();
  final _projects = _Projects();
  final _events = _Events();
  Map<String, dynamic> caps = fixture.capability();
  @override
  _Jobs get jobRepository => _jobs;
  @override
  _Projects get batchRepository => _projects;
  @override
  _Events get eventClient => _events;
  @override
  ImportAnalysisService get importAnalysisService => _workflow;
  late final _workflow = ImportAnalysisService(
    repository: _jobs,
    batches: _projects,
    cache: cache,
    readCapabilities: () async => caps,
    deviceId: () => deviceSessionCubit.state.device?.id,
    contextKey: () => deviceSessionCubit.state.device?.id,
  );
  void existing() {
    _projects.hasExisting = true;
    _jobs.backend.current['project-1'] = fixture.result('project-1');
  }
}

class _Projects extends B4Batches {
  final requests = fixture.Projects();
  bool hasExisting = false;
  @override
  Future<BatchSummary?> current() async => requests.created.values.lastOrNull ?? (hasExisting ? B4Batches.batch : null);
  @override
  Future<BatchSummary> create(ProjectCreateRequest request) async {
    if (request.idempotencyKey == null) {
      hasExisting = true;
      return B4Batches.batch;
    }
    return requests.create(request);
  }
}

class _Jobs extends B4Jobs implements ImportWorkflowRepository {
  final backend = fixture.Backend();
  bool omitAnalysis = false;
  int legacyImport = 0, legacyAnalysis = 0, legacyControl = 0;
  ImportJobRequest? lastLegacyImport;
  final legacy = <BirdJobStatus>[];
  @override
  Future<JobPage> page({String? state, String? type, String? cursor, int pageSize = 50}) async => JobPage(
    items: [
      for (final result in backend.current.values) result.importJob,
      for (final result in backend.current.values)
        if (!omitAnalysis) result.analysisJob,
      ...legacy,
    ],
    hasMore: false,
  );
  @override
  Future<BirdJobStatus> detail(String id) async => [
    ...backend.current.values.expand((r) => [r.importJob, r.analysisJob]),
    ...legacy,
  ].singleWhere((j) => j.id == id);
  @override
  Future<ImportStartResult> startImportWorkflow(String projectId, Map<String, dynamic> request, String key) => backend.startImportWorkflow(projectId, request, key);
  @override
  Future<ImportStartResult> importWorkflow(String projectId) => backend.importWorkflow(projectId);
  @override
  Future<BirdJobStatus> controlWorkflowJob(String id, String action, int version, String key) => backend.controlWorkflowJob(id, action, version, key);
  @override
  Future<BirdJobStatus> createImport(String projectId, ImportJobRequest request) async {
    legacyImport++;
    lastLegacyImport = request;
    final job = fixture.result(projectId).importJob;
    legacy.add(job);
    return job;
  }

  @override
  Future<BirdJobStatus> createAnalysis(String projectId, AnalysisJobRequest request) async {
    legacyAnalysis++;
    final job = fixture.result(projectId).analysisJob;
    legacy.add(job);
    return job;
  }

  @override
  Future<BirdJobStatus> control(String id, String action, {int? version}) async {
    legacyControl++;
    return detail(id);
  }
}

class _Events extends EventClient {
  final _updates = StreamController<DeviceEvent>.broadcast();
  @override
  Stream<DeviceEvent> get events => _updates.stream;
  @override
  EventConnectionState get currentState => EventConnectionState.connected;
  void send(BirdJobStatus job) => _updates.add(DeviceEvent(type: 'job_updated', payload: job.toJson(), timestamp: DateTime.now()));
  @override
  Future<void> dispose() async {
    await _updates.close();
    await super.dispose();
  }
}
