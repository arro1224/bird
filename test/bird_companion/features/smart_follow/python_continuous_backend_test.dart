import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current Python: import, incremental Pipeline, one continuous task, pages and hashes', () async {
    HttpOverrides.global = null;
    final client = ApiClient()..configure(Uri.parse(Platform.environment['BIRDBOX_CONTINUOUS_BASE']!));
    addTearDown(client.dispose);
    final paired = await client.post('/api/v1/device/pair', data: {'pairing_code': '123456', 'client_name': 'current backend regression'}, idempotencyKey: 'continuous-app-pair-${DateTime.now().microsecondsSinceEpoch}');
    client.setSession(accessToken: paired['access_token'] as String);
    final scan = await client.get('/api/v1/storage/cards/current/scan');
    final project = await client.post('/api/v1/projects', data: {'name': '持续复制本地验证', 'card_id': scan['card_id']}, idempotencyKey: 'continuous-app-project');
    final projectId = project['project_id'] as String;
    final imported = await client.post('/api/v1/projects/$projectId/imports', data: {'source': 'card', 'read_only': true, 'generate_thumbnails': true, 'generate_previews': true}, idempotencyKey: 'continuous-app-import');
    Future<Map<String, dynamic>> waitJob(String id) async {
      for (var i = 0; i < 200; i++) {
        final job = await client.get('/api/v1/jobs/$id');
        if (job['job_state'] == 'completed') return job;
        expect(job['job_state'], isNot('failed'), reason: '$job');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('Python job did not finish');
    }
    await waitJob(imported['job_id'] as String);
    final api = SmartFollowApi(client);
    final cap = await api.capabilities();
    expect(cap.canShowEntry, isTrue);
    final analysis = await client.post('/api/v1/projects/$projectId/analysis-jobs', data: {
      'mode': 'all', 'existing_result_policy': 'create_new_version',
      'smart_follow': {'target_media_id': 'target', 'pair_policy': 'jpeg_only', 'conflict_strategy': 'skip'}
    }, idempotencyKey: 'continuous-app-analysis');
    final jobId = analysis['job_id'] as String;
    final sid = analysis['smart_follow_session_id'] as String;
    var sawIncremental = false;
    for (var i = 0; i < 200; i++) {
      final events = await client.get('/api/v1/jobs/$jobId/recognition-results');
      final job = await client.get('/api/v1/jobs/$jobId');
      if ((events['items'] as List).isNotEmpty && job['job_state'] != 'completed') sawIncremental = true;
      final snapshot = await api.session(sid);
      expect(snapshot.isContinuous, isTrue);
      if (snapshot.isFinished) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(sawIncremental, isTrue, reason: 'use a fresh isolated fixture; result must precede Pipeline completion');
    final completed = await api.session(sid);
    expect(completed.isFinished, isTrue);
    expect(completed.copiedFileCount, 2);
    expect(completed.childJobCount, 0);
    final first = await api.fileItems(sid, pageSize: 1);
    expect(first.hasMore, isTrue);
    final second = await api.fileItems(sid, cursor: first.nextCursor, pageSize: 1);
    expect(second.hasMore, isFalse);
    expect(first.items.single.fileId, isNot(second.items.single.fileId));
    final history = await api.groupedHistory();
    expect(history.items.where((item) => item.session?.sessionId == sid), hasLength(1));
    final copy = CopyApi(client);
    expect((await copy.capabilities()).atomicPreferencesOnCreate, isTrue);
    final files = await client.get('/local-fixture/files');
    expect(files['file_count'], 2);
    expect(files['writes'], 2);
    expect(files['all_hashes_match'], isTrue);
    await waitJob(jobId);
  }, skip: Platform.environment['BIRDBOX_CONTINUOUS_BASE'] == null ? 'Requires loopback current-backend fixture.' : false);
}
