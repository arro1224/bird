import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real Python: atomic create, same-token replay, preference CAS and copied-file hashes agree', () async {
    HttpOverrides.global = null;
    final client = ApiClient()..configure(Uri.parse(Platform.environment['BIRDBOX_ATOMIC_BASE']!));
    addTearDown(client.dispose);
    final pairing = await client.post(ApiEndpoints.devicePair, data: {'pairing_code': '123456', 'client_name': 'atomic local test'}, idempotencyKey: 'atomic-app-pair-1');
    client.setSession(accessToken: pairing['access_token'] as String);
    final fixture = await client.get('/local-atomic-fixture');
    final body = Map<String, dynamic>.from(fixture['body'] as Map);
    final api = CopyApi(client);
    expect((await api.capabilities()).atomicPreferencesOnCreate, isTrue);
    final draft = CopyRequestDraft(batchId: body['batch_id'] as String, sourceMediaId: fixture['source_media_id'] as String,
      sourceBindingToken: body['source_binding_token'] as String, targetMediaId: body['target_media_id'] as String,
      scope: CopyScope.batchAllAssets, expectedPreferencesVersion: 1, pairPolicy: PairPolicy.both,
      conflictStrategy: ConflictStrategy.skip, reviewExport: const ReviewExportConfig.disabled(), savePreferencesOnCreate: true);
    final job = await api.createJob(draft, body['preview_token'] as String);
    expect(job.savedPreferences!.version, 2);
    expect(job.savedPreferences!.pairPolicy, PairPolicy.both);
    final replay = await api.createJob(draft, body['preview_token'] as String);
    expect(replay.copyJobId, job.copyJobId);
    expect((await api.preferences()).version, 2);
    for (var attempt = 0; attempt < 100; attempt++) {
      final detail = await api.getJob(job.copyJobId);
      if (detail.state.isTerminal) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final report = await api.jobReport(job.copyJobId);
    expect(report.failedFiles, 0);
    final files = await client.get('/local-atomic-fixture/files');
    expect(files['file_count'], greaterThan(0));
    expect(files['all_hashes_match'], isTrue);
    expect(files['file_count'], report.copiedFiles);
  }, skip: Platform.environment['BIRDBOX_ATOMIC_BASE'] == null ? 'Requires separate loopback Python atomic-create fixture.' : false);
}
