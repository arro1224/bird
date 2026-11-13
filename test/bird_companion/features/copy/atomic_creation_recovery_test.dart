import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_test/flutter_test.dart';

class IntentStorage implements DiagnosticStorage {
  final values = <String, Object?>{};
  bool failWrites = false;
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async { if (failWrites) throw StateError('disk unavailable'); values[key] = value; }
  @override
  Future<void> remove(String key) async { values.remove(key); }
}

class CreateClient extends ApiClient {
  bool fail = true;
  final bodies = <Object?>[];
  final keys = <String?>[];
  @override
  Uri? get baseUri => Uri.parse('http://local-test');
  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) async {
    bodies.add(data); keys.add(idempotencyKey);
    if (fail) throw const ApiException(message: 'lost response', retryable: true);
    return {'copy_job_id': 'original-job', 'state': 'queued', 'event_seq': 1, 'saved_preferences': {'pair_policy': 'both', 'preferences_version': 2, 'origin': 'user_saved'}};
  }
}

const draft = CopyRequestDraft(batchId: 'batch', scope: CopyScope.batchAllAssets, sourceMediaId: 'source', sourceBindingToken: 'binding-original', targetMediaId: 'target', expectedPreferencesVersion: 1, pairPolicy: PairPolicy.both, conflictStrategy: ConflictStrategy.skip, reviewExport: ReviewExportConfig.disabled(), savePreferencesOnCreate: true);

void main() {
  test('lost response survives API restart and a refreshed preview never replaces original create intent', () async {
    final storage = IntentStorage(), client = CreateClient();
    final api = CopyApi(client, creationStorage: storage, creationDeviceId: () => 'box-original');
    await expectLater(api.createJob(draft, 'rc3_preview_original'), throwsA(isA<ApiException>()));
    expect(storage.values, hasLength(1));
    client.fail = false;
    final restored = CopyApi(client, creationStorage: storage, creationDeviceId: () => 'box-original');
    final job = await restored.createJob(draft.copyWith(sourceBindingToken: 'binding-refreshed', expectedPreferencesVersion: 2), 'rc3_preview_new');
    expect(job.copyJobId, 'original-job');
    expect(client.keys, ['copy-atomic-rc3_preview_original', 'copy-atomic-rc3_preview_original']);
    expect(client.bodies[0], client.bodies[1]);
    expect((client.bodies.last as Map)['preview_token'], 'rc3_preview_original');
    expect(storage.values, isEmpty);
  });
  test('an unresolved request cannot be changed to another target', () async {
    final storage = IntentStorage(), client = CreateClient();
    final api = CopyApi(client, creationStorage: storage, creationDeviceId: () => 'box-original');
    await expectLater(api.createJob(draft, 'rc3_preview_original'), throwsA(isA<ApiException>()));
    await expectLater(api.createJob(draft.copyWith(targetMediaId: 'other-target'), 'rc3_preview_other'), throwsA(isA<CopyCreationPending>()));
    expect(client.bodies, hasLength(1));
  });
  test('intent storage failure prevents POST', () async {
    final storage = IntentStorage()..failWrites = true;
    final client = CreateClient();
    final api = CopyApi(client, creationStorage: storage, creationDeviceId: () => 'box-original');
    await expectLater(api.createJob(draft, 'rc3_preview_original'), throwsStateError);
    expect(client.bodies, isEmpty);
  });
}
