import 'dart:async';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> sessionJson({
  String sessionId = 'sf_1',
  String jobId = 'rec_1',
  String state = 'following',
  int version = 1,
  int eligible = 0,
  int pending = 0,
  int copiedAssets = 0,
  int copiedFiles = 0,
  int childJobs = 0,
  List<String> actions = const ['pause', 'finish_current_results', 'stop_following'],
  bool metadataAvailable = false,
}) => {
  'session_id': sessionId,
  'recognition_job_id': jobId,
  'state': state,
  'state_version': version,
  'eligible_count': eligible,
  'pending_count': pending,
  'copied_asset_count': copiedAssets,
  'copied_file_count': copiedFiles,
  'child_job_count': childJobs,
  'allowed_actions': actions,
  'metadata_update_available': metadataAvailable,
};

ApiException timeoutError() => ApiException(
  message: 'Connection timed out',
  cause: DioException(requestOptions: RequestOptions(path: '/api/v1/jobs/rec_1/smart-follow-sessions'), type: DioExceptionType.connectionTimeout),
);

class FakeGateway implements SmartFollowGateway {
  SmartFollowSession sessionValue = SmartFollowSession.fromJson(sessionJson());
  Map<String, dynamic>? availableJson;
  String? recoveredSessionId;

  /// 逐次消费：为空时用 [recoveredSessionId]，否则按顺序返回（先 null 再命中，
  /// 用来模拟"第一次查没有、创建超时后再查有了"）。
  final recoverSequence = <String?>[];
  Object? capabilitiesError;
  Object? startError;
  Object? actError;
  SmartFollowSession? actResponse;
  SmartFollowChildJobPage childPage = SmartFollowChildJobPage.empty;
  bool partialPreview = false;

  int startCalls = 0;
  int sessionCalls = 0;
  int actCalls = 0;
  int capabilitiesCalls = 0;
  int childJobCalls = 0;
  int createCalls = 0;
  int recoverCalls = 0;
  String? lastCreateKey;
  Map<String, dynamic>? lastCreateData;
  Map<String, dynamic>? lastStartRequest;
  int? lastExpectedVersion;

  @override
  Future<SmartFollowCapabilities> capabilities() async {
    capabilitiesCalls++;
    final error = capabilitiesError;
    if (error != null) throw error;
    return SmartFollowCapabilities.fromJson({
      'incremental_recognition_results': {'available': true},
      'smart_follow_copy': {'available': true, 'default_batch_size': 8, 'default_collect_window_ms': 2000},
      'smart_follow_metadata_update': {'available': true},
    });
  }

  @override
  Future<SmartFollowSession> startOnRecognitionJob(
    String recognitionJobId,
    SmartFollowStartRequest request, {
    String? idempotencyKey,
  }) async {
    startCalls++;
    lastStartRequest = request.toJson();
    final error = startError;
    if (error != null) throw error;
    return sessionValue;
  }

  @override
  Future<SmartFollowSession> session(String sessionId) async {
    sessionCalls++;
    return sessionValue;
  }

  @override
  Future<SmartFollowChildJobPage> childJobs(String sessionId, {String? cursor, int pageSize = 50}) async {
    childJobCalls++;
    return childPage;
  }

  @override
  Future<SmartFollowSession?> act(
    String sessionId,
    SmartFollowAction action, {
    required int expectedStateVersion,
    String? idempotencyKey,
  }) async {
    actCalls++;
    lastExpectedVersion = expectedStateVersion;
    final error = actError;
    if (error != null) throw error;
    return actResponse;
  }

  @override
  Future<String?> sessionIdForRecognitionJob(String recognitionJobId) async {
    recoverCalls++;
    if (recoverSequence.isNotEmpty) return recoverSequence.removeAt(0);
    return recoveredSessionId;
  }

  @override
  Future<SmartFollowMetadataAvailability> metadataAvailability(String sessionId) async =>
      SmartFollowMetadataAvailability.fromJson(availableJson ?? const {'available': false});

  @override
  Future<SmartFollowMetadataPreview> previewMetadata(String sessionId, {Map<String, dynamic>? data, String? idempotencyKey}) async =>
      SmartFollowMetadataPreview.fromJson({
        'preview_id': 'pv_1',
        'preview_token': 'tok_1',
        'updatable_asset_count': 4,
        'requires_partial_confirmation': partialPreview,
      });

  @override
  Future<SmartFollowMetadataPreview> previewDetail(String previewId) async => throw UnimplementedError();

  @override
  Future<SmartFollowMetadataUpdate> createMetadataUpdate(String sessionId, {required Map<String, dynamic> data, String? idempotencyKey}) async {
    createCalls++;
    lastCreateKey = idempotencyKey;
    lastCreateData = data;
    return SmartFollowMetadataUpdate.fromJson({'update_id': 'u1', 'state': 'queued'});
  }

  @override
  Future<SmartFollowMetadataUpdate> metadataUpdate(String updateId) async => SmartFollowMetadataUpdate.fromJson({'update_id': updateId, 'state': 'running'});
}

const startRequest = SmartFollowStartRequest(targetMediaId: 'media_usb_1', reviewExportEnabled: true);

void main() {
  late FakeGateway gateway;
  late SmartFollowRepository repository;

  setUp(() {
    gateway = FakeGateway();
    repository = SmartFollowRepository(gateway);
  });

  tearDown(() => repository.dispose());

  group('开启跟随', () {
    test('同一 job 已有活动会话时不再 POST', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 5, eligible: 3));
      await repository.refresh('sf_1');
      final started = await repository.startOnRecognitionJob('rec_1', startRequest);
      expect(started.sessionId, 'sf_1');
      expect(gateway.startCalls, 0);
      expect(repository.sessionIdForJob('rec_1'), 'sf_1');
    });

    test('会话已结束后再开一轮，映射到新会话而不是旧会话', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(state: 'completed', version: 9));
      await repository.refresh('sf_1');
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(sessionId: 'sf_2', version: 1));
      final started = await repository.startOnRecognitionJob('rec_1', startRequest);
      expect(gateway.startCalls, 1);
      expect(started.sessionId, 'sf_2');
      expect(started.state, SmartFollowState.following);
      expect(repository.sessionIdForJob('rec_1'), 'sf_2');
    });

    test('创建前先用识别事件查回已有会话（不重复创建）', () async {
      gateway.recoveredSessionId = 'sf_9';
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(sessionId: 'sf_9', version: 7));
      final started = await repository.startOnRecognitionJob('rec_1', startRequest);
      expect(started.sessionId, 'sf_9');
      expect(gateway.startCalls, 0);
      expect(gateway.recoverCalls, 1);
    });

    test('创建超时且查不回会话时抛结果未知，且不换键重建', () async {
      gateway.startError = timeoutError();
      await expectLater(
        repository.startOnRecognitionJob('rec_1', startRequest),
        throwsA(isA<SmartFollowOutcomeUnknown>()),
      );
      expect(gateway.startCalls, 1);
      expect(repository.snapshotForJob('rec_1'), isNull);
    });

    test('创建超时但盒子其实已建好：查回会话并返回', () async {
      gateway.startError = timeoutError();
      // 第一次（POST 前的查重）没有，POST 超时后再查就有了。
      gateway.recoverSequence.addAll([null, 'sf_1']);
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 2, eligible: 1));
      final started = await repository.startOnRecognitionJob('rec_1', startRequest);
      expect(started.stateVersion, 2);
      expect(gateway.startCalls, 1);
      expect(repository.snapshotForJob('rec_1'), isNotNull);
    });

    test('SMART_FOLLOW_ALREADY_ACTIVE 时接管已有会话而不是报错', () async {
      gateway.startError = const ApiException(message: 'already active', code: 'SMART_FOLLOW_ALREADY_ACTIVE', statusCode: 409);
      gateway.recoveredSessionId = 'sf_1';
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 4));
      final started = await repository.startOnRecognitionJob('rec_1', startRequest);
      expect(started.sessionId, 'sf_1');
    });
  });

  group('快照合并', () {
    test('更旧的 state_version 不能把新数字退回去', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 8, eligible: 12, copiedAssets: 10));
      await repository.refresh('sf_1');
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 7, eligible: 9, copiedAssets: 7));
      await repository.refresh('sf_1');
      final snapshot = repository.snapshot('sf_1')!;
      expect(snapshot.stateVersion, 8);
      expect(snapshot.eligibleCount, 12);
      expect(snapshot.copiedAssetCount, 10);
    });

    test('更新的快照替换并通知监听者', () async {
      var notified = 0;
      repository.addListener(() => notified++);
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 3, pending: 2));
      await repository.refresh('sf_1');
      expect(repository.snapshot('sf_1')!.pendingCount, 2);
      expect(notified, 1);
    });
  });

  group('会话动作', () {
    test('后端没给的动作本地直接拒绝，不发请求', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 3, actions: ['pause']));
      await repository.refresh('sf_1');
      await expectLater(
        repository.act('sf_1', SmartFollowAction.stopFollowing),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_ACTION_NOT_ALLOWED')),
      );
      expect(gateway.actCalls, 0);
    });

    test('带当前 state_version 发动作；响应无会话时重读', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 6));
      await repository.refresh('sf_1');
      final sessionsBefore = gateway.sessionCalls;
      await repository.act('sf_1', SmartFollowAction.pause);
      expect(gateway.actCalls, 1);
      expect(gateway.lastExpectedVersion, 6);
      expect(gateway.sessionCalls, sessionsBefore + 1);
    });

    test('版本冲突后先刷新再抛出，保留原始原因', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 6));
      await repository.refresh('sf_1');
      final sessionsBefore = gateway.sessionCalls;
      gateway.actError = const ApiException(message: 'conflict', code: 'SMART_FOLLOW_STATE_VERSION_CONFLICT', statusCode: 409);
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 7));
      await expectLater(
        repository.act('sf_1', SmartFollowAction.finishCurrentResults),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_STATE_VERSION_CONFLICT')),
      );
      expect(gateway.sessionCalls, sessionsBefore + 1);
      expect(repository.snapshot('sf_1')!.stateVersion, 7);
    });
  });

  group('事件与能力', () {
    test('已知事件唤醒重读，未知事件忽略', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 2, eligible: 5));
      await repository.handleEvent('SmartFollowStateChanged', {'session_id': 'sf_1'});
      expect(repository.snapshot('sf_1')!.eligibleCount, 5);
      final calls = gateway.sessionCalls;
      await repository.handleEvent('SomeOtherEvent', {'session_id': 'sf_1'});
      await repository.handleEvent('SmartFollowCountsChanged', const {});
      expect(gateway.sessionCalls, calls);
    });

    test('事件里只有 job id 时先按映射找会话', () async {
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 2));
      await repository.refresh('sf_1');
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 3, pending: 1));
      await repository.handleEvent('RecognitionResultCommitted', {'recognition_job_id': 'rec_1'});
      expect(repository.snapshot('sf_1')!.stateVersion, 3);
    });

    test('旧盒子 404 视为无能力且只查一次', () async {
      gateway.capabilitiesError = const ApiException(message: 'not found', statusCode: 404);
      final first = await repository.capabilities();
      final second = await repository.capabilities();
      expect(first.canShowEntry, isFalse);
      expect(second.canShowEntry, isFalse);
      expect(gateway.capabilitiesCalls, 1);
    });

    test('换盒子后清空快照与能力缓存，并通知页面重建', () async {
      var notified = 0;
      repository.addListener(() => notified++);
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 2));
      await repository.refresh('sf_1');
      await repository.capabilities();
      expect(repository.snapshot('sf_1'), isNotNull);
      expect(gateway.capabilitiesCalls, 1);

      repository.resetForDeviceChange();
      expect(repository.snapshot('sf_1'), isNull);
      expect(repository.sessionIdForJob('rec_1'), isNull);
      expect(notified, 2); // refresh 一次 + reset 一次

      await repository.capabilities();
      expect(gateway.capabilitiesCalls, 2);
    });
  });

  group('信息统一更新', () {
    Future<SmartFollowMetadataPreview> preview() => repository.previewMetadata('sf_1');

    test('部分可更新时必须显式确认', () async {
      gateway.partialPreview = true;
      final previewValue = await preview();
      await expectLater(
        repository.createMetadataUpdate('sf_1', previewValue),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED')),
      );
      expect(gateway.createCalls, 0);
      await repository.createMetadataUpdate('sf_1', previewValue, confirmPartial: true);
      expect(gateway.createCalls, 1);
      expect(gateway.lastCreateData?['confirm_partial'], true);
      expect(gateway.lastCreateData?['preview_token'], 'tok_1');
      // 键由会话 + preview_token 派生，连点两次也只建一个任务。
      expect(gateway.lastCreateKey, 'md-create-sf_1-tok_1');
    });

    test('没有可更新项时不允许创建', () async {
      final empty = SmartFollowMetadataPreview.fromJson({'preview_token': 'tok_2'});
      await expectLater(
        repository.createMetadataUpdate('sf_1', empty),
        throwsA(isA<ApiException>().having((error) => error.code, 'code', 'SMART_FOLLOW_METADATA_NOT_AVAILABLE')),
      );
    });
  });

  group('事件流绑定', () {
    test('WS 通知只唤醒重读：数字来自会话接口，不来自 payload', () async {
      final controller = StreamController<DeviceEvent>.broadcast();
      addTearDown(controller.close);
      repository.bindEvents(controller.stream);
      gateway.sessionValue = SmartFollowSession.fromJson(sessionJson(version: 4, eligible: 9, pending: 1));

      controller.add(
        DeviceEvent(
          type: 'SmartFollowCountsChanged',
          // 故意给一个错的数字：App 必须无视它。
          payload: const {'session_id': 'sf_1', 'eligible_count': 999},
          timestamp: DateTime.now(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.snapshot('sf_1')!.eligibleCount, 9);
      expect(gateway.sessionCalls, 1);
    });

    test('销毁后不再订阅', () async {
      final controller = StreamController<DeviceEvent>.broadcast();
      addTearDown(controller.close);
      repository.bindEvents(controller.stream);
      repository.dispose();
      controller.add(DeviceEvent(type: 'SmartFollowStateChanged', payload: const {'session_id': 'sf_1'}, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);
      expect(gateway.sessionCalls, 0);
    });
  });
}
