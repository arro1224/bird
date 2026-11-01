import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter_test/flutter_test.dart';

const enabled = SmartFollowCapabilities(incrementalRecognition: true, copy: SmartFollowCapability(available: true), metadataUpdate: false);

BirdJobStatus analysis(BirdJobState state, {String id = 'rec-1', String batch = 'batch-1', DateTime? createdAt}) => BirdJobStatus(id: id, type: BirdJobType.analysis, state: state, sourceProjectId: batch, createdAt: createdAt);

SmartFollowSession session({String job = 'rec-1'}) => SmartFollowSession(
  sessionId: 'sf-1',
  recognitionJobId: job,
  state: SmartFollowState.following,
  stateVersion: 1,
  recognizedCount: 1,
  eligibleCount: 1,
  pendingCount: 1,
  assignedCount: 0,
  copiedAssetCount: 0,
  copiedFileCount: 0,
  failedAssetCount: 0,
  childJobCount: 0,
  allowedActions: const [],
  metadataUpdateAvailable: false,
);

void main() {
  SmartFollowEntryDecision resolve(List<BirdJobStatus> jobs, {SmartFollowCapabilities caps = enabled, SmartFollowSession? existing, String? jobId}) =>
      SmartFollowEntryDecision.resolve(batchId: 'batch-1', jobs: jobs, capabilities: caps, session: existing, recognitionJobId: jobId);

  test('not started, running, completed and interrupted remain distinct', () {
    expect(resolve([]).phase, RecognitionEntryPhase.notStarted);
    expect(resolve([]).followLabel, '识别并复制已识别照片');
    for (final state in [BirdJobState.queued, BirdJobState.running, BirdJobState.paused]) {
      expect(resolve([analysis(state)]).phase, RecognitionEntryPhase.running);
      expect(resolve([analysis(state)]).canChooseFollow, state == BirdJobState.running);
    }
    expect(resolve([analysis(BirdJobState.completed)]).canChooseFollow, isFalse);
    for (final state in [BirdJobState.failed, BirdJobState.cancelled]) {
      expect(resolve([analysis(state)]).phase, RecognitionEntryPhase.interrupted);
      expect(resolve([analysis(state)]).canChooseFollow, isFalse);
    }
  });

  test('unrelated batch and import jobs cannot determine recognition state', () {
    expect(resolve([const BirdJobStatus(id: 'unassigned', type: BirdJobType.analysis, state: BirdJobState.running)]).phase, RecognitionEntryPhase.unknown);
    expect(resolve([analysis(BirdJobState.running, batch: 'other'), const BirdJobStatus(id: 'import', type: BirdJobType.import, state: BirdJobState.running, sourceProjectId: 'batch-1')]).phase, RecognitionEntryPhase.notStarted);
  });

  test('both incremental and follow capabilities are required', () {
    for (final caps in [
      SmartFollowCapabilities.none,
      const SmartFollowCapabilities(incrementalRecognition: false, copy: SmartFollowCapability(available: true), metadataUpdate: false),
      const SmartFollowCapabilities(incrementalRecognition: true, copy: SmartFollowCapability(available: false), metadataUpdate: false),
    ]) {
      expect(resolve([analysis(BirdJobState.running)], caps: caps).canChooseFollow, isFalse);
    }
  });

  test('existing session is exposed rather than offering another creation', () {
    final decision = resolve([analysis(BirdJobState.running)], existing: session());
    expect(decision.session!.sessionId, 'sf-1');
    expect(decision.canChooseFollow, isFalse);
    expect(resolve([analysis(BirdJobState.running)], existing: session(job: 'other')).session, isNull);
  });

  test('active job wins; terminal jobs need trustworthy chronology', () {
    expect(resolve([analysis(BirdJobState.completed, id: 'old'), analysis(BirdJobState.running)]).job!.id, 'rec-1');
    expect(resolve([analysis(BirdJobState.completed, id: 'old'), analysis(BirdJobState.failed)]).phase, RecognitionEntryPhase.unknown);
    expect(resolve([analysis(BirdJobState.completed, id: 'old', createdAt: DateTime.utc(2026, 1)), analysis(BirdJobState.failed, createdAt: DateTime.utc(2026, 2))]).phase, RecognitionEntryPhase.interrupted);
    expect(resolve([analysis(BirdJobState.running), analysis(BirdJobState.running, id: 'other')]).phase, RecognitionEntryPhase.unknown);
  });

  test('specific job entry cannot bind a job from another batch', () {
    expect(resolve([analysis(BirdJobState.running, batch: 'other')], jobId: 'rec-1').phase, RecognitionEntryPhase.unknown);
    expect(resolve([analysis(BirdJobState.completed, id: 'old'), analysis(BirdJobState.running)], jobId: 'old').phase, RecognitionEntryPhase.completed);
  });

  test('all job pages are read before deciding whether recognition has started', () async {
    final cursors = <String?>[];
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => enabled,
      readSession: (_) async => null,
      readPage: (cursor) async {
        cursors.add(cursor);
        return cursor == null
            ? JobPage(
                items: [analysis(BirdJobState.completed, batch: 'other', id: 'other-rec')],
                hasMore: true,
                nextCursor: 'next',
              )
            : JobPage(items: [analysis(BirdJobState.running)], hasMore: false);
      },
    );
    expect((await reader.read()).phase, RecognitionEntryPhase.running);
    expect(cursors, [null, 'next']);
  });

  test('partial or non-progressing pagination cannot become not-started', () async {
    for (final page in [
      const JobPage(items: [], hasMore: true),
      JobPage(
        items: [analysis(BirdJobState.completed, batch: 'other')],
        hasMore: true,
        nextCursor: 'repeat',
      ),
    ]) {
      final reader = SmartFollowEntryReader(batchId: 'batch-1', isCurrent: () => true, readCapabilities: () async => enabled, readSession: (_) async => null, readPage: (_) async => page);
      expect((await reader.read()).phase, RecognitionEntryPhase.unknown);
    }
  });

  test('capability 404 disables follow but preserves snapshot recognition facts', () async {
    var sessionReads = 0;
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => throw const ApiException(statusCode: 404, message: 'not found'),
      readSession: (_) async {
        sessionReads++;
        return null;
      },
      readPage: (_) async => JobPage(items: [analysis(BirdJobState.running)], hasMore: false),
    );
    final decision = await reader.read();
    expect(decision.phase, RecognitionEntryPhase.running);
    expect(decision.canChooseFollow, isFalse);
    expect(sessionReads, 0);
  });

  test('existing draining session remains discoverable after recognition ends', () async {
    final reader = SmartFollowEntryReader(
      batchId: 'batch-1',
      isCurrent: () => true,
      readCapabilities: () async => enabled,
      readSession: (_) async => session(),
      readPage: (_) async => JobPage(items: [analysis(BirdJobState.completed)], hasMore: false),
    );
    expect((await reader.read()).session!.sessionId, 'sf-1');
  });

  test('late response after changing devices cannot authorize follow', () async {
    var current = true;
    final page = Completer<JobPage>();
    final reader = SmartFollowEntryReader(batchId: 'batch-1', isCurrent: () => current, readCapabilities: () async => enabled, readSession: (_) async => session(), readPage: (_) => page.future);
    final pending = reader.read();
    await Future<void>.delayed(Duration.zero);
    current = false;
    page.complete(JobPage(items: [analysis(BirdJobState.running)], hasMore: false));
    final decision = await pending;
    expect(decision.phase, RecognitionEntryPhase.unknown);
    expect(decision.canChooseFollow, isFalse);
    expect(decision.session, isNull);
  });
}
