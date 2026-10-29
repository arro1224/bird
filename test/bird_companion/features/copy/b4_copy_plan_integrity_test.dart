import 'dart:async';
import 'package:aves/bird_companion/core/network/api_exception.dart';

import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_plan_integrity.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_preview_items_sheet.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

CopyJobItem item(int id, {CopyPlanState state = CopyPlanState.copy, int bytes = 100, String? filename, String? decision, String? asset}) => CopyJobItem(
  copyItemId: 'item-$id',
  assetId: asset,
  sourceRelativePath: 'DCIM/$id.ARW',
  sourceSize: bytes,
  targetRelativeDirectory: '20261023',
  targetFilename: filename ?? '$id.ARW',
  planState: state,
  conflictDecision: decision,
);

CopyPreview preview({int files = 1, int bytes = 100, int logical = 1, Duration lifetime = const Duration(minutes: 1), String? id}) => CopyPreview(
  previewToken: 'token',
  previewId: id,
  expiresAt: DateTime.now().add(lifetime),
  source: b3Device('source', source: true, target: false),
  target: b3Device('target'),
  logicalPhotoCount: logical,
  actualFileCount: files,
  totalBytes: bytes,
  rawCount: files,
  jpegCount: 0,
  videoCount: 0,
  companionCount: 0,
  estimatedDateDirectories: 1,
  conflictCount: 0,
  targetFreeBytes: 1000000,
  safetyReserveBytes: 100,
);

class Pages implements CopyJobRepository {
  Pages(this.read);
  final Future<CopyJobItemPage> Function(String, String?) read;
  @override
  Future<CopyJobItemPage> previewItems(String id, {String? cursor}) => read(id, cursor);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Pages onePage(List<CopyJobItem> items) => Pages((_, _) async => CopyJobItemPage(items: items, hasMore: false));
Future<CopyPlanIntegrity> verify(CopyPreview value, CopyJobRepository? repository, {CopyPlanVerifier verifier = const CopyPlanVerifier()}) => verifier.verify(value, repository, isCurrent: () => true);

Future<CopyConfigCubit> configured(FakeCopyEnvironment repository, {CopyScope scope = CopyScope.batchAllAssets, Map<String, dynamic>? filter, bool cleanup = true}) async {
  final cubit = CopyConfigCubit(repository, batchId: 'b', scope: scope, filter: filter, pollInterval: Duration.zero);
  if (cleanup) addTearDown(cubit.close);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.keepBoth);
  return cubit;
}

void main() {
  test('plan_state is independent of execution state and unknown is never copy', () {
    for (final entry in {
      'copy': CopyPlanState.copy,
      'skip_conflict': CopyPlanState.skipConflict,
      'not_applicable': CopyPlanState.notApplicable,
      'blocked': CopyPlanState.blocked,
      'future': CopyPlanState.unknown,
      null: CopyPlanState.unknown,
    }.entries) {
      final parsed = CopyJobItem.fromJson({'copy_item_id': 'i', 'state': 'completed', if (entry.key != null) 'plan_state': entry.key, 'conflict_decision': 'keep_both'});
      expect(parsed.planState, entry.value);
      expect(parsed.copyWith(state: CopyItemState.pending).planState, entry.value);
    }
  });

  test('five logical photos: two copies and three skips, bytes only from copies', () async {
    final result = await verify(preview(files: 2, bytes: 200, logical: 5), onePage([item(0), item(1), for (var i = 2; i < 5; i++) item(i, state: CopyPlanState.skipConflict)]));
    expect(result.status, CopyPlanIntegrityStatus.verified);
    expect(result.items.length, 5);
    expect(result.copyCount, 2);
    expect(result.skippedCount, 3);
    expect(result.copyBytes, 200);
    expect(result.items.clear, throwsUnsupportedError);
  });

  test('RAW/JPEG one asset two file rows does not compare logical assets to file count', () async {
    final result = await verify(preview(files: 2, bytes: 200, logical: 1), onePage([item(0, asset: 'photo'), item(1, asset: 'photo', filename: 'photo.JPG')]));
    expect(result.verified, true);
  });

  test('zero copy, all skipped is a complete plan', () async {
    final result = await verify(preview(files: 0, bytes: 0, logical: 2), onePage([item(0, state: CopyPlanState.skipConflict), item(1, state: CopyPlanState.skipConflict)]));
    expect(result.verified, true);
    expect(result.skippedCount, 2);
    expect(result.copyBytes, 0);
  });

  for (final testCase in <String, List<CopyJobItem>>{
    'missing/unknown plan_state': [item(0, state: CopyPlanState.unknown)],
    'duplicate stable item ID': [item(0), item(0)],
    'copy count mismatch': [item(0), item(1)],
    'byte mismatch': [item(0, bytes: 99)],
    'missing source identity': [const CopyJobItem(copyItemId: 'i', planState: CopyPlanState.copy, sourceSize: 100, targetFilename: 'x', targetRelativeDirectory: '')],
    'missing target filename': [const CopyJobItem(copyItemId: 'i', planState: CopyPlanState.copy, sourceSize: 100, sourceRelativePath: 'x')],
    'empty details with nonempty summary': [],
  }.entries) {
    test('${testCase.key} fails closed', () async {
      final result = await verify(preview(), onePage(testCase.value));
      expect(result.verified, false);
      expect(result.message, isNotEmpty);
    });
  }

  test('second page awaited; explicit preview_id used on every page', () async {
    final second = Completer<CopyJobItemPage>();
    final ids = <String>[], cursors = <String?>[];
    var completed = false;
    final pending =
        verify(
          preview(files: 2, bytes: 200, id: 'plan-id'),
          Pages((id, cursor) async {
            ids.add(id);
            cursors.add(cursor);
            return cursor == null ? CopyJobItemPage(items: [item(0)], hasMore: true, nextCursor: 'next') : second.future;
          }),
        ).then((result) {
          completed = true;
          return result;
        });
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    second.complete(CopyJobItemPage(items: [item(1)], hasMore: false));
    expect((await pending).verified, true);
    expect(ids, ['plan-id', 'plan-id']);
    expect(cursors, [null, 'next']);
  });

  test('looping cursor / no progress / contradictory pagination abort', () async {
    for (final page in [
      CopyJobItemPage(items: [item(0)], hasMore: true),
      const CopyJobItemPage(items: [], hasMore: true, nextCursor: 'x'),
      CopyJobItemPage(items: [item(0)], hasMore: false, nextCursor: 'x'),
      CopyJobItemPage.fromJson({'items': []}),
    ]) {
      expect((await verify(preview(), Pages((_, _) async => page))).verified, false);
    }
    var calls = 0;
    final result = await verify(preview(), Pages((_, _) async => CopyJobItemPage(items: [item(calls++)], hasMore: true, nextCursor: 'same')));
    expect(result.status, CopyPlanIntegrityStatus.inconsistent);
    expect(calls, 2);
  });

  test('duplicate across pages aborts rather than being silently deduplicated', () async {
    final result = await verify(preview(), Pages((_, cursor) async => CopyJobItemPage(items: [item(0)], hasMore: cursor == null, nextCursor: cursor == null ? 'next' : null)));
    expect(result.status, CopyPlanIntegrityStatus.inconsistent);
  });

  test('page and item caps and read timeout never produce a verified partial plan', () async {
    final endless = Pages((_, cursor) async => CopyJobItemPage(items: [item(int.tryParse(cursor ?? '') ?? 0)], hasMore: true, nextCursor: '${(int.tryParse(cursor ?? '') ?? 0) + 1}'));
    expect((await verify(preview(), endless, verifier: const CopyPlanVerifier(maxPages: 2))).verified, false);
    expect((await verify(preview(), onePage([item(0), item(1)]), verifier: const CopyPlanVerifier(maxItems: 1))).verified, false);
    expect((await verify(preview(), Pages((_, _) => Completer<CopyJobItemPage>().future), verifier: const CopyPlanVerifier(pageTimeout: Duration(milliseconds: 10)))).status, CopyPlanIntegrityStatus.unavailable);
  });

  test('expiry or cancellation during a hanging page interrupts verification', () async {
    final never = Pages((_, _) => Completer<CopyJobItemPage>().future);
    expect((await verify(preview(lifetime: const Duration(milliseconds: 20)), never)).status, CopyPlanIntegrityStatus.expired);
    var current = true;
    final pending = const CopyPlanVerifier().verify(preview(), never, isCurrent: () => current);
    current = false;
    expect((await pending).verified, false);
  });

  test('page transport failure and absent plan repository block', () async {
    expect((await verify(preview(), Pages((_, _) async => throw StateError('offline')))).status, CopyPlanIntegrityStatus.unavailable);
    expect((await verify(preview(), null)).status, CopyPlanIntegrityStatus.unavailable);
    expect((await verify(preview(), Pages((_, _) async => throw const ApiException(message: 'expired', code: 'COPY_PREVIEW_EXPIRED', statusCode: 409)))).status, CopyPlanIntegrityStatus.expired);
  });

  test('fractional byte size is not truncated into an apparently valid plan', () async {
    final parsed = CopyJobItem.fromJson({'copy_item_id': 'i', 'plan_state': 'copy', 'source_relative_path': 'x', 'source_size': 100.5, 'target_relative_directory': '', 'target_filename': 'x'});
    expect((await verify(preview(), onePage([parsed]))).verified, false);
  });

  test('semantic comparison ignores new IDs/order but includes conflict decisions', () async {
    final first = await verify(preview(files: 2, bytes: 200), onePage([item(0), item(1)]));
    final reordered = await verify(
      preview(files: 2, bytes: 200),
      onePage([item(1), const CopyJobItem(copyItemId: 'regenerated-id', sourceRelativePath: 'DCIM/0.ARW', sourceSize: 100, targetRelativeDirectory: '20261023', targetFilename: '0.ARW', planState: CopyPlanState.copy)]),
    );
    final changed = await verify(preview(files: 2, bytes: 200), onePage([item(0, decision: 'overwrite'), item(1)]));
    expect(first.signature, reordered.signature);
    expect(first.signature, isNot(changed.signature));
  });

  test('Cubit does not need the sheet to block inconsistent second page', () async {
    final repository = FakeCopyEnvironment();
    final second = Completer<CopyJobItemPage>();
    repository.readPlan = (_, cursor) async => cursor == null ? CopyJobItemPage(items: [item(0)], hasMore: true, nextCursor: 'next') : second.future;
    final cubit = await configured(repository);
    final pending = cubit.fetchPreview();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.planIntegrity?.status, CopyPlanIntegrityStatus.pending);
    expect(await cubit.submit(), false);
    second.complete(CopyJobItemPage(items: [item(1)], hasMore: false));
    expect(await pending, false);
    expect(cubit.state.planIntegrity?.status, CopyPlanIntegrityStatus.inconsistent);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('blocked and not applicable do not turn into copies under keep_both', () async {
    final repository = FakeCopyEnvironment();
    repository.readPlan = (_, _) async => CopyJobItemPage(
      items: [
        item(0),
        item(1, state: CopyPlanState.blocked, decision: 'keep_both'),
        item(2, state: CopyPlanState.notApplicable, decision: 'keep_both'),
      ],
      hasMore: false,
    );
    final cubit = await configured(repository);
    expect(await cubit.fetchPreview(), true);
    expect(cubit.state.planIntegrity!.blockedCount, 1);
    expect(cubit.state.planIntegrity!.notApplicableCount, 1);
    expect(cubit.state.submissionBlockReason, contains('已阻止'));
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('new submit token is independently checked; missing plan cannot reuse old verification', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await configured(repository);
    expect(await cubit.fetchPreview(), true);
    repository.readPlan = (id, _) async => CopyJobItemPage(items: [item(0, state: CopyPlanState.unknown)], hasMore: false);
    expect(await cubit.submit(), false);
    expect(cubit.state.planIntegrity!.token, 'preview-2');
    expect(cubit.state.planIntegrity!.verified, false);
    expect(repository.createCalls, 0);
  });

  test('new filename requires another confirmation; token-only refresh then creates', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await configured(repository);
    await cubit.fetchPreview();
    repository.readPlan = (_, _) async => CopyJobItemPage(items: [item(0, filename: 'renamed(1).ARW')], hasMore: false);
    expect(await cubit.submit(), false);
    expect(cubit.state.planNotice, contains('计划已变化'));
    expect(repository.createCalls, 0);
    expect(await cubit.submit(), true);
    expect(repository.createdTokens, ['preview-3']);
  });

  test('new count and bytes require confirmation even when the refreshed plan is valid', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await configured(repository);
    await cubit.fetchPreview();
    repository.makePreview = (_) async => preview(files: 2, bytes: 200, logical: 2);
    repository.readPlan = (_, _) async => CopyJobItemPage(items: [item(0), item(1)], hasMore: false);
    expect(await cubit.submit(), false);
    expect(cubit.state.preview!.actualFileCount, 2);
    expect(cubit.state.planNotice, isNotNull);
    expect(repository.createCalls, 0);
  });

  test('cancel and retry while old page is pending cannot overwrite the new plan', () async {
    final repository = FakeCopyEnvironment();
    final oldPage = Completer<CopyJobItemPage>();
    repository.readPlan = (_, _) => oldPage.future;
    final cubit = await configured(repository);
    final old = cubit.fetchPreview();
    await Future<void>.delayed(Duration.zero);
    cubit.cancelPlanVerification();
    repository.readPlan = null;
    expect(await cubit.fetchPreview(), true);
    oldPage.complete(CopyJobItemPage(items: [item(0, state: CopyPlanState.unknown)], hasMore: false));
    expect(await old, false);
    expect(cubit.state.planIntegrity!.token, 'preview-2');
    expect(cubit.state.planIntegrity!.verified, true);
  });

  test('configuration change while reading items invalidates the plan and never POSTs', () async {
    final repository = FakeCopyEnvironment();
    final page = Completer<CopyJobItemPage>();
    repository.readPlan = (_, _) => page.future;
    final cubit = await configured(repository);
    final pending = cubit.fetchPreview();
    await Future<void>.delayed(Duration.zero);
    cubit.setConflictStrategy(ConflictStrategy.skip);
    page.complete(CopyJobItemPage(items: [item(0)], hasMore: false));
    expect(await pending, false);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('cancel submit verification before POST and retry safely', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await configured(repository);
    await cubit.fetchPreview();
    final pendingPage = Completer<CopyJobItemPage>();
    repository.readPlan = (_, _) => pendingPage.future;
    final submit = cubit.submit();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.checkingPlan, true);
    cubit.cancelPlanVerification();
    pendingPage.complete(CopyJobItemPage(items: [item(0)], hasMore: false));
    expect(await submit, false);
    expect(cubit.state.checkingPlan, false);
    expect(repository.createCalls, 0);
    repository.readPlan = null;
    expect(await cubit.fetchPreview(), true);
    expect(await cubit.submit(), true);
    expect(repository.createCalls, 1);
  });

  test('filtered_assets keeps the entire filter and verifies all backend matching rows', () async {
    final filter = const PhotoQuery(
      search: '鸟',
      species: 'bird-1',
      minScore: 3,
      minConfidence: .8,
      tags: ['tag'],
      keepState: 'keep',
      analysisState: 'completed',
      clarityState: 'sharp',
      recognitionState: 'recognized',
      recommendedOnly: true,
      groupId: 'g',
      sceneId: 's',
    ).toCopyFilterV1()!;
    final repository = FakeCopyEnvironment();
    repository.makePreview = (_) async => preview(files: 25, bytes: 2500, logical: 25);
    final cursors = <String?>[];
    repository.readPlan = (_, cursor) async {
      cursors.add(cursor);
      return CopyJobItemPage(items: [for (var i = cursor == null ? 0 : 20; i < (cursor == null ? 20 : 25); i++) item(i)], hasMore: cursor == null, nextCursor: cursor == null ? '20' : null);
    };
    final cubit = await configured(repository, scope: CopyScope.filteredAssets, filter: filter);
    expect(await cubit.fetchPreview(), true);
    expect(cubit.state.planIntegrity!.items.length, 25);
    expect(await cubit.submit(), true);
    expect(repository.drafts.every((draft) => draft.filter.toString() == filter.toString()), true);
    expect(repository.createdDraft!.filter, filter);
    expect(cursors, [null, '20', null, '20']);
  });

  testWidgets('summary uses five detail rows, two copy files and three skipped files', (tester) async {
    final repository = FakeCopyEnvironment();
    repository.makePreview = (_) async => preview(files: 2, bytes: 200, logical: 5);
    repository.readPlan = (_, _) async => CopyJobItemPage(
      items: [
        item(0),
        item(1),
        for (var i = 2; i < 5; i++) item(i, state: CopyPlanState.skipConflict),
      ],
      hasMore: false,
    );
    final cubit = await configured(repository, cleanup: false);
    await cubit.fetchPreview();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: CopyFinalConfirmationStep(state: cubit.state, onBack: () {}, onRefreshPreview: cubit.fetchPreview, onSubmit: cubit.submit),
        ),
      ),
    );
    expect(find.textContaining('5 张逻辑照片 · 2 个将复制文件'), findsOneWidget);
    expect(find.textContaining('5 条明细（2 个将复制 · 3 个将跳过'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('copy-preview-items-open')), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('查看预检明细（5 条）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('plan badges win over keep_both and cached verified rows need no extra request', (tester) async {
    final rows = [item(0, state: CopyPlanState.blocked, decision: 'keep_both'), item(1, state: CopyPlanState.notApplicable, decision: 'keep_both')];
    await tester.pumpWidget(
      MaterialApp(
        home: CopyPreviewItemsSheet(
          repository: Pages((_, _) async => throw StateError('must use snapshot')),
          previewToken: 'token',
          summaryFileCount: 0,
          verifiedPlan: CopyPlanIntegrity(CopyPlanIntegrityStatus.verified, token: 'token', items: rows),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已阻止'), findsOneWidget);
    expect(find.text('不适用'), findsOneWidget);
    expect(find.text('两份保留'), findsNWidgets(2));
    expect(find.text('将复制'), findsNothing);
  });
}
