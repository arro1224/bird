import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/batches/domain/project_create_request.dart';
import 'package:aves/bird_companion/features/jobs/data/import_analysis_service.dart';
import 'package:aves/bird_companion/features/jobs/domain/import_analysis_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> capability({bool follow = true}) => {
  'import_analysis_workflow': {
    'available': true,
    'contract_version': 'import-analysis-v1',
    'owner': 'box',
    'request_field': 'auto_analysis',
    'status_path': '/api/v1/projects/{project_id}/import-analysis',
    'smart_follow_available': follow,
  },
};

void main() {
  test('capability is explicit, keeps legacy absent/false branch, and does not guess unknown contracts', () {
    expect(ImportAnalysisCapability.fromJson({}).available, isFalse);
    expect(
      ImportAnalysisCapability.fromJson({
        'import_analysis_workflow': {'available': false},
      }).available,
      isFalse,
    );
    expect(ImportAnalysisCapability.fromJson(capability(follow: false)).smartFollowAvailable, isFalse);
    for (final field in ['owner', 'contract_version', 'request_field', 'status_path', 'smart_follow_available']) {
      final json = capability();
      (json['import_analysis_workflow'] as Map).remove(field);
      expect(() => ImportAnalysisCapability.fromJson(json), throwsA(isA<ProtocolCompatibilityException>()), reason: field);
    }
  });

  test('new request maps modes and all chosen copy policies without legacy standard mode', () {
    const follow = SmartFollowStartRequest(targetMediaId: 'usb-1', reviewExportEnabled: true, continuousQueue: true, pairPolicy: 'both', conflictStrategy: 'keep_both');
    final request = const ImportJobRequest(
      autoAnalysis: AutoAnalysisRequest(includeGrouping: false, smartFollow: follow),
      idempotencyKey: 'transport-only',
    ).toJson();
    expect(request['auto_analysis'], {
      'mode': 'new_only',
      'existing_result_policy': 'skip',
      'include_grouping': false,
      'smart_follow': {'target_media_id': 'usb-1', 'eligibility_mode': 'recognized_only_v1', 'pair_policy': 'both', 'conflict_strategy': 'keep_both', 'review_export_enabled': true},
    });
    expect(jsonEncode(request), isNot(contains('standard')));
    expect(jsonEncode(request), isNot(contains('transport-only')));
    expect(const ImportJobRequest().toJson().containsKey('auto_analysis'), isFalse);
  });

  test('complete envelope validates ownership, both jobs and project association', () {
    final original = result('p-1');
    final envelope = {'data': original.importJob.toJson(), 'workflow': original.workflow.toJson(), 'analysis_job': original.analysisJob.toJson()};
    expect(ImportStartResult.fromEnvelope(envelope, projectId: 'p-1').analysisJob.workflowStage, 'waiting_import');
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (j) => (j['workflow'] as Map)['owner'] = 'phone',
      (j) => (j['workflow'] as Map)['project_id'] = 'another',
      (j) => (j['analysis_job'] as Map)['job_id'] = 'other-job',
      (j) => (j['analysis_job'] as Map)['source_project_id'] = 'another',
      (j) => j.remove('analysis_job'),
    ]) {
      final json = clone(envelope);
      mutation(json);
      expect(() => ImportStartResult.fromEnvelope(json, projectId: 'p-1'), throwsA(isA<ProtocolCompatibilityException>()));
    }
  });

  test('first project POST and import POST follow durable requests/keys; GET supplies actual current state', () async {
    final env = Environment()..backend.advanceOnStart = true;
    env.projects.beforeCreate = () {
      final row = env.records.single;
      expect(row['project_request'], {'name': 'One start', 'card_id': 'card-1'});
      expect(row['project_key'], isNotEmpty);
      expect((row['import_request'] as Map)['auto_analysis'], isA<Map>());
    };
    env.backend.beforeStart = () {
      final row = env.records.single;
      expect(row['sent'], true);
      expect(row['project_id'], 'project-1');
      expect(row['import_key'], isNotEmpty);
    };
    final started = await env.start();
    expect(started.analysisJob.state, BirdJobState.running);
    expect(started.analysisJob.version, 2);
    expect(env.service.owns('project-1'), isTrue);
    expect(env.service.hasPendingStart, isFalse);
    expect(env.backend.submissions, hasLength(1));
    expect(env.backend.reads, ['project-1']);
  });

  test('journal write failure sends neither project nor import', () async {
    final env = Environment()..store.failWrites = true;
    await expectLater(env.start(), throwsStateError);
    expect(env.projects.calls, isEmpty);
    expect(env.backend.submissions, isEmpty);
  });

  for (final after in [false, true]) {
    test('project response loss ${after ? 'after' : 'before'} commit recovers same key across service restart', () async {
      final env = Environment();
      if (after) {
        env.projects.afterError = StateError('lost response');
      } else {
        env.projects.beforeError = StateError('never reached box');
      }
      await expectLater(env.start(), throwsA(isA<ImportAnalysisPending>()));
      expect(env.service.hasPendingStart, isTrue);
      env.restartPhone();
      final recovered = await env.service.resumePending();
      expect(recovered.workflow.projectId, 'project-1');
      expect(env.projects.calls.map((r) => r.idempotencyKey).toSet(), hasLength(1));
      expect(env.projects.created, hasLength(1));
      expect(env.backend.submissions, hasLength(1));
    });
  }

  for (final after in [false, true]) {
    test('import response loss ${after ? 'after' : 'before'} commit never creates another project or another pair', () async {
      final env = Environment();
      if (after) {
        env.backend.afterStartError = StateError('lost response');
      } else {
        env.backend.beforeStartError = StateError('not accepted');
      }
      await expectLater(env.start(), throwsA(isA<ImportAnalysisPending>()));
      final original = env.records.single;
      env.restartPhone();
      final recovered = await env.service.resumePending();
      expect(recovered.workflow.importJobId, 'import-project-1');
      expect(env.projects.created, hasLength(1));
      expect(env.backend.receipts, hasLength(1));
      for (final call in env.backend.submissions) {
        expect(call.$3, original['import_key']);
        expect(call.$2, original['import_request']);
      }
      expect(env.backend.submissions, hasLength(after ? 1 : 2));
    });
  }

  test('simultaneous taps and repeated callback after success reuse one logical start', () async {
    final env = Environment()..backend.startGate = Completer<void>();
    final one = env.start();
    final two = env.start();
    await Future<void>.delayed(Duration.zero);
    env.backend.startGate!.complete();
    expect((await one).workflow.analysisJobId, (await two).workflow.analysisJobId);
    await env.start();
    expect(env.projects.created, hasLength(1));
    expect(env.backend.submissions, hasLength(1));
    await env.service.start(name: 'One start', cardId: 'card-1', analysis: const AutoAnalysisRequest(), intentId: 'explicit-new-form');
    expect(env.projects.created, hasLength(2));
  });

  test('unresolved original request blocks different name/card or copied strategy and retains all parameters', () async {
    final env = Environment()..backend.beforeStartError = StateError('offline');
    const analysis = AutoAnalysisRequest(
      smartFollow: SmartFollowStartRequest(targetMediaId: 'usb-1', reviewExportEnabled: true, pairPolicy: 'both', conflictStrategy: 'keep_both', continuousQueue: true),
    );
    await expectLater(env.service.start(name: 'One start', cardId: 'card-1', analysis: analysis), throwsA(isA<ImportAnalysisPending>()));
    await expectLater(env.service.start(name: 'Different', cardId: 'card-2', analysis: const AutoAnalysisRequest()), throwsA(isA<ImportAnalysisPending>()));
    env.restartPhone();
    final recovered = await env.service.resumePending();
    expect(recovered.workflow.sessionId, 'session-project-1');
    expect(env.backend.submissions.last.$2['auto_analysis'], analysis.toJson());
    expect(env.projects.created, hasLength(1));
  });

  test('follow capability false refuses before creating a project and never downgrades', () async {
    final env = Environment()..caps = capability(follow: false);
    await expectLater(
      env.service.start(
        name: 'One start',
        cardId: 'card-1',
        analysis: const AutoAnalysisRequest(smartFollow: SmartFollowStartRequest(targetMediaId: 'usb', reviewExportEnabled: false)),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'smart_follow_unavailable')),
    );
    expect(env.projects.calls, isEmpty);
    expect(env.backend.submissions, isEmpty);
  });

  for (final code in ['source_card_changed', 'smart_follow_metadata_not_supported', 'import_analysis_invalid']) {
    test('$code rejection keeps original body and never submits a field-stripped request', () async {
      final env = Environment()..backend.beforeStartError = ApiException(message: 'definite rejection', code: code, statusCode: code == 'source_card_changed' ? 409 : 422);
      await expectLater(env.start(), throwsA(isA<ApiException>()));
      final original = clone(env.backend.submissions.single.$2);
      await expectLater(env.start(), throwsA(isA<ApiException>()));
      expect(env.backend.submissions, hasLength(1));
      expect(env.records.single['import_request'], original);
      expect(original['auto_analysis'], isA<Map>());
    });
  }

  test('malformed or missing workflow siblings retain ownership and original POST for recovery', () async {
    final env = Environment()..backend.afterStartError = const ProtocolCompatibilityException('workflow', 'missing');
    await expectLater(env.start(), throwsA(isA<ProtocolCompatibilityException>()));
    expect(env.service.owns('project-1'), isTrue);
    env.restartPhone();
    expect((await env.service.resumePending()).workflow.projectId, 'project-1');
    expect(env.backend.submissions, hasLength(1));
  });

  test('requested follow without returned session is not silently accepted as ordinary analysis', () async {
    final env = Environment()..backend.omitSession = true;
    await expectLater(
      env.service.start(
        name: 'One start',
        cardId: 'card-1',
        analysis: const AutoAnalysisRequest(smartFollow: SmartFollowStartRequest(targetMediaId: 'usb', reviewExportEnabled: false)),
      ),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
    expect(env.service.hasPendingStart, isTrue);
    expect(env.backend.submissions, hasLength(1));
  });

  test('unknown local owner first queries box; a timeout does not imply legacy ownership', () async {
    final env = Environment();
    env.backend.current['external'] = result('external');
    expect(await env.service.ensureOwner('external'), isTrue);
    expect(env.service.owns('external'), isTrue);
    expect(env.backend.submissions, isEmpty);
    final failing = Environment()..backend.readError = StateError('cannot query');
    await expectLater(failing.service.ensureOwner('external'), throwsStateError);
    expect(failing.backend.submissions, isEmpty);
  });

  test('only explicit missing workflow permits old project fallback; managed intent never does', () async {
    final env = Environment();
    expect(await env.service.ensureOwner('old-project'), isFalse);
    await env.start();
    env.backend.current.clear();
    expect(await env.service.ensureOwner('project-1'), isTrue);
    expect(env.service.owns('project-1'), isTrue);
  });

  test('restart restores same IDs, not stale replay state, and does not POST again', () async {
    final env = Environment();
    await env.start();
    env.backend.current['project-1'] = result('project-1', version: 5, state: BirdJobState.completed, dispatch: 'no_candidates');
    env.restartPhone();
    await env.service.restoreActive();
    expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.completed);
    expect(env.backend.submissions, hasLength(1));
    env.backend.current['project-1'] = result('project-1', version: 2, state: BirdJobState.running, dispatch: 'dispatched');
    await env.service.refresh('project-1');
    expect(env.service.snapshot('project-1')!.analysisJob.version, 5);
  });

  test('same workflow cannot change job identifiers during recovery', () async {
    final env = Environment();
    await env.start();
    final other = result('project-1');
    final changed = other.toSnapshot()..['analysis_job_id'] = 'new-analysis';
    (changed['analysis_job'] as Map)['job_id'] = 'new-analysis';
    env.backend.current['project-1'] = ImportStartResult.fromSnapshot(changed, projectId: 'project-1');
    await expectLater(env.service.refresh('project-1'), throwsA(isA<ProtocolCompatibilityException>()));
    expect(env.service.snapshot('project-1')!.analysisJob.id, 'analysis-project-1');
  });

  test('late project response after device change cannot import into another device', () async {
    final env = Environment()..projects.gate = Completer<void>();
    final pending = env.start();
    final assertion = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    env.device = 'box-b';
    env.context = 'box-b|new-endpoint';
    env.projects.gate!.complete();
    await assertion;
    expect(env.backend.submissions, isEmpty);
    expect(env.service.snapshots, isEmpty);
    env.device = 'box-a';
    env.context = 'box-a|endpoint';
    env.restartPhone();
    await env.service.resumePending();
    expect(env.projects.created, hasLength(1));
  });

  test('corrupt or future journal is retained rather than replaced by a new start', () async {
    final env = Environment();
    env.store.values['import-analysis-intents:v1:box-a'] = {'format': 2, 'records': {}};
    await expectLater(env.start(), throwsA(isA<ProtocolCompatibilityException>()));
    expect(env.projects.calls, isEmpty);
    expect((env.store.values['import-analysis-intents:v1:box-a'] as Map)['format'], 2);
  });

  test('pre-import cancellation persists stable job action key and confirms only box state', () async {
    final env = Environment();
    await env.start();
    final job = await env.service.controlAnalysis('project-1', 'cancel', 0);
    expect(job.state, BirdJobState.cancelled);
    expect(env.service.cancelPending(job.id), isFalse);
    expect(env.backend.controls.single, ('analysis-project-1', 'cancel', 0, 'import-analysis-analysis-project-1-cancel-0'));
    env.restartPhone();
    await env.service.restoreActive();
    expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.cancelled);
    expect(env.backend.submissions, hasLength(1));
  });

  for (final applied in [false, true]) {
    test('unknown cancel ${applied ? 'after' : 'before'} commit stays pending and replays no newer version', () async {
      final env = Environment();
      await env.start();
      if (applied) {
        env.backend.afterControlError = const ApiException(message: 'lost ACK');
      } else {
        env.backend.beforeControlError = const ApiException(message: 'not received');
      }
      await expectLater(env.service.controlAnalysis('project-1', 'cancel', 0), throwsA(isA<ImportAnalysisPending>().having((e) => e.cancel, 'cancel', true)));
      expect(env.service.cancelPending('analysis-project-1'), isTrue);
      expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.queued);
      env.restartPhone();
      final recovered = await env.service.controlAnalysis('project-1', 'cancel', 0);
      expect(recovered.state, BirdJobState.cancelled);
      expect(env.backend.controls.map((c) => c.$4).toSet(), hasLength(1));
      expect(env.backend.controls, hasLength(applied ? 1 : 2));
    });
  }

  test('pending cancel encountering newer run requires fresh user confirmation and sends no changed CAS', () async {
    final env = Environment();
    await env.start();
    env.backend.beforeControlError = const ApiException(message: 'lost');
    await expectLater(env.service.controlAnalysis('project-1', 'cancel', 0), throwsA(isA<ImportAnalysisPending>()));
    env.backend.current['project-1'] = result('project-1', version: 3, state: BirdJobState.running, dispatch: 'dispatched');
    await expectLater(env.service.controlAnalysis('project-1', 'cancel', 3), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    expect(env.backend.controls, hasLength(1));
    expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.running);
  });

  test('definite not-prepared action rejection is explained and does not leave false cancellation pending', () async {
    final env = Environment();
    await env.start();
    env.backend.beforeControlError = const ApiException(message: 'not ready', code: 'import_analysis_not_prepared', statusCode: 422);
    await expectLater(env.service.controlAnalysis('project-1', 'cancel', 0), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_not_prepared')));
    expect(env.service.cancelPending('analysis-project-1'), isFalse);
  });

  test('late original POST receipt cannot erase a cancellation recorded after a successful recovery GET', () async {
    final env = Environment()..backend.responseGate = Completer<void>();
    final starting = env.start();
    final assertion = expectLater(starting, throwsA(isA<ImportAnalysisPending>()));
    while (env.backend.current.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await env.service.refresh('project-1');
    env.backend.beforeControlError = const ApiException(message: 'lost cancel');
    await expectLater(env.service.controlAnalysis('project-1', 'cancel', 0), throwsA(isA<ImportAnalysisPending>()));
    env.backend.readError = StateError('status offline');
    env.backend.responseGate!.complete();
    await assertion;
    expect(env.service.cancelPending('analysis-project-1'), isTrue);
    expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.queued);
    env.backend.readError = null;
    await env.service.controlAnalysis('project-1', 'cancel', 0);
    expect(env.backend.controls.map((c) => c.$4).toSet(), hasLength(1));
  });

  test('queued ACK plus failed status query remains cancellation pending, never cancelled', () async {
    final env = Environment();
    await env.start();
    env.backend.ackQueued = true;
    env.backend.afterControl = () => env.backend.readError = StateError('lost query');
    await expectLater(env.service.controlAnalysis('project-1', 'cancel', 0), throwsA(isA<ImportAnalysisPending>()));
    expect(env.service.cancelPending('analysis-project-1'), isTrue);
    expect(env.service.snapshot('project-1')!.analysisJob.state, BirdJobState.queued);
  });
}

ImportStartResult result(String project, {int version = 0, BirdJobState state = BirdJobState.queued, String dispatch = 'waiting', String? session}) => ImportStartResult(
  workflow: ImportWorkflow.fromJson({
    'contract_version': 'import-analysis-v1',
    'owner': 'box',
    'project_id': project,
    'import_job_id': 'import-$project',
    'analysis_job_id': 'analysis-$project',
    'smart_follow_session_id': session,
    'dispatch_state': dispatch,
  }, expectedProject: project),
  importJob: BirdJobStatus(id: 'import-$project', type: BirdJobType.import, state: dispatch == 'waiting' ? BirdJobState.running : BirdJobState.completed, sourceProjectId: project, version: version, totalCount: 10),
  analysisJob: BirdJobStatus(
    id: 'analysis-$project',
    type: BirdJobType.analysis,
    state: state,
    sourceProjectId: project,
    version: version,
    smartFollowSessionId: session,
    workflowStage: state == BirdJobState.queued
        ? 'waiting_import'
        : state == BirdJobState.completed
        ? 'completed'
        : 'analyzing',
    progress: state == BirdJobState.completed ? 1 : 0,
    availableActions: state == BirdJobState.queued || state == BirdJobState.running ? const ['cancel'] : const [],
  ),
);

Map<String, dynamic> clone(Map raw) => Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map);

class Environment {
  final store = Store();
  final projects = Projects();
  final backend = Backend();
  String device = 'box-a', context = 'box-a|endpoint';
  Map<String, dynamic> caps = capability();
  late ImportAnalysisService service = makeService();
  ImportAnalysisService makeService() => ImportAnalysisService(repository: backend, batches: projects, cache: store, readCapabilities: () async => caps, deviceId: () => device, contextKey: () => context);
  void restartPhone() => service = makeService();
  Future<ImportStartResult> start() => service.start(name: 'One start', cardId: 'card-1', analysis: const AutoAnalysisRequest());
  List<Map> get records => ((store.values['import-analysis-intents:v1:$device'] as Map?)?['records'] as Map? ?? {}).values.cast<Map>().toList();
}

class Store extends Fake implements LocalCache {
  final values = <String, Object?>{};
  bool failWrites = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    if (failWrites) throw StateError('disk unavailable');
    values[key] = jsonDecode(jsonEncode(value));
  }
}

class Projects extends Fake implements BatchRepository {
  final calls = <ProjectCreateRequest>[];
  final created = <String, BatchSummary>{};
  Object? beforeError, afterError;
  void Function()? beforeCreate;
  Completer<void>? gate;
  @override
  Future<BatchSummary> create(ProjectCreateRequest request) async {
    calls.add(request);
    beforeCreate?.call();
    if (gate != null) await gate!.future;
    final failure = beforeError;
    beforeError = null;
    if (failure != null) throw failure;
    final project = created.putIfAbsent(
      request.idempotencyKey!,
      () => BatchSummary(id: 'project-${created.length + 1}', name: request.name, createdAt: DateTime.utc(2026), totalFiles: 0, analyzedCount: 0, reviewCount: 0, keepCount: 0, discardCount: 0, pendingCopyCount: 0, copyState: 'idle'),
    );
    final lost = afterError;
    afterError = null;
    if (lost != null) throw lost;
    return project;
  }
}

class Backend extends Fake implements ImportWorkflowRepository {
  final current = <String, ImportStartResult>{}, receipts = <String, ImportStartResult>{};
  final submissions = <(String, Map<String, dynamic>, String)>[], controls = <(String, String, int, String)>[], reads = <String>[];
  Object? beforeStartError, afterStartError, beforeControlError, afterControlError, readError;
  bool advanceOnStart = false, omitSession = false, ackQueued = false;
  void Function()? beforeStart, afterControl;
  Completer<void>? startGate, responseGate;
  @override
  Future<ImportStartResult> startImportWorkflow(String projectId, Map<String, dynamic> request, String key) async {
    submissions.add((projectId, clone(request), key));
    beforeStart?.call();
    if (startGate != null) await startGate!.future;
    final failed = beforeStartError;
    beforeStartError = null;
    if (failed != null) throw failed;
    final session = (request['auto_analysis'] as Map)['smart_follow'] == null || omitSession ? null : 'session-$projectId';
    final receipt = receipts.putIfAbsent(key, () => result(projectId, session: session));
    current.putIfAbsent(projectId, () => advanceOnStart ? result(projectId, version: 2, state: BirdJobState.running, dispatch: 'dispatched', session: session) : receipt);
    if (responseGate != null) await responseGate!.future;
    final lost = afterStartError;
    afterStartError = null;
    if (lost != null) throw lost;
    return receipt;
  }

  @override
  Future<ImportStartResult> importWorkflow(String projectId) async {
    reads.add(projectId);
    if (readError != null) throw readError!;
    return current[projectId] ?? (throw const ApiException(message: 'no workflow', code: 'import_analysis_not_found', statusCode: 404));
  }

  @override
  Future<BirdJobStatus> controlWorkflowJob(String jobId, String action, int version, String key) async {
    controls.add((jobId, action, version, key));
    final failed = beforeControlError;
    beforeControlError = null;
    if (failed != null) throw failed;
    final project = current.entries.singleWhere((entry) => entry.value.analysisJob.id == jobId).key;
    final updated = result(project, version: version + 1, state: ackQueued ? BirdJobState.queued : BirdJobState.cancelled, session: current[project]!.workflow.sessionId);
    current[project] = updated;
    afterControl?.call();
    final lost = afterControlError;
    afterControlError = null;
    if (lost != null) throw lost;
    return updated.analysisJob;
  }
}
