import 'dart:async';

import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/sync/bird_sync_service.dart';
import 'package:aves/bird_companion/core/sync/sync_coordinator.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_cubit.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nov18_repair_test_support.dart';

void expectOriginal(RecognitionResult? ai) {
  expect(ai!.candidates.map((candidate) => candidate.confidence), [.42, .37]);
  expect(ai.candidates.map((candidate) => candidate.speciesId), ['common-kingfisher', 'little-egret']);
  expect(ai.isLowConfidence, true);
  expect(ai.verdict, 'medium');
  expect(ai.top1Class, 'Alcedo_atthis');
}

void main() {
  Future<RepairTestContext> fixture() async {
    final value = RepairTestContext(RepairAcceptanceProfile.repair14);
    await value.open();
    addTearDown(value.close);
    return value;
  }

  Future<UserDecision> selectSecond(RepairTestContext context) async {
    final detail = await context.reviews.detail(context.manualId);
    final receipt = await context.reviews.saveAuthoritative(
      UserDecision(fileId: context.manualId, keepState: KeepState.keep, userSpeciesId: 'little-egret', userSpecies: '白鹭', userScore: 4, userTags: const ['原标签'], version: detail.decision!.version),
      projectId: RepairTestContext.project,
    );
    return receipt.authoritativeDecision!;
  }

  test('second candidate remains 37 percent and both AI candidates survive all cached views and a fresh repository', () async {
    final context = await fixture();
    await context.photos.page(RepairTestContext.project, const PhotoQuery());
    final saved = await selectSecond(context);
    expect(saved.version, 1);
    final repository = context.freshReviewRepository();
    final detail = await repository.detail(context.manualId);
    expectOriginal(detail.photo.summary.recognition);
    expect(detail.decision!.userSpecies, '白鹭');
    expect(detail.photo.summary.userSpecies, '白鹭');
    final groups = await repository.groups(RepairTestContext.project);
    final member = groups.expand((group) => group.members).singleWhere((photo) => photo.id == context.manualId);
    expectOriginal(member.recognition);
    expect(member.userSpecies, '白鹭');
    await context.photos.invalidateLocalQueries(RepairTestContext.project);
    final page = await context.photos.page(RepairTestContext.project, const PhotoQuery(recognitionState: 'needs_review'));
    final photo = page.items.singleWhere((photo) => photo.id == context.manualId);
    expectOriginal(photo.recognition);
    expect(photo.userSpecies, '白鹭');
    expect(page.items, hasLength(6));
  });

  test('restore on a cold repository sends exactly version and two explicit nulls, retaining other fields', () async {
    final context = await fixture();
    final saved = await selectSecond(context);
    context.cache.values.clear();
    final restored = await context.freshReviewRepository().restoreAiSpecies(saved, projectId: RepairTestContext.project);
    expect(restored.conflict, false);
    expect(context.writes.last, {'version': 1, 'user_species_id': null, 'user_species': null});
    final detail = await context.freshReviewRepository().detail(context.manualId);
    expectOriginal(detail.photo.summary.recognition);
    expect(detail.decision!.userSpecies, null);
    expect(detail.decision!.userSpeciesId, null);
    expect(detail.decision!.keepState, KeepState.keep);
    expect(detail.decision!.userScore, 4);
    expect(detail.decision!.userTags, ['原标签']);
  });

  test('restoring differs from undo; both retain the immutable AI result', () async {
    final context = await fixture();
    await selectSecond(context);
    final cubit = PhotoDetailCubit(context.reviews, null, context.bus, RepairTestContext.project);
    addTearDown(cubit.close);
    await cubit.load(context.manualId);
    await cubit.restoreAiSpecies();
    expect(cubit.state.detail!.decision!.userSpecies, null);
    expect(cubit.state.canUndo, true);
    expectOriginal(cubit.state.detail!.photo.summary.recognition);
    await cubit.undo();
    expect(cubit.state.detail!.decision!.userSpecies, '白鹭');
    expectOriginal(cubit.state.detail!.photo.summary.recognition);
    expect(cubit.state.detail!.decision!.userTags, ['原标签']);
  });

  test('409 restore reloads the newer decision and never automatically resubmits it', () async {
    final context = await fixture();
    await selectSecond(context);
    final cubit = PhotoDetailCubit(context.reviews, null, context.bus, RepairTestContext.project);
    addTearDown(cubit.close);
    await cubit.load(context.manualId);
    await context.client.post(
      '/api/v1/files/${context.manualId}/decision',
      data: {
        'version': 1,
        'user_species_id': 'remote-species',
        'user_species': '他端鸟种',
        'user_score': 4.8,
        'user_tags': ['他端标签'],
      },
    );
    context.writes.clear();
    await cubit.restoreAiSpecies();
    expect(cubit.state.conflict, true);
    expect(cubit.state.detail!.decision!.version, 2);
    expect(cubit.state.detail!.decision!.userSpecies, '他端鸟种');
    expect(cubit.state.detail!.decision!.userTags, ['他端标签']);
    expect(context.writes, hasLength(1));
    await cubit.restoreAiSpecies();
    expect(context.writes, hasLength(1));
    await cubit.useRemote(context.manualId);
    await cubit.restoreAiSpecies();
    expect(context.writes.last, {'version': 2, 'user_species_id': null, 'user_species': null});
    expect(cubit.state.detail!.decision!.userScore, 4.8);
    expect(cubit.state.detail!.decision!.userTags, ['他端标签']);
  });

  test('offline edit then restore merges its narrow clear without losing unsent tags, and replays once on reconnect', () async {
    final context = await fixture();
    final saved = await selectSecond(context);
    context.connectivity.online = false;
    final edited = await context.reviews.saveAuthoritative(
      UserDecision(fileId: saved.fileId, keepState: saved.keepState, userSpeciesId: saved.userSpeciesId, userSpecies: saved.userSpecies, userScore: saved.userScore, userTags: const ['原标签', '离线标签'], version: saved.version),
      projectId: RepairTestContext.project,
    );
    final restored = await context.reviews.restoreAiSpecies(edited.authoritativeDecision!, projectId: RepairTestContext.project);
    expect(restored.queued, true);
    final operation = context.pending.readAll().single;
    expect(operation.payload['version'], 1);
    expect(operation.payload['user_species_id'], null);
    expect(operation.payload['user_species'], null);
    expect(operation.payload['user_tags'], ['原标签', '离线标签']);
    expect(operation.payload.containsKey('user_score'), false);
    expectOriginal((await context.freshReviewRepository().detail(context.manualId)).photo.summary.recognition);
    context.connectivity.online = true;
    final sync = BirdSyncService(context.connectivity, SyncCoordinator(context.pending), context.client, context.bus, () => context.deviceId, null, context.reviews.acceptSyncedPhoto);
    addTearDown(sync.dispose);
    final result = await sync.synchronize();
    expect(result.syncedCount, 1);
    expect(result.failedOperations, isEmpty);
    expect(context.pending.readAll(), isEmpty);
    final finalDetail = await context.freshReviewRepository().detail(context.manualId);
    expect(finalDetail.decision!.userSpecies, null);
    expect(finalDetail.decision!.userTags, ['原标签', '离线标签']);
    expect(finalDetail.decision!.userScore, 4);
    expectOriginal(finalDetail.photo.summary.recognition);
    expect((await sync.synchronize()).syncedCount, 0);
  });

  test('offline restart reads separate manual fields and original AI from local cache', () async {
    final context = await fixture();
    await selectSecond(context);
    await context.server.close();
    final detail = await context.freshReviewRepository().detail(context.manualId);
    expectOriginal(detail.photo.summary.recognition);
    expect(detail.decision!.userSpecies, '白鹭');
  });

  test('a legacy overwritten cache remains unverified after an offline restore instead of inventing an AI probability', () async {
    final context = await fixture();
    await selectSecond(context);
    final key = 'album:detail:box-a:${context.manualId}';
    final cached = Map<String, dynamic>.from(context.cache.read<Map>(key)!);
    cached.remove('_app_review_projection_version');
    final file = Map<String, dynamic>.from(cached['file'] as Map);
    file['recognition'] = {
      'species_topn': [
        {'species_id': 'little-egret', 'name': '白鹭', 'confidence': .42},
      ],
      'low_confidence': false,
    };
    cached['file'] = file;
    await context.cache.write(key, cached);
    await context.server.close();
    context.connectivity.online = false;
    final repository = context.freshReviewRepository();
    final detail = await repository.detail(context.manualId);
    expect(detail.photo.summary.recognition!.isOriginalVerified, false);
    await repository.restoreAiSpecies(detail.decision!, projectId: RepairTestContext.project);
    final restored = await context.freshReviewRepository().detail(context.manualId);
    expect(restored.decision!.userSpecies, null);
    expect(restored.photo.summary.recognition!.isOriginalVerified, false);
  });

  test('a missing decision uses version zero even if the file has a nonzero analysis version', () async {
    final context = await fixture();
    context.dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          if (response.requestOptions.method == 'GET' && response.requestOptions.path == '/api/v1/files/${context.manualId}') {
            final body = (response.data as Map)['data'] as Map;
            body.remove('decision');
            (body['file'] as Map)['version'] = 19;
          }
          handler.next(response);
        },
      ),
    );
    final detail = await ReviewApi(context.client).detail(context.manualId);
    expect(detail.photo.summary.version, 19);
    expect(detail.decision!.version, 0);
    expect(detail.decision!.userSpecies, null);
  });

  test('late detail from a prior device cannot populate the new device cache', () async {
    final context = await fixture();
    final arrived = Completer<void>(), release = Completer<void>();
    context.dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) async {
          if (response.requestOptions.path == '/api/v1/files/${context.manualId}') {
            arrived.complete();
            await release.future;
          }
          handler.next(response);
        },
      ),
    );
    final loading = context.reviews.detail(context.manualId);
    final rejected = expectLater(loading, throwsStateError);
    await arrived.future;
    context.deviceId = 'box-b';
    release.complete();
    await rejected;
    expect(context.cache.keysWithPrefix('album:detail:box-b:'), isEmpty);
  });

  test('late restore acknowledgement cannot project prior-device manual data into the new device', () async {
    final context = await fixture();
    final saved = await selectSecond(context);
    final arrived = Completer<void>(), release = Completer<void>();
    context.dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) async {
          if (response.requestOptions.method == 'POST' && response.requestOptions.path.endsWith('/decision')) {
            arrived.complete();
            await release.future;
          }
          handler.next(response);
        },
      ),
    );
    final saving = context.reviews.restoreAiSpecies(saved, projectId: RepairTestContext.project);
    final rejected = expectLater(saving, throwsStateError);
    await arrived.future;
    context.deviceId = 'box-b';
    release.complete();
    await rejected;
    expect(context.cache.keysWithPrefix('album:detail:box-b:'), isEmpty);
    expect(context.pending.readAll(), isEmpty);
  });
}
