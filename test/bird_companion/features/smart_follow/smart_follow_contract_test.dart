import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 联合开发任务书 §6.5 的示例响应，逐字段照抄（含 null 与三动作顺序）。
Map<String, dynamic> jointSessionExample() => {
  'session_id': 'sf_1',
  'recognition_job_id': 'rec_1',
  'state': 'following',
  'state_version': 12,
  'eligibility_mode': 'recognized_only_v1',
  'target_media_id': 'media_usb_1',
  'batch_size': 8,
  'collect_window_ms': 2000,
  'last_consumed_event_seq': 123,
  'cutoff_event_seq': null,
  'recognized_count': 16,
  'eligible_count': 16,
  'pending_count': 2,
  'assigned_count': 14,
  'copied_asset_count': 12,
  'copied_file_count': 12,
  'failed_asset_count': 0,
  'child_job_count': 2,
  'metadata_update_available': false,
  'active_metadata_update_id': null,
  'allowed_actions': ['pause', 'finish_current_results', 'stop_following'],
  'error_code': null,
  'error_message': null,
  'created_at': '2026-10-27T10:00:00Z',
  'updated_at': '2026-10-27T10:03:00Z',
  'finished_at': null,
};

class RecordingApi extends ApiClient {
  RecordingApi(this.handler);

  final Map<String, dynamic> Function(String method, String path, {Map<String, dynamic>? query, Object? data, String? idempotencyKey}) handler;
  final calls = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    calls.add({'method': 'GET', 'path': path, 'query': queryParameters});
    return handler('GET', path, query: queryParameters);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
    Map<String, String>? headers,
  }) async {
    calls.add({'method': 'POST', 'path': path, 'data': data, 'key': idempotencyKey});
    return handler('POST', path, data: data, idempotencyKey: idempotencyKey);
  }
}

void main() {
  group('SmartFollowSession', () {
    test('联合任务书 §6.5 示例逐字段解析', () {
      final session = SmartFollowSession.fromJson(jointSessionExample());
      expect(session.sessionId, 'sf_1');
      expect(session.recognitionJobId, 'rec_1');
      expect(session.state, SmartFollowState.following);
      expect(session.stateVersion, 12);
      expect(session.eligibilityMode, 'recognized_only_v1');
      expect(session.targetMediaId, 'media_usb_1');
      expect(session.batchSize, 8);
      expect(session.collectWindowMs, 2000);
      expect(session.lastConsumedEventSeq, 123);
      expect(session.cutoffEventSeq, isNull);
      expect(session.recognizedCount, 16);
      expect(session.pendingCount, 2);
      expect(session.assignedCount, 14);
      expect(session.copiedAssetCount, 12);
      // 照片数与文件数必须分开，App 不得互相推导（联合 §6.5 末段）。
      expect(session.copiedFileCount, 12);
      expect(session.childJobCount, 2);
      expect(session.metadataUpdateAvailable, isFalse);
      expect(session.allowedActions, [SmartFollowAction.pause, SmartFollowAction.finishCurrentResults, SmartFollowAction.stopFollowing]);
      expect(session.isFinished, isFalse);
      expect(session.supports(SmartFollowAction.stopFollowing), isTrue);
      expect(session.supports(SmartFollowAction.retry), isFalse);
    });

    test('状态九值 + 未知值原样保留且不当作终端', () {
      const wires = {
        'created': 'created',
        'following': 'following',
        'paused': 'paused',
        'waiting_for_target': 'waiting_for_target',
        'waiting_for_source': 'waiting_for_source',
        'draining': 'draining',
        'completed': 'completed',
        'completed_partial': 'completed_partial',
        'failed': 'failed',
      };
      for (final entry in wires.entries) {
        expect(SmartFollowState.fromWire(entry.key).wire, entry.value);
        expect(SmartFollowState.fromWire(entry.key).isUnknown, isFalse);
      }
      final legacy = SmartFollowState.fromWire('recognition_interrupted');
      expect(legacy.isUnknown, isTrue);
      expect(legacy.wire, 'recognition_interrupted');
      expect(legacy.isFinished, isFalse);
      expect(SmartFollowState.fromWire(null), SmartFollowState.unknown);
      expect(SmartFollowState.fromWire('  '), SmartFollowState.unknown);
    });

    test('终端状态只允许 completed / completed_partial / failed', () {
      final terminals = SmartFollowState.values.where((state) => state.isFinished).map((state) => state.wire).toList();
      expect(terminals..sort(), ['completed', 'completed_partial', 'failed']);
    });

    test('新快照才可覆盖旧快照', () {
      final older = SmartFollowSession.fromJson({...jointSessionExample(), 'state_version': 11});
      final newer = SmartFollowSession.fromJson({...jointSessionExample(), 'state_version': 12});
      expect(newer.isNewerThan(older), isTrue);
      expect(older.isNewerThan(newer), isFalse);
      expect(newer.isNewerThan(newer), isTrue);
    });

    test('旧后端字段名（mode/policy_version、default_batch_size）等价解析', () {
      final legacy = SmartFollowSession.fromJson({
        ...jointSessionExample(),
        'eligibility_mode': null,
        'mode': 'recognized_only_v1',
        'policy_version': 'recognized_only_v1',
        'batch_size': null,
        'default_batch_size': 8,
        'collect_window_ms': null,
        'default_collect_window_ms': 2000,
      });
      expect(legacy.eligibilityMode, 'recognized_only_v1');
      expect(legacy.batchSize, 8);
      expect(legacy.collectWindowMs, 2000);
    });

    test('未知动作丢弃，旧的 resume_recognition 不进枚举', () {
      final session = SmartFollowSession.fromJson({
        ...jointSessionExample(),
        'allowed_actions': ['pause', 'resume_recognition', 'teleport', 'resume'],
      });
      expect(session.allowedActions, [SmartFollowAction.pause, SmartFollowAction.resume]);
      expect(session.action(SmartFollowAction.stopFollowing), isNull);
    });

    test('缺 session_id / recognition_job_id 时明确报协议不兼容', () {
      expect(() => SmartFollowSession.fromJson({'session_id': 'sf_1'}), throwsA(isA<Exception>()));
      expect(() => SmartFollowSession.fromJson({'recognition_job_id': 'rec_1'}), throwsA(isA<Exception>()));
    });
  });

  group('SmartFollowCapabilities', () {
    test('联合 §6.1 写法', () {
      final caps = SmartFollowCapabilities.fromJson({
        'incremental_recognition_results': {'available': true, 'schema_version': 'birdbox.pipeline_result.v1'},
        'smart_follow_copy': {
          'available': true,
          'contract_version': 'smart-follow-v1',
          'eligibility_mode': 'recognized_only_v1',
          'default_batch_size': 8,
          'default_collect_window_ms': 2000,
          'batch_size_range': [1, 32],
          'collect_window_ms_range': [250, 10000],
        },
        'smart_follow_metadata_update': {'available': true, 'contract_version': 'smart-follow-metadata-v1'},
      });
      expect(caps.canShowEntry, isTrue);
      expect(caps.canUpdateMetadata, isTrue);
      expect(caps.copy.contractVersion, 'smart-follow-v1');
      expect(caps.copy.batchSize, 8);
      expect(caps.copy.collectWindowMs, 2000);
      expect(caps.copy.batchSizeRange, [1, 32]);
      expect(caps.copy.collectWindowMsRange, [250, 10000]);
      expect(caps.incrementalSchemaVersion, 'birdbox.pipeline_result.v1');
    });

    test('09-23 后端任务书写法（mode/policy_version/batch_size）等价', () {
      final caps = SmartFollowCapabilities.fromJson({
        'incremental_recognition_results': {'available': true},
        'smart_follow_copy': {'available': true, 'mode': 'recognized_only_v1', 'batch_size': 8, 'collect_window_ms': 2000},
        'smart_follow_metadata_update': {'available': false},
      });
      expect(caps.canShowEntry, isTrue);
      expect(caps.canUpdateMetadata, isFalse);
      expect(caps.copy.eligibilityMode, 'recognized_only_v1');
      expect(caps.copy.batchSize, 8);
    });

    test('旧盒子：404 后的空能力不让任何入口出现', () {
      final caps = SmartFollowCapabilities.fromJson(const {});
      expect(caps.canShowEntry, isFalse);
      expect(caps.canUpdateMetadata, isFalse);
      expect(caps.copy.available, isFalse);
      expect(SmartFollowCapabilities.none.canShowEntry, isFalse);
    });

    test('只有增量结果、没有跟随能力时入口仍然关闭', () {
      final caps = SmartFollowCapabilities.fromJson({
        'incremental_recognition_results': {'available': true},
        'smart_follow_copy': {'available': false},
      });
      expect(caps.canShowEntry, isFalse);
    });
  });

  group('SmartFollowChildJob', () {
    test('cursor 分页与字段别名', () {
      final page = SmartFollowChildJobPage.fromJson({
        'items': [
          {
            'copy_job_id': 'cj_1',
            'index': 1,
            'state': 'completed',
            'asset_count': 8,
            'file_count': 9,
            'total_bytes': 4096,
            'copied_files': 9,
            'skipped_files': 0,
            'failed_files': 0,
            'created_at': '2026-10-27T10:00:00Z',
            'finished_at': '2026-10-27T10:01:00Z',
          },
          {
            'copy_job_id': 'cj_2',
            'state': 'running',
            'planned_files': 4,
            'planned_bytes': 2048,
          },
        ],
        'has_more': true,
        'next_cursor': 'c2',
      });
      expect(page.items, hasLength(2));
      expect(page.items.first.state, CopyJobState.completed);
      expect(page.items.first.fileCount, 9);
      expect(page.items.first.totalBytes, 4096);
      expect(page.items.first.finishedAt, isNotNull);
      expect(page.items.last.state, CopyJobState.running);
      expect(page.items.last.fileCount, 4);
      expect(page.items.last.copiedFileCount, 0);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, 'c2');
    });

    test('未知 state 走 RC3 自定义状态，不崩', () {
      final job = SmartFollowChildJob.fromJson({'copy_job_id': 'cj_9', 'state': 'reconciling'});
      expect(job.state.isCustom, isTrue);
      expect(job.state.wire, 'reconciling');
    });

    test('has_more 但无 cursor 时不再翻页', () {
      final page = SmartFollowChildJobPage.fromJson({
        'items': <Object>[],
        'has_more': true,
      });
      expect(page.hasMore, isFalse);
      expect(page.items, isEmpty);
    });
  });

  group('SmartFollowMetadataPreview', () {
    test('预览强类型字段 + 写入方式文案', () {
      final preview = SmartFollowMetadataPreview.fromJson({
        'preview_id': 'pv_1',
        'preview_token': 'tok_1',
        'expires_at': '2099-01-01T00:00:00Z',
        'target_media_id': 'media_usb_1',
        'child_job_count': 2,
        'updatable_asset_count': 12,
        'updatable_file_count': 13,
        'unchanged_count': 2,
        'blocked_count': 1,
        'conflict_count': 1,
        'estimated_bytes': 1024,
        'write_mode': 'safe_embed_first',
        'requires_partial_confirmation': true,
        'blocked_reasons': ['目标文件已被外部修改'],
      });
      expect(preview.previewToken, 'tok_1');
      expect(preview.childJobCount, 2);
      expect(preview.updatableAssetCount, 12);
      expect(preview.updatableFileCount, 13);
      expect(preview.requiresPartialConfirmation, isTrue);
      expect(preview.blockedReasons, ['目标文件已被外部修改']);
      expect(preview.writeModeLabel, contains('内嵌'));
      expect(preview.isExpired, isFalse);
      expect(preview.hasUpdatableItems, isTrue);
    });

    test('availability 与父任务终端判定', () {
      final availability = SmartFollowMetadataAvailability.fromJson({'available': true, 'updatable_asset_count': 3, 'reason': '识别结束后产生了新信息'});
      expect(availability.available, isTrue);
      expect(availability.updatableAssetCount, 3);
      final running = SmartFollowMetadataUpdate.fromJson({'update_id': 'u1', 'state': 'running'});
      expect(running.isTerminal, isFalse);
      final partial = SmartFollowMetadataUpdate.fromJson({
        'update_id': 'u1',
        'state': 'completed_partial',
        'child_jobs': [
          {'metadata_update_id': 'm1', 'copy_job_id': 'cj_1', 'state': 'completed', 'updated_files': 8},
          {'metadata_update_id': 'm2', 'copy_job_id': 'cj_2', 'state': 'failed', 'error_code': 'COPY_METADATA_WRITE_FAILED'},
        ],
      });
      expect(partial.isTerminal, isTrue);
      expect(partial.isPartial, isTrue);
      expect(partial.childUpdates, hasLength(2));
      expect(partial.childUpdates.last.isTerminal, isTrue);
    });
  });

  group('SmartFollowApi', () {
    test('创建请求体符合联合 §6.2', () {
      const request = SmartFollowStartRequest(targetMediaId: 'media_usb_1', reviewExportEnabled: true);
      expect(request.toJson(), {
        'target_media_id': 'media_usb_1',
        'eligibility_mode': 'recognized_only_v1',
        'pair_policy': 'raw_only',
        'conflict_strategy': 'skip',
        'review_export': {'enabled': true, 'prefer_embedded': true},
      });
    });

    test('开启跟随：路径/幂等键/响应包法', () async {
      final api = RecordingApi((method, path, {query, data, idempotencyKey}) => {'session': jointSessionExample()});
      final sessions = SmartFollowApi(api);
      final session = await sessions.startOnRecognitionJob(
        'rec_1',
        const SmartFollowStartRequest(targetMediaId: 'media_usb_1', reviewExportEnabled: false),
        idempotencyKey: 'follow-start-rec_1',
      );
      expect(session.sessionId, 'sf_1');
      final call = api.calls.single;
      expect(call['method'], 'POST');
      expect(call['path'], '/api/v1/jobs/rec_1/smart-follow-sessions');
      expect(call['key'], 'follow-start-rec_1');
      expect((call['data']! as Map)['target_media_id'], 'media_usb_1');
    });

    test('子任务分页参数', () async {
      final api = RecordingApi((method, path, {query, data, idempotencyKey}) => {'items': <Object>[], 'has_more': false});
      await SmartFollowApi(api).childJobs('sf_1', cursor: ' c0 ');
      final call = api.calls.single;
      expect(call['path'], '/api/v1/smart-follow-sessions/sf_1/copy-jobs');
      expect(call['query'], {'cursor': 'c0', 'page_size': 50});
    });

    test('动作：body 带 expected_state_version，响应无会话时返回 null', () async {
      final api = RecordingApi((method, path, {query, data, idempotencyKey}) => {'ok': true});
      final result = await SmartFollowApi(api).act(
        'sf_1',
        SmartFollowAction.finishCurrentResults,
        expectedStateVersion: 12,
        idempotencyKey: 'sf_1-finish_current_results-12',
      );
      expect(result, isNull);
      final call = api.calls.single;
      expect(call['path'], '/api/v1/smart-follow-sessions/sf_1/actions');
      expect(call['data'], {'action': 'finish_current_results', 'expected_state_version': 12});
      expect(call['key'], 'sf_1-finish_current_results-12');
    });

    test('动作：返回会话时直接解析', () async {
      final api = RecordingApi((method, path, {query, data, idempotencyKey}) => {'smart_follow_session': {...jointSessionExample(), 'state_version': 13}});
      final result = await SmartFollowApi(api).act(
        'sf_1',
        SmartFollowAction.pause,
        expectedStateVersion: 12,
        idempotencyKey: 'k',
      );
      expect(result?.stateVersion, 13);
    });

    test('信息更新三个接口的路径', () async {
      final api = RecordingApi((method, path, {query, data, idempotencyKey}) {
        if (path.endsWith('metadata-update-availability')) return {'available': true};
        if (path.endsWith('metadata-updates/preview')) {
          return {'preview_id': 'pv_1', 'preview_token': 'tok_1', 'expires_at': '2099-01-01T00:00:00Z', 'updatable_asset_count': 1};
        }
        return {'update_id': 'u1', 'state': 'queued'};
      });
      final sessions = SmartFollowApi(api);
      expect((await sessions.metadataAvailability('sf_1')).available, isTrue);
      final preview = await sessions.previewMetadata('sf_1', idempotencyKey: 'kp');
      expect(preview.previewToken, 'tok_1');
      final update = await sessions.createMetadataUpdate('sf_1', data: {'preview_token': 'tok_1'}, idempotencyKey: 'ku');
      expect(update.updateId, 'u1');
      expect(api.calls.map((call) => call['path']), [
        '/api/v1/smart-follow-sessions/sf_1/metadata-update-availability',
        '/api/v1/smart-follow-sessions/sf_1/metadata-updates/preview',
        '/api/v1/smart-follow-sessions/sf_1/metadata-updates',
      ]);
      expect(ApiEndpoints.smartFollowMetadataPreviewDetail, '/api/v1/smart-follow-metadata-previews/{previewId}');
      expect(ApiEndpoints.smartFollowMetadataUpdateDetail, '/api/v1/smart-follow-metadata-updates/{updateId}');
    });
  });
}
