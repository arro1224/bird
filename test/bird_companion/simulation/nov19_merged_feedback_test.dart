import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the new remote project/auto-drive paths with the local repair contract.
void main() {
  Future<(MockBoxServer, ApiClient)> open({RepairAcceptanceProfile? profile, bool workflow = false, bool autoFollow = false}) async {
    final server = MockBoxServer(
      photoCount: profile == null ? 14 : null,
      acceptanceProfile: profile,
      workflowAutoAdvance: workflow,
      autoSmartFollow: autoFollow,
      logRequests: false,
    );
    final client = ApiClient()..configure(await server.start());
    addTearDown(() async {
      await client.dispose();
      await server.close();
    });
    return (server, client);
  }

  Future<String> importedProject(MockBoxServer server, ApiClient client) async {
    final project = await client.post('/api/v1/projects', data: const {'name': '合并后验收', 'card_id': 'card-mock-001'});
    final id = project['project_id'] as String;
    final job = await client.post('/api/v1/projects/$id/imports', data: const {'source': 'card', 'read_only': true});
    await server.completeJob(job['job_id'] as String);
    return id;
  }

  Future<Map> current(ApiClient client) async => (await client.get('/api/v1/projects/current'))['batch'] as Map;

  for (final profile in RepairAcceptanceProfile.values) {
    test('${profile.id}: newly imported project retains recognition counts after single and batch decisions', () async {
      final (server, client) = await open(profile: profile);
      final project = await importedProject(server, client);
      final analysis = await client.post('/api/v1/projects/$project/analysis-jobs', data: const {'mode': 'standard'});
      await server.completeJob(analysis['job_id'] as String);
      final expected = profile == RepairAcceptanceProfile.repair110 ? [38, 48, 24] : [5, 6, 3];

      Future<void> check() async {
        final batch = await current(client);
        expect(batch['total_files'], profile.total);
        expect(batch['pending_review_count'], expected[1]);
        expect(batch['recognized_count'], expected[0]);
        expect(batch['filtered_count'], expected[2]);
        final page = await client.get('/api/v1/projects/$project/files', queryParameters: const {'recognition_state': 'needs_review', 'page_size': 100});
        expect((page['items'] as List).length, batch['pending_review_count']);
      }

      await check();
      await client.post('/api/v1/files/${profile.manualSpeciesFileId}/decision', data: const {'version': 0, 'keep_state': 'keep'});
      await check();
      await client.post(
        '/api/v1/projects/$project/files/actions',
        data: {
          'file_ids': [for (var i = 1; i <= profile.total; i++) 'photo-${i.toString().padLeft(4, '0')}'],
          'operation': 'discard',
          'version': (await current(client))['version'],
        },
      );
      await check();
      expect((await current(client))['discard_count'], profile.total);
    });
  }

  test('new project summary reflects the first single-photo decision immediately', () async {
    final (server, client) = await open();
    final project = await importedProject(server, client);
    final analysis = await client.post('/api/v1/projects/$project/analysis-jobs', data: const {'mode': 'standard'});
    await server.completeJob(analysis['job_id'] as String);
    final before = await current(client);
    final page = await client.get('/api/v1/projects/$project/files', queryParameters: const {'keep_state': 'pending'});
    final file = (page['items'] as List).first as Map;
    final id = file['file_id'];
    final detail = await client.get('/api/v1/files/$id');
    await client.post('/api/v1/files/$id/decision', data: {'version': (detail['decision'] as Map)['version'], 'keep_state': 'keep'});
    final after = await current(client);
    expect(after['keep_count'], (before['keep_count'] as int) + 1);
    expect(after['pending_review_count'], (before['pending_review_count'] as int) - 1);
  });

  test('acceptance and auto-follow use one driver, keeping analysis and session progress aligned', () async {
    final (_, client) = await open(profile: RepairAcceptanceProfile.repair110, workflow: true, autoFollow: true);
    final job = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: const {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    final api = SmartFollowApi(client);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    SmartFollowSession session;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      session = await api.session(job['smart_follow_session_id'] as String);
    } while (session.recognizedCount == 0 && DateTime.now().isBefore(deadline));
    final snapshot = await client.get('/api/v1/jobs/${job['job_id']}');
    expect(session.recognizedCount, 5, reason: 'The existing acceptance driver advances five results per tick.');
    expect(snapshot['finished_count'], session.recognizedCount);
  });

  test('auto-follow alone preserves acceptance pause, independent AI completion and exact-once copying', () async {
    final (_, client) = await open(profile: RepairAcceptanceProfile.repair14, autoFollow: true);
    final job = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: const {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    final api = SmartFollowApi(client);
    final sid = job['smart_follow_session_id'] as String;
    var session = await api.session(sid);
    await api.act(sid, SmartFollowAction.pause, expectedStateVersion: session.stateVersion);
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      session = await api.session(sid);
    } while (DateTime.now().isBefore(deadline) && session.recognizedCount < 14);
    expect(session.state, SmartFollowState.paused);
    expect(session.recognizedCount, 14);
    expect(session.copiedFileCount, 0);
    expect((await client.get('/api/v1/jobs/${job['job_id']}'))['job_state'], 'completed');
    await api.act(sid, SmartFollowAction.resume, expectedStateVersion: session.stateVersion);
    final finishDeadline = DateTime.now().add(const Duration(seconds: 8));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      session = await api.session(sid);
    } while (DateTime.now().isBefore(finishDeadline) && !session.isFinished);
    expect(session.state, SmartFollowState.completed);
    expect(session.eligibleCount, 5);
    expect(session.copiedFileCount, 5);
    final files = await api.fileItems(sid);
    expect(files.items.map((item) => item.fileId).toSet(), hasLength(5));
    expect(files.items.every((item) => item.state == 'copied' && item.attemptCount == 1), true);
  });
}
