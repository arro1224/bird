import 'dart:async';

import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_repository.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:aves/bird_companion/features/gallery/presentation/gallery_cubit.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nov18_repair_test_support.dart';

void main() {
  Future<RepairTestContext> fixture([RepairAcceptanceProfile profile = RepairAcceptanceProfile.repair14]) async {
    final context = RepairTestContext(profile);
    await context.open();
    addTearDown(context.close);
    return context;
  }

  for (final profile in RepairAcceptanceProfile.values) {
    test('${profile.id}: production gallery matches all three frozen classes and refreshes authoritative counts', () async {
      final context = await fixture(profile);
      final gallery = context.gallery();
      addTearDown(gallery.close);
      final ids = <String>{};
      for (final category in ['recognized', 'needs_review', 'filtered']) {
        await gallery.refresh(
          query: const PhotoQuery(search: 'old search', minConfidence: .99, keepState: 'keep', analysisState: 'completed', recognitionState: 'recognized').forQuickCategory(category),
        );
        final expected = category == 'recognized'
            ? profile.high
            : category == 'needs_review'
            ? profile.needsReview
            : profile.filtered;
        expect(gallery.state.items, hasLength(expected));
        expect(gallery.state.resultComplete, true);
        ids.addAll(gallery.state.items.map((photo) => photo.id));
      }
      await gallery.refreshSummary(force: true);
      expect(ids, hasLength(profile.total));
      expect(gallery.state.recognizedCount, profile.high);
      expect(gallery.state.pendingCount, profile.needsReview);
      expect(gallery.state.filteredCount, profile.filtered);
      expect(gallery.state.countsStatus, GalleryCountsStatus.fresh);
      expect(gallery.state.countsNeedVersionCheck, false);
    });
  }

  test('manual keep does not change recognition membership or review total after refresh', () async {
    final context = await fixture();
    final gallery = context.gallery();
    addTearDown(gallery.close);
    await gallery.refresh(query: const PhotoQuery(recognitionState: 'needs_review'));
    await gallery.refreshSummary();
    final detail = await context.reviews.detail(context.manualId);
    await context.reviews.saveAuthoritative(
      UserDecision(fileId: context.manualId, keepState: KeepState.keep, version: detail.decision!.version),
      projectId: RepairTestContext.project,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await gallery.refresh();
    await gallery.refreshSummary();
    expect(gallery.state.items, hasLength(6));
    expect(gallery.state.items.singleWhere((photo) => photo.id == context.manualId).keepState, 'keep');
    expect(gallery.state.pendingCount, 6);
    expect(gallery.state.keepCount, 1);
    expect(gallery.state.recognizedCount, 5);
  });

  test('recognition event refreshes counts in place without changing selected query', () async {
    final context = await fixture();
    final gallery = context.gallery();
    addTearDown(gallery.close);
    const query = PhotoQuery(recognitionState: 'needs_review');
    await gallery.refresh(query: query);
    await gallery.refreshSummary();
    await context.client.post('/mock/control/acceptance', data: {'action': 'set_analysis_state', 'file_id': context.manualId, 'analysis_state': 'failed'});
    context.bus.publishChange(RecognitionFactsChanged(deviceId: context.deviceId, projectId: RepairTestContext.project, fileIds: {context.manualId}));
    await waitUntil(() => gallery.state.pendingCount == 5 && !gallery.state.loading);
    expect(gallery.state.query.recognitionState, 'needs_review');
    expect(gallery.state.items, hasLength(5));
    expect(gallery.state.recognizedCount! + gallery.state.pendingCount! + gallery.state.filteredCount!, lessThan(14));
  });

  test('a batch edit in another retained view updates visible rows and authoritative totals without changing recognition count', () async {
    final context = await fixture();
    final gallery = context.gallery();
    addTearDown(gallery.close);
    await gallery.refresh(query: const PhotoQuery(recognitionState: 'needs_review'));
    await gallery.refreshSummary();
    final outcome = await context.photos.batchOperation(RepairTestContext.project, [context.manualId], 'keep', version: 0);
    expect(outcome.succeededIds, [context.manualId]);
    context.bus.publishChange(
      BatchReviewDecisionChanged(
        deviceId: context.deviceId,
        projectId: RepairTestContext.project,
        transitions: [ReviewStateTransition(fileId: context.manualId, before: KeepState.pending, after: KeepState.keep)],
        queued: false,
      ),
    );
    await waitUntil(() => gallery.state.keepCount == 1);
    expect(gallery.state.pendingCount, 6);
    expect(gallery.state.items.singleWhere((photo) => photo.id == context.manualId).keepState, 'keep');
    expect(gallery.state.query.recognitionState, 'needs_review');
  });

  test('unknown counts remain unknown and an old 72 summary is flagged, never corrected by subtraction', () async {
    final context = await fixture();
    final gallery = context.gallery();
    addTearDown(gallery.close);
    expect(gallery.state.pendingCount, null);
    expect(gallery.state.recognizedCount, null);
    expect(gallery.state.countsStatus, GalleryCountsStatus.unread);
    gallery.applyBatchSummary(batch(pending: 72), deviceId: 'box-a');
    expect(gallery.state.pendingCount, 72);
    expect(gallery.state.recognizedCount, null);
    expect(gallery.state.filteredCount, null);
    expect(gallery.state.countsNeedVersionCheck, true);
  });

  test('retained gallery accepts newer same-device summaries, rejects other projects/devices and stale timestamps', () async {
    final context = await fixture();
    final gallery = context.gallery();
    addTearDown(gallery.close);
    final now = DateTime.now();
    gallery.applyBatchSummary(batch(pending: 6, at: now), deviceId: 'box-a');
    gallery.applyBatchSummary(batch(pending: 99, at: now.add(const Duration(seconds: 1))), deviceId: 'box-b');
    gallery.applyBatchSummary(
      batch(id: 'other-project', pending: 98, at: now.add(const Duration(seconds: 2))),
      deviceId: 'box-a',
    );
    gallery.applyBatchSummary(batch(pending: 97, at: now.subtract(const Duration(seconds: 1))), deviceId: 'box-a');
    expect(gallery.state.pendingCount, 6);
    gallery.applyBatchSummary(batch(pending: 5, at: now.add(const Duration(seconds: 3))), deviceId: 'box-a');
    expect(gallery.state.pendingCount, 5);
  });

  test('summary failure retains prior count and timestamp; a new device cannot receive a late prior-device result', () async {
    final context = await fixture();
    final reader = _ControlledSummary();
    final gallery = GalleryCubit(context.photos, RepairTestContext.project, null, null, null, null, () => context.deviceId, null, null, reader);
    addTearDown(gallery.close);
    final now = DateTime.now();
    gallery.applyBatchSummary(batch(pending: 6, at: now), deviceId: 'box-a');
    final failed = gallery.refreshSummary(force: true);
    reader.requests.single.completeError(StateError('unreachable'));
    await failed;
    expect(gallery.state.pendingCount, 6);
    expect(gallery.state.countsUpdatedAt, now);
    expect(gallery.state.countsStatus, GalleryCountsStatus.stale);
    final old = gallery.refreshSummary(force: true);
    context.deviceId = 'box-b';
    await gallery.refresh(query: const PhotoQuery());
    reader.requests[1].complete(batch(pending: 99, at: DateTime.now()));
    reader.requests[2].complete(batch(pending: 3, at: DateTime.now()).copyWith(countsDeviceId: 'box-b'));
    await old;
    await gallery.refreshSummary();
    expect(gallery.state.pendingCount, 3);
  });

  test('legacy pending saved view migrates to review, new explicit unmarked view is preserved', () {
    final old = resolveInitialPhotoQuery(fallback: const PhotoQuery(), savedView: {'keep_state': 'pending', 'recognition_state': 'recognized', 'search': 'egret'}, restoreSavedView: true);
    expect(old.keepState, null);
    expect(old.recognitionState, 'needs_review');
    expect(old.search, 'egret');
    final current = resolveInitialPhotoQuery(fallback: const PhotoQuery(), savedView: {'view_schema_version': 2, 'keep_state': 'pending'}, restoreSavedView: true);
    expect(current.keepState, 'pending');
    expect(current.recognitionState, null);
  });
}

BatchSummary batch({String id = RepairTestContext.project, int pending = 6, DateTime? at}) => BatchSummary(
  id: id,
  name: 'test',
  createdAt: DateTime.utc(2026, 11, 18),
  totalFiles: 110,
  analyzedCount: 110,
  reviewCount: pending,
  keepCount: 0,
  discardCount: 0,
  pendingCopyCount: 0,
  copyState: 'idle',
  countsUpdatedAt: at,
  countsDeviceId: 'box-a',
);

class _ControlledSummary implements BatchSummaryReader {
  final requests = <Completer<BatchSummary?>>[];
  @override
  Future<BatchSummary?> summary(String projectId) {
    final result = Completer<BatchSummary?>();
    requests.add(result);
    return result.future;
  }
}

Future<void> waitUntil(bool Function() predicate) async {
  for (var index = 0; index < 100; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected gallery update did not arrive');
}
