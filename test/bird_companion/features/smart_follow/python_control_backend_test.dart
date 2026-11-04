import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual Python HTTP: pause, committed backlog, frozen finish and verified RC3 files', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    final client = ApiClient()..configure(Uri.parse(Platform.environment['BIRDBOX_SF_CONTROL_BASE']!));
    addTearDown(client.dispose);
    final pair = await client.post(ApiEndpoints.devicePair, data: {'pairing_code': '123456', 'client_name': 'Dart SmartFollow real HTTP test'}, idempotencyKey: 'dart-sf-pair');
    client.setSession(accessToken: pair['access_token'] as String);
    final fixture = await client.get('/local-control-fixture');
    final api = SmartFollowApi(client);
    final created = await api.startOnRecognitionJob(
      fixture['job_id'] as String,
      SmartFollowStartRequest(targetMediaId: fixture['target_media_id'] as String, reviewExportEnabled: false, pairPolicy: 'both'),
      idempotencyKey: 'dart-sf-start',
    );
    expect(created.recognitionJobId, fixture['job_id']);
    expect(created.eligibilityMode, 'recognized_only_v1');
    final paused = await api.act(created.sessionId, SmartFollowAction.pause, expectedStateVersion: created.stateVersion, idempotencyKey: 'dart-sf-pause');
    expect(paused!.state, SmartFollowState.paused);
    await client.post('/local-control-fixture/commit/0', data: {}, idempotencyKey: 'fixture-input-first');
    final pending = await api.session(created.sessionId);
    expect(pending.pendingCount, 1);
    expect(pending.childJobCount, 0);
    final finishing = await api.act(created.sessionId, SmartFollowAction.finishCurrentResults, expectedStateVersion: pending.stateVersion, idempotencyKey: 'dart-sf-finish');
    expect(finishing!.cutoffEventSeq, 1);
    await client.post('/local-control-fixture/commit/1', data: {}, idempotencyKey: 'fixture-input-second');
    var finalSession = await api.session(created.sessionId);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!finalSession.isFinished && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      finalSession = await api.session(created.sessionId);
    }
    expect(finalSession.state, SmartFollowState.completedPartial);
    expect(finalSession.recognizedCount, 2);
    expect(finalSession.eligibleCount, 1);
    expect(finalSession.copiedAssetCount, 1);
    expect(finalSession.copiedFileCount, 1);
    expect(finalSession.cutoffEventSeq, 1);
    final children = await api.childJobs(created.sessionId);
    expect(children.paginationValid, isTrue);
    expect(children.hasMore, isFalse);
    expect(children.items, hasLength(1));
    expect(children.items.single.fileCount, 1);
    final events = await client.get('/api/v1/smart-follow-sessions/${created.sessionId}/events', queryParameters: {'after_event_seq': 0, 'page_size': 200});
    expect((events['items'] as List).length, greaterThan(3));
    expect(events['has_more'], isFalse);
    final report = await client.get('/local-control-fixture/report');
    expect(report['recognition_state'], 'running');
    expect(report['file_count'], 1);
    expect(report['hashes'], [fixture['expected_first_hash']]);
    // This direct API test does not turn on an unfinished production UI feature.
    expect((await api.capabilities()).canShowEntry, isFalse);
  }, skip: Platform.environment['BIRDBOX_SF_CONTROL_BASE'] == null ? 'Start the isolated Python SmartFollow control fixture first.' : false);
}
