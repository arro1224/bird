import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';

/// 用真实 HTTP 走一遍 mock 盒子的 SmartFollow：验证 App 侧契约与 mock 实现一致，
/// 也给乙的 E1–E4 提供"没有真板也能联调"的样例。
void main() {
  late MockBoxServer server;
  late ApiClient client;
  late SmartFollowApi api;

  setUp(() async {
    server = MockBoxServer(photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false);
    final baseUri = await server.start();
    client = ApiClient()..configure(baseUri);
    api = SmartFollowApi(client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  Future<String> createAnalysisJob() async {
    final job = await JobApi(client).createAnalysis('mock-batch-current', const AnalysisJobRequest(includeGrouping: false));
    return job.id;
  }

  Future<void> control(Map<String, dynamic> body) async {
    await client.post('/mock/control/smart-follow', data: body);
  }

  test('能力：跟随可用、信息更新不可用（旧后端可能本期不做）', () async {
    final capabilities = await api.capabilities();
    expect(capabilities.canShowEntry, isTrue);
    expect(capabilities.canUpdateMetadata, isFalse);
    expect(capabilities.copy.batchSize, 8);
    expect(capabilities.copy.batchSizeRange, [1, 32]);
    expect(capabilities.incrementalSchemaVersion, 'birdbox.pipeline_result.v1');
  });

  test('识别中开启跟随 → 逐张跟随 → 排空 → 完成（全程真实 HTTP）', () async {
    final jobId = await createAnalysisJob();
    final repository = SmartFollowRepository(api);
    addTearDown(repository.dispose);

    final session = await repository.startOnRecognitionJob(
      jobId,
      const SmartFollowStartRequest(targetMediaId: 'mock-media-usb-1', reviewExportEnabled: true),
    );
    expect(session.state, SmartFollowState.following);
    expect(session.targetMediaId, 'mock-media-usb-1');

    await control({'action': 'commit', 'count': 3});
    await repository.refresh(session.sessionId);
    var snapshot = repository.snapshot(session.sessionId)!;
    expect(snapshot.eligibleCount, 3);
    expect(snapshot.pendingCount, 3);
    expect(snapshot.childJobCount, 0);

    await control({'action': 'finish_recognition'});
    await repository.refresh(session.sessionId);
    snapshot = repository.snapshot(session.sessionId)!;
    expect(snapshot.state, SmartFollowState.draining);
    expect(snapshot.childJobCount, 1);
    expect(snapshot.pendingCount, 0);

    await control({'action': 'complete_children'});
    await repository.refresh(session.sessionId);
    snapshot = repository.snapshot(session.sessionId)!;
    expect(snapshot.state, SmartFollowState.completed);
    expect(snapshot.copiedAssetCount, 3);
    expect(snapshot.metadataUpdateAvailable, isFalse);
  });

  test('满 8 张封一批、动作按 allowed_actions 收口、旧版本被 409 拒绝', () async {
    final jobId = await createAnalysisJob();
    final repository = SmartFollowRepository(api);
    addTearDown(repository.dispose);
    final session = await repository.startOnRecognitionJob(
      jobId,
      const SmartFollowStartRequest(targetMediaId: 'mock-media-usb-1', reviewExportEnabled: false),
    );

    await control({'action': 'commit', 'count': 8});
    await repository.refresh(session.sessionId);
    final withBatch = repository.snapshot(session.sessionId)!;
    expect(withBatch.childJobCount, 1);
    expect(withBatch.pendingCount, 0);

    final page = await repository.childJobs(session.sessionId);
    expect(page.items, hasLength(1));
    expect(page.items.single.assetCount, 8);
    expect(page.items.single.state.wire, 'running');

    // 暂停：allowed_actions 换成 resume。
    final paused = await repository.act(session.sessionId, SmartFollowAction.pause);
    expect(paused.state, SmartFollowState.paused);
    expect(paused.supports(SmartFollowAction.resume), isTrue);

    // 用过期版本号发动作必须被拒（后端 state_version 校验）。
    await expectLater(
      api.act(session.sessionId, SmartFollowAction.resume, expectedStateVersion: 0, idempotencyKey: 'stale-version-key'),
      throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_STATE_VERSION_CONFLICT')),
    );

    // 当前状态不允许的动作也要被拒（paused 的 allowed_actions 里没有 retry）。
    await expectLater(
      api.act(session.sessionId, SmartFollowAction.retry, expectedStateVersion: paused.stateVersion, idempotencyKey: 'not-allowed-key'),
      throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_ACTION_NOT_ALLOWED')),
    );
  });

  test('识别任务与跟随会话原子创建：分析任务响应里直接带会话', () async {
    final raw = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: const {'mode': 'standard', 'include_grouping': false, 'smart_follow': {'target_media_id': 'mock-media-usb-1', 'eligibility_mode': 'recognized_only_v1'}},
    );
    final sessionId = raw['smart_follow_session_id'];
    expect(sessionId, isNotNull);
    final jobId = raw['job_id'].toString();
    final session = await api.session(sessionId.toString());
    expect(session.recognitionJobId, jobId);
    expect(session.state, SmartFollowState.following);

    // 同一识别任务再开一次跟随：App 的创建路径应先查回原会话，而不是再建一个。
    final repository = SmartFollowRepository(api);
    addTearDown(repository.dispose);
    final recovered = await repository.startOnRecognitionJob(
      jobId,
      const SmartFollowStartRequest(targetMediaId: 'mock-media-usb-1', reviewExportEnabled: false),
    );
    expect(recovered.sessionId, sessionId);
  });

  test('等待目标盘：状态与按钮由后端给，App 只读', () async {
    final jobId = await createAnalysisJob();
    final repository = SmartFollowRepository(api);
    addTearDown(repository.dispose);
    final session = await repository.startOnRecognitionJob(
      jobId,
      const SmartFollowStartRequest(targetMediaId: 'mock-media-usb-1', reviewExportEnabled: false),
    );
    await control({'action': 'commit', 'count': 2});
    await control({'action': 'wait_target'});
    await repository.refresh(session.sessionId);
    final waiting = repository.snapshot(session.sessionId)!;
    expect(waiting.state, SmartFollowState.waitingForTarget);
    expect(waiting.eligibleCount, 2);
    expect(waiting.errorCode, 'SMART_FOLLOW_TARGET_UNAVAILABLE');
    expect(waiting.allowedActions, [SmartFollowAction.pause, SmartFollowAction.stopFollowing]);
  });
}
