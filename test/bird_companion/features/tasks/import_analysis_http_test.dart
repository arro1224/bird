import 'dart:io';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/jobs/data/import_analysis_service.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_repository_impl.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_analysis_service_test.dart' as fixture;

void main() {
  late MockBoxServer box;
  late ApiClient client;
  late JobRepositoryImpl jobs;
  late BatchRepositoryImpl projects;
  late fixture.Store cache;
  late DateTime now;
  late Dio dio;
  final requests = <(String, String, String?)>[];
  Future<void> open({bool ticker = false, bool noCandidates = false, File? state}) async {
    now = DateTime.utc(2026, 11, 26);
    box = MockBoxServer(
      photoCount: 5,
      logRequests: false,
      importAnalysisWorkflow: true,
      importAnalysisNoCandidates: noCandidates,
      workflowAutoAdvance: ticker,
      stateFile: state,
      clock: () => now,
      requestOverride: (request) async {
        requests.add((request.method, request.uri.path, request.headers.value('Idempotency-Key')));
        return false;
      },
    );
    final uri = await box.start();
    dio = Dio();
    client = ApiClient(dio: dio)..configure(uri);
    jobs = JobRepositoryImpl(JobApi(client));
    projects = BatchRepositoryImpl(BatchApi(client));
  }

  ImportAnalysisService phone() =>
      ImportAnalysisService(repository: jobs, batches: projects, cache: cache, readCapabilities: () => client.get('/api/v1/recognition-capabilities'), deviceId: () => 'box-a', contextKey: () => 'box-a|${box.baseUri}');
  Future<String> project() async => (await projects.create(const ProjectCreateRequest(name: 'B6 HTTP', cardId: 'card-mock-001', idempotencyKey: 'project-key'))).id;
  final body = const ImportJobRequest(autoAnalysis: AutoAnalysisRequest()).toJson();
  setUp(() {
    cache = fixture.Store();
    requests.clear();
  });
  tearDown(() async {
    await client.dispose();
    dio.close(force: true);
    await box.close();
  });

  test('real HTTP full envelope keeps both jobs; replay remains first receipt while GET is current', () async {
    await open();
    final id = await project();
    final first = await jobs.startImportWorkflow(id, body, 'import-key');
    expect(first.analysisJob.workflowStage, 'waiting_import');
    expect(first.analysisJob.totalCount, 0);
    expect(first.workflow.projectId, id);
    expect(first.workflow.importJobId, first.importJob.id);
    expect(first.workflow.analysisJobId, first.analysisJob.id);
    await box.completeJob(first.importJob.id);
    final replay = await jobs.startImportWorkflow(id, body, 'import-key');
    expect(replay.analysisJob.state, BirdJobState.queued);
    final current = await jobs.importWorkflow(id);
    expect(current.analysisJob.state, BirdJobState.running);
    expect(current.workflow.dispatchState, 'dispatched');
    expect(box.jobs.where((j) => j['source_project_id'] == id), hasLength(2));
    expect(requests.where((r) => r.$1 == 'POST' && r.$2.endsWith('/imports')).map((r) => r.$3), everyElement('import-key'));
    // Other ApiClient GET consumers still receive unwrapped data.
    expect((await BatchApi(client).current())!.id, id);
  });

  test('same key with changed project or import parameters returns a conflict rather than another pair', () async {
    await open();
    final id = await project();
    await expectLater(projects.create(const ProjectCreateRequest(name: 'Changed', cardId: 'card-mock-001', idempotencyKey: 'project-key')), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_conflict')));
    await jobs.startImportWorkflow(id, body, 'import-key');
    final changed = fixture.clone(body);
    (changed['auto_analysis'] as Map)['include_grouping'] = false;
    await expectLater(jobs.startImportWorkflow(id, changed, 'import-key'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_conflict')));
    expect(box.jobs.where((j) => j['source_project_id'] == id), hasLength(2));
  });

  for (final route in ['projects', 'imports']) {
    test('lost $route HTTP response recovers original keys against actual server after phone restart', () async {
      await open();
      var lose = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            if (lose && response.requestOptions.path.endsWith('/$route') && response.requestOptions.method == 'POST') {
              lose = false;
              handler.reject(DioException(requestOptions: response.requestOptions, type: DioExceptionType.connectionError));
            } else {
              handler.next(response);
            }
          },
        ),
      );
      final oldPhone = phone();
      await expectLater(oldPhone.start(name: 'Lost ACK', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest()), throwsA(isA<ImportAnalysisPending>()));
      final restored = phone();
      final result = await restored.resumePending();
      expect(restored.hasPendingStart, isFalse);
      expect(box.jobs.where((j) => j['source_project_id'] == result.workflow.projectId), hasLength(2));
      for (final path in ['/api/v1/projects', '/api/v1/projects/${result.workflow.projectId}/imports']) {
        expect(requests.where((r) => r.$1 == 'POST' && r.$2 == path).map((r) => r.$3).toSet(), hasLength(1));
      }
      expect((await BatchApi(client).page()).items.where((p) => p.name == 'Lost ACK'), hasLength(1));
    });
  }

  test('independent server timer completes import then analysis while phone makes no requests; reopen uses same IDs', () async {
    await open(ticker: true);
    final started = await phone().start(name: 'Phone closed', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    final before = requests.length;
    now = now.add(const Duration(seconds: 13));
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    expect(box.jobs.singleWhere((j) => j['job_id'] == started.importJob.id)['job_state'], 'completed');
    now = now.add(const Duration(seconds: 13));
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    expect(box.jobs.singleWhere((j) => j['job_id'] == started.analysisJob.id)['job_state'], 'completed');
    expect(requests, hasLength(before));
    final reopened = phone();
    await reopened.restoreActive();
    expect(reopened.snapshot(started.workflow.projectId)!.analysisJob.state, BirdJobState.completed);
    expect(box.jobs.where((j) => j['source_project_id'] == started.workflow.projectId), hasLength(2));
    expect(requests.where((r) => r.$1 == 'POST' && r.$2.endsWith('/analysis-jobs')), isEmpty);
  });

  test('cancel registered queued analysis prevents dispatch after import completion and replay', () async {
    await open();
    final service = phone();
    final started = await service.start(name: 'Cancel before import', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    await service.controlAnalysis(started.workflow.projectId, 'cancel', started.analysisJob.version!);
    await box.completeJob(started.importJob.id);
    final restored = await phone().refresh(started.workflow.projectId);
    expect(restored.analysisJob.state, BirdJobState.cancelled);
    expect(restored.workflow.dispatchState, 'stopped');
    final actions = requests.where((r) => r.$1 == 'POST' && r.$2.endsWith('/actions'));
    expect(actions.single.$3, isNotEmpty);
    expect(box.jobs.where((j) => j['job_type'] == 'analysis'), hasLength(1));
  });

  test('source import failure stops original analysis with actual source error', () async {
    await open();
    final service = phone();
    final started = await service.start(name: 'Failure', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    await box.failJob(started.importJob.id);
    final failed = await service.refresh(started.workflow.projectId);
    expect(failed.analysisJob.state, BirdJobState.failed);
    expect(failed.analysisJob.errorCode, 'source_import_failed');
    expect(failed.workflow.dispatchState, 'stopped');
  });

  test('changed source card is rejected without stripping auto_analysis or submitting analysis', () async {
    await open();
    final id = await project();
    box.importSourceCardId = 'replacement-card';
    await expectLater(jobs.startImportWorkflow(id, body, 'import-key'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'source_card_changed')));
    expect(box.jobs, isEmpty);
  });

  test('no candidates explicitly completes registered zero-count analysis without running pipeline', () async {
    await open(noCandidates: true);
    final service = phone();
    final started = await service.start(name: 'No candidates', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    await box.completeJob(started.importJob.id);
    final done = await service.refresh(started.workflow.projectId);
    expect(done.workflow.dispatchState, 'no_candidates');
    expect(done.analysisJob.state, BirdJobState.completed);
    expect(done.analysisJob.totalCount, 0);
    expect(box.jobs.where((j) => j['job_type'] == 'analysis'), hasLength(1));
  });

  test('one follow session retains confirmed target, pair, conflict and metadata choices on duplicate start', () async {
    await open();
    final service = phone();
    const follow = SmartFollowStartRequest(targetMediaId: 'media_usb_mock_001', reviewExportEnabled: true, continuousQueue: true, pairPolicy: 'both', conflictStrategy: 'keep_both');
    final started = await service.start(
      name: 'With follow',
      cardId: 'card-mock-001',
      analysis: const AutoAnalysisRequest(smartFollow: follow),
    );
    final again = await service.start(
      name: 'With follow',
      cardId: 'card-mock-001',
      analysis: const AutoAnalysisRequest(smartFollow: follow),
    );
    expect(started.workflow.sessionId, isNotNull);
    expect(again.workflow.sessionId, started.workflow.sessionId);
    final status = await client.get('/api/v1/projects/${started.workflow.projectId}/import-analysis');
    expect((status['auto_analysis'] as Map)['smart_follow'], const AutoAnalysisRequest(smartFollow: follow).toJson()['smart_follow']);
    expect(box.jobs.where((j) => j['job_type'] == 'analysis'), hasLength(1));
  });

  test('box-owned manual analysis and active deletion return explainable errors', () async {
    await open();
    final service = phone();
    final started = await service.start(name: 'Owner', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    await expectLater(jobs.createAnalysis(started.workflow.projectId, const AnalysisJobRequest()), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_owned')));
    await expectLater(jobs.delete(started.analysisJob.id), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_active')));
    expect(box.jobs, hasLength(2));
  });

  test('server restart restores failed original IDs as backend_restarted and never creates a new workflow', () async {
    final directory = await Directory.systemTemp.createTemp('bird-b6-restart-');
    final state = File('${directory.path}/box.json');
    addTearDown(() async {
      if (await state.exists()) await state.delete();
      await directory.delete();
    });
    await open(state: state);
    final started = await phone().start(name: 'Backend restart', cardId: 'card-mock-001', analysis: const AutoAnalysisRequest());
    await client.dispose();
    dio.close(force: true);
    await box.close();
    await open(state: state);
    final reopened = phone();
    await reopened.restoreActive();
    final failed = reopened.snapshot(started.workflow.projectId)!;
    expect(failed.importJob.id, started.importJob.id);
    expect(failed.analysisJob.id, started.analysisJob.id);
    expect(failed.analysisJob.state, BirdJobState.failed);
    expect(failed.analysisJob.errorCode, 'backend_restarted');
    expect(box.jobs, hasLength(2));
  });
}
