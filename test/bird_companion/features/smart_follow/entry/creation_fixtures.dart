import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';

import 'configuration_fixtures.dart';

class CreationCache implements LocalCache {
  final values = <String, Object?>{};
  bool failWrites = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    if (failWrites) throw StateError('disk full');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CreationEnvironment {
  CreationEnvironment({bool atomic = false}) {
    configuration.notStarted = atomic;
    configuration.devices[1] = configDevice('media_usb_fake', displayName: '旅行备份盘');
    jobs = CreationJobs(backend);
    if (!atomic) jobs.rows.add(job());
    follows = SmartFollowRepository(backend);
    service = newService();
  }
  final configuration = ConfigurationFixture();
  final backend = FakeSmartFollowBackend(recognitionJobId: 'rec-1', sessionId: 'sf-1');
  final cache = CreationCache();
  late final CreationJobs jobs;
  late final SmartFollowRepository follows;
  late final SmartFollowCreationService service;
  String? context = 'box-1|http://box';
  String? device = 'box-1';
  BirdJobStatus job({String id = 'rec-1', String batch = 'batch-1', String? session}) => BirdJobStatus(id: id, type: BirdJobType.analysis, state: BirdJobState.running, sourceProjectId: batch, smartFollowSessionId: session);
  SmartFollowConfigurationReader reader() => configuration.reader();
  SmartFollowCreationService newService() => SmartFollowCreationService(jobs: jobs, follows: follows, cache: cache, deviceId: () => device, contextKey: () => context);
  Future<SmartFollowConfiguredIntent> intent() async {
    final controller = await configuration.controller();
    controller.selectTarget('media_usb_fake');
    controller.selectConflict(ConflictStrategy.skip);
    final success = await controller.confirm();
    if (!success) throw StateError(controller.blockReason ?? 'configuration failed');
    final result = controller.confirmed!;
    controller.dispose();
    return result;
  }
}

class CreationJobs implements JobRepository {
  CreationJobs(this.backend);
  final FakeSmartFollowBackend backend;
  final rows = <BirdJobStatus>[];
  final requests = <AnalysisJobRequest>[];
  bool timeoutBeforeCommit = false, timeoutAfterCommit = false;
  bool pageFails = false, omitSession = false;
  Completer<void>? createGate;
  Object? createError;
  Future<JobPage> Function(String?)? readPage;
  @override
  Future<JobPage> page({String? cursor, int pageSize = 50, String? state, String? type}) async {
    if (pageFails) throw StateError('disconnected');
    return readPage == null ? JobPage(items: rows.toList(), hasMore: false) : readPage!(cursor);
  }

  @override
  Future<BirdJobStatus> detail(String id) async => rows.firstWhere((job) => job.id == id);
  @override
  Future<BirdJobStatus> createAnalysis(String projectId, AnalysisJobRequest request) async {
    requests.add(request);
    await createGate?.future;
    if (createError != null) throw createError!;
    if (timeoutBeforeCommit) throw TimeoutException('response missing');
    backend.start();
    final job = BirdJobStatus(id: 'rec-1', type: BirdJobType.analysis, state: BirdJobState.running, sourceProjectId: projectId, smartFollowSessionId: omitSession ? null : 'sf-1');
    rows.add(job);
    if (timeoutAfterCommit) throw TimeoutException('response missing');
    return job;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
