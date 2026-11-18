import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  _Fixture(this.profile, {this.stateFile});
  final RepairAcceptanceProfile profile;
  final File? stateFile;
  late MockBoxServer server;
  late ApiClient client;
  late SmartFollowApi api;
  String sid = '', jobId = '';
  static const target = 'media_7f9a76e6c97690b61aedf6fd';

  Future<void> open() async {
    server = MockBoxServer(acceptanceProfile: profile, stateFile: stateFile, logRequests: false);
    client = ApiClient()..configure(await server.start());
    api = SmartFollowApi(client);
  }

  Future<void> close() async {
    await client.dispose();
    await server.close();
  }

  Future<void> start() async {
    final job = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: {
        'mode': 'standard',
        'smart_follow': {'target_media_id': target},
      },
    );
    sid = job['smart_follow_session_id'] as String;
    jobId = job['job_id'] as String;
  }

  Future<Map<String, dynamic>> control(String action, [Map<String, dynamic> data = const {}]) => client.post('/mock/control/acceptance', data: {'action': action, ...data});
  Future<SmartFollowSession> tick({int count = 5, bool writes = true}) async => SmartFollowSession.fromJson(Map<String, dynamic>.from((await control('tick', {'recognition_count': count, 'complete_writes': writes}))['session'] as Map));
  Future<SmartFollowSession> act(SmartFollowAction action) async => (await api.act(sid, action, expectedStateVersion: (await api.session(sid)).stateVersion))!;
  Future<Map> batch() async => (await client.get('/api/v1/projects/current'))['batch'] as Map;

  Future<List<Map<String, dynamic>>> category(Map<String, dynamic> query) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final page = await client.get('/api/v1/projects/mock-batch-current/files', queryParameters: {...query, 'page_size': 7, 'cursor': ?cursor});
      rows.addAll((page['items'] as List).map((item) => Map<String, dynamic>.from(item as Map)));
      cursor = page['has_more'] == true ? page['next_cursor'] as String : null;
    } while (cursor != null);
    return rows;
  }

  Future<SmartFollowSession> finish() async {
    var session = await api.session(sid);
    for (var i = 0; i < 50 && !session.isFinished; i++) {
      session = await tick();
    }
    expect(session.isFinished, true);
    return session;
  }
}

void main() {
  Future<_Fixture> fixture([RepairAcceptanceProfile profile = RepairAcceptanceProfile.repair14, File? state]) async {
    final value = _Fixture(profile, stateFile: state);
    await value.open();
    addTearDown(value.close);
    return value;
  }

  for (final profile in RepairAcceptanceProfile.values) {
    test('${profile.id} agrees with frozen categories, verdicts and real paginated lists', () async {
      final frozen = jsonDecode(File('test/fixtures/repair_acceptance_profiles.json').readAsStringSync()) as Map;
      final expected = (frozen['samples'] as List).cast<Map>().singleWhere((sample) => sample['total'] == profile.total);
      final box = await fixture(profile);
      final high = await box.category({'recognition_state': 'recognized'});
      final review = await box.category({'recognition_state': 'needs_review'});
      final skipped = await box.category({'analysis_state': 'skipped'});
      expect([high.length, review.length, skipped.length], [expected['high_confidence'], expected['needs_review'], expected['filtered']]);
      final all = [...high, ...review, ...skipped];
      expect(all.map((row) => row['file_id']).toSet(), hasLength(profile.total));
      final verdicts = <String, int>{};
      for (final row in all) {
        final verdict = (row['recognition'] as Map)['verdict'] as String;
        verdicts.update(verdict, (count) => count + 1, ifAbsent: () => 1);
      }
      expect(verdicts, expected['verdict_counts']);
      final batch = await box.batch();
      expect(batch['pending_review_count'], review.length);
      expect(batch['recognized_count'], high.length);
      expect(batch['filtered_count'], skipped.length);
      expect(review.any((row) => (row['recognition'] as Map)['verdict'] == 'unknown'), true);
      expect(skipped.every((row) => (row['recognition'] as Map)['low_confidence'] == true), true);
      expect(high.every((row) => row['format'] == 'RAW' && (row['filename'] as String).endsWith('.ARW')), true);
    });
  }

  test('manual keep/discard and independent keep filters never change recognition category totals', () async {
    final box = await fixture();
    for (final patch in [
      {'file_id': 'photo-0001', 'keep_state': 'discard'},
      {'file_id': box.profile.manualSpeciesFileId, 'keep_state': 'keep'},
    ]) {
      final id = patch['file_id'];
      await box.client.post('/api/v1/files/$id/decision', data: {'version': 0, 'keep_state': patch['keep_state']});
    }
    expect((await box.batch())['pending_review_count'], 6);
    expect(await box.category({'recognition_state': 'recognized'}), hasLength(5));
    expect(await box.category({'recognition_state': 'needs_review'}), hasLength(6));
    expect(await box.category({'recognition_state': 'needs_review', 'keep_state': 'keep'}), hasLength(1));
    expect(await box.category({'analysis_state': 'skipped'}), hasLength(3));
  });

  test('AI 42/37 candidates stay immutable through manual species, clear, conflict and restart', () async {
    final directory = await Directory.systemTemp.createTemp('repair-review-state-');
    addTearDown(() => directory.delete(recursive: true));
    final box = await fixture(RepairAcceptanceProfile.repair14, File('${directory.path}/state.json'));
    final id = box.profile.manualSpeciesFileId;
    final initial = await box.client.get('/api/v1/files/$id');
    final ai = jsonDecode(jsonEncode((initial['file'] as Map)['recognition']));
    final candidates = (ai as Map)['species_topn'] as List;
    expect(candidates.map((item) => (item as Map)['confidence']), [.42, .37]);
    expect(ai['low_confidence'], true);
    expect((initial['decision'] as Map)['version'], 0);
    expect((initial['decision'] as Map)['user_species'], null);
    expect((await box.client.get('/api/v1/files/$id/history'))['items'], isEmpty);
    final second = candidates[1] as Map;
    await box.client.post(
      '/api/v1/files/$id/decision',
      data: {
        'version': 0,
        'user_species_id': second['species_id'],
        'user_species': second['name'],
        'keep_state': 'keep',
        'user_score': 4,
        'user_tags': ['观察'],
      },
    );
    await expectLater(box.client.post('/api/v1/files/$id/decision', data: {'version': 0, 'user_species': 'stale'}), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    final saved = await box.client.get('/api/v1/files/$id');
    expect((saved['file'] as Map)['recognition'], ai);
    expect((saved['decision'] as Map)['user_species'], second['name']);
    await box.client.post('/api/v1/files/$id/decision', data: {'version': 1, 'user_species_id': null, 'user_species': null});
    await box.close();
    await box.open();
    final restored = await box.client.get('/api/v1/files/$id');
    expect((restored['file'] as Map)['recognition'], ai);
    final decision = restored['decision'] as Map;
    expect(decision['version'], 2);
    expect(decision['user_species_id'], null);
    expect(decision['user_species'], null);
    expect(decision['keep_state'], 'keep');
    expect(decision['user_score'], 4);
    expect(decision['user_tags'], ['观察']);
  });

  test('processing and failed analysis records are outside completed classification totals', () async {
    final box = await fixture();
    await box.control('set_analysis_state', {'file_id': 'photo-0001', 'analysis_state': 'processing'});
    await box.control('set_analysis_state', {'file_id': box.profile.manualSpeciesFileId, 'analysis_state': 'failed'});
    final counts = [
      (await box.category({'recognition_state': 'recognized'})).length,
      (await box.category({'recognition_state': 'needs_review'})).length,
      (await box.category({'analysis_state': 'skipped'})).length,
    ];
    expect(counts, [4, 5, 3]);
    expect(counts.reduce((a, b) => a + b), lessThan((await box.batch())['total_files'] as int));
  });

  test('pause is acknowledged separately, AI finishes while paused, and resume copies each eligible file once', () async {
    final box = await fixture();
    await box.start();
    final requested = await box.act(SmartFollowAction.pause);
    expect(requested.summary!.phase, 'pause_requested');
    expect(requested.allowedActions, isEmpty);
    final paused = await box.tick(count: 14);
    expect(paused.state, SmartFollowState.paused);
    expect(paused.recognizedCount, 14);
    expect(paused.eligibleCount, 5);
    expect(paused.copiedFileCount, 0);
    expect((await box.client.get('/api/v1/jobs/${box.jobId}'))['job_state'], 'completed');
    await box.act(SmartFollowAction.resume);
    final completed = await box.finish();
    expect(completed.state, SmartFollowState.completed);
    expect(completed.copiedFileCount, 5);
    final files = await box.api.fileItems(box.sid);
    expect(files.items.map((item) => item.fileId).toSet(), hasLength(5));
    expect(files.items.every((item) => item.state == 'copied' && item.attemptCount == 1), true);
  });

  test('110 replay overlaps recognition and copying but only copies the 38 high-confidence files', () async {
    final box = await fixture(RepairAcceptanceProfile.repair110);
    await box.start();
    final active = await box.tick(count: 10);
    expect(active.recognizedCount, 10);
    expect(active.copiedFileCount, 3);
    expect(active.recognizedCount, lessThan(110));
    final completed = await box.finish();
    expect(completed.recognizedCount, 110);
    expect(completed.eligibleCount, 38);
    expect(completed.copiedFileCount, 38);
    expect(completed.failedAssetCount, 0);
    final fileIds = (await box.api.fileItems(box.sid)).items.map((item) => item.fileId).toSet();
    expect(fileIds, (await box.category({'recognition_state': 'recognized'})).map((row) => row['file_id']).toSet());
    final events = await box.client.get('/api/v1/jobs/${box.jobId}/recognition-events');
    final rows = (events['items'] as List).cast<Map>();
    expect(rows, hasLength(110));
    expect(rows.where((row) => row['eligible'] == true), hasLength(38));
    expect(rows.map((row) => row['file_id']).toSet(), hasLength(110));
  });

  for (final scenario in {
    'wait_writer': 'waiting_for_writer',
    'wait_target': 'waiting_target',
    'wait_source': 'waiting_source',
    'storage_unavailable': 'waiting_for_storage',
  }.entries) {
    test('${scenario.key} retains the queue, allows AI to finish, and never bypasses the blocker on resume', () async {
      final box = await fixture();
      await box.start();
      await box.control(scenario.key);
      final waiting = await box.tick(count: 14);
      expect(waiting.recognizedCount, 14);
      expect(waiting.copiedFileCount, 0);
      expect(resolveSmartFollowStage(session: waiting).id, scenario.value);
      await box.act(SmartFollowAction.pause);
      await box.tick(count: 0);
      await box.act(SmartFollowAction.resume);
      expect((await box.tick(count: 0)).copiedFileCount, 0);
      await expectLater(box.control('recover', {'target_media_id': 'another-disk'}), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)));
      await box.control('recover', {'target_media_id': _Fixture.target});
      expect((await box.finish()).copiedFileCount, 5);
    });
  }

  test('awaiting results and invalid controls do not manufacture recognition or successful files', () async {
    final box = await fixture();
    await box.start();
    await box.control('await_results');
    final waiting = await box.tick(count: 0);
    expect(waiting.summary!.phase, 'awaiting_results');
    expect(waiting.recognizedCount, 0);
    expect(waiting.copiedFileCount, 0);
    await expectLater(box.control('tick', {'recognition_count': -1}), throwsA(isA<ApiException>()));
    await expectLater(box.control('finish_recognition'), throwsA(isA<ApiException>()));
    expect((await box.api.session(box.sid)).recognizedCount, 0);
  });

  test('one write failure stays failed in completion and file details', () async {
    final box = await fixture();
    await box.start();
    await box.control('fail_next_write');
    await box.tick(count: 14);
    final result = await box.finish();
    expect(result.state, SmartFollowState.completedPartial);
    expect(result.copiedFileCount, 4);
    expect(result.failedAssetCount, 1);
    final files = (await box.api.fileItems(box.sid)).items;
    expect(files.where((item) => item.state == 'failed').single.errorCode, 'COPY_HASH_MISMATCH');
    expect(files.where((item) => item.state == 'copied'), hasLength(4));
  });

  test('fatal copy failure holds its queue while the independent analysis continues', () async {
    final box = await fixture();
    await box.start();
    await box.tick(count: 3, writes: false);
    await box.control('fail');
    final failed = await box.tick(count: 14);
    expect(failed.state, SmartFollowState.failed);
    expect(failed.recognizedCount, 14);
    expect(failed.copiedFileCount, 0);
    expect(failed.summary!.fileCounts['blocked'], 3);
    expect(failed.errorCode, 'SMART_FOLLOW_RECONCILIATION_REQUIRED');
  });

  for (final action in [SmartFollowAction.finishCurrentResults, SmartFollowAction.stopFollowing]) {
    test('${action.wire} freezes its cutoff while future AI results stay outside this copy session', () async {
      final box = await fixture(RepairAcceptanceProfile.repair110);
      await box.start();
      await box.tick(count: 10);
      await box.act(action);
      var result = await box.tick(count: 110);
      if (!result.isFinished) result = await box.finish();
      expect(result.state, SmartFollowState.completedPartial);
      expect(result.recognizedCount, 110);
      expect(result.eligibleCount, 10);
      expect(result.copiedFileCount, action == SmartFollowAction.finishCurrentResults ? 10 : 3);
      final raw = await box.client.get('/api/v1/smart-follow-sessions/${box.sid}');
      expect(raw['cutoff_event_seq'], 10);
      expect(raw['last_consumed_event_seq'], 10);
      final files = (await box.api.fileItems(box.sid)).items;
      expect(files.where((item) => item.state == 'stopped').length, action == SmartFollowAction.stopFollowing ? 7 : 0);
    });
  }

  test('waiting queue and exact file outcomes survive restart, with profile state isolation', () async {
    final directory = await Directory.systemTemp.createTemp('repair-workflow-state-');
    addTearDown(() => directory.delete(recursive: true));
    final state = File('${directory.path}/state.json');
    final box = await fixture(RepairAcceptanceProfile.repair14, state);
    await box.start();
    await box.control('wait_target');
    await box.tick(count: 14);
    final sid = box.sid;
    await box.close();
    expect(() => MockBoxServer(acceptanceProfile: RepairAcceptanceProfile.repair110, stateFile: state), throwsFormatException);
    expect(() => MockBoxServer(photoCount: 14, embeddedDemo: true, stateFile: state), throwsFormatException);
    await box.open();
    expect((await box.api.session(sid)).state, SmartFollowState.waitingForTarget);
    expect((await box.tick(count: 0)).copiedFileCount, 0);
    await box.control('recover');
    expect((await box.finish()).copiedFileCount, 5);
    await box.close();
    await box.open();
    expect((await box.api.session(sid)).copiedFileCount, 5);
    expect((await box.tick(count: 0)).copiedFileCount, 5);
    expect((await box.api.fileItems(sid)).items.map((item) => item.fileId).toSet(), hasLength(5));
  });

  test('profiles require explicit selection and reject ambiguous photo counts', () {
    expect(RepairAcceptanceProfile.parse('demo'), null);
    expect(RepairAcceptanceProfile.parse('repair-110'), RepairAcceptanceProfile.repair110);
    expect(() => RepairAcceptanceProfile.parse('unrecognized-profile'), throwsFormatException);
    expect(() => MockBoxServer(acceptanceProfile: RepairAcceptanceProfile.repair14, photoCount: 110), throwsArgumentError);
    final generic = MockBoxServer(embeddedDemo: true, photoCount: 60);
    expect(generic.acceptanceProfile, null);
    expect(generic.photoCount, 60);
  });
}
