import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

enum RecognitionEntryPhase { notStarted, running, completed, interrupted, unknown }

/// Read-only entry facts. Choosing a mode never creates or changes a task.
class SmartFollowEntryDecision {
  const SmartFollowEntryDecision({
    required this.phase,
    this.capabilities = SmartFollowCapabilities.none,
    this.job,
    this.session,
    this.notice,
  });

  final RecognitionEntryPhase phase;
  final SmartFollowCapabilities capabilities;
  final BirdJobStatus? job;
  final SmartFollowSession? session;
  final String? notice;

  bool get canChooseFollow => capabilities.canShowEntry && session == null && (phase == RecognitionEntryPhase.notStarted || (phase == RecognitionEntryPhase.running && job?.state == BirdJobState.running));

  String get followLabel => phase == RecognitionEntryPhase.notStarted ? '识别并复制已识别照片' : '边识别边复制';

  String get snapshotLabel => switch (phase) {
    RecognitionEntryPhase.running => '仅复制当前已识别结果',
    RecognitionEntryPhase.interrupted => '复制当前已完成结果',
    _ => '复制已识别照片',
  };

  static SmartFollowEntryDecision resolve({
    required String batchId,
    required Iterable<BirdJobStatus> jobs,
    required SmartFollowCapabilities capabilities,
    SmartFollowSession? session,
    String? recognitionJobId,
  }) {
    final analyses = jobs.where((job) => job.type == BirdJobType.analysis).toList();
    if (recognitionJobId == null && analyses.any((job) => job.sourceProjectId?.trim().isNotEmpty != true)) {
      return const SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '部分识别任务的批次归属无法确认，请从具体任务进入。');
    }
    final candidates = analyses.where((job) => job.sourceProjectId?.trim() == batchId.trim()).toList();
    BirdJobStatus? selected;
    if (recognitionJobId != null) {
      selected = candidates.where((job) => job.id == recognitionJobId).firstOrNull;
      if (selected == null) return const SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '无法确认本批次的识别任务，请刷新后重试。');
    } else {
      final active = candidates.where((job) => const {BirdJobState.running, BirdJobState.queued, BirdJobState.paused}.contains(job.state)).toList();
      if (active.length > 1) return const SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '本批次有多个活动识别任务，请从具体任务进入。');
      if (active.length == 1) {
        selected = active.single;
      } else if (candidates.length == 1) {
        selected = candidates.single;
      } else if (candidates.isNotEmpty) {
        // Without a creation time, list order cannot establish the current run.
        if (candidates.any((job) => job.createdAt == null)) return const SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '无法确认最新一轮识别，请从具体任务进入。');
        candidates.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
        if (candidates[0].createdAt == candidates[1].createdAt) return const SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '无法确认最新一轮识别，请从具体任务进入。');
        selected = candidates.first;
      }
    }
    final phase = switch (selected?.state) {
      null => RecognitionEntryPhase.notStarted,
      BirdJobState.queued || BirdJobState.running || BirdJobState.paused => RecognitionEntryPhase.running,
      BirdJobState.completed => RecognitionEntryPhase.completed,
      BirdJobState.failed || BirdJobState.cancelled => RecognitionEntryPhase.interrupted,
      _ => RecognitionEntryPhase.unknown,
    };
    return SmartFollowEntryDecision(
      phase: phase,
      capabilities: capabilities,
      job: selected,
      session: session?.recognitionJobId == selected?.id ? session : null,
      notice: switch (selected?.state) {
        BirdJobState.paused => '识别已暂停，请先回到识别任务继续处理。',
        BirdJobState.queued => '识别正在等待开始，请在开始处理后开启跟随。',
        _ => null,
      },
    );
  }
}

/// Existing REST reads only. Exhaust pages before treating absence as not started.
class SmartFollowEntryReader {
  const SmartFollowEntryReader({
    required this.batchId,
    required this.readPage,
    required this.readCapabilities,
    required this.readSession,
    required this.isCurrent,
    this.recognitionJobId,
  });

  final String batchId;
  final String? recognitionJobId;
  final Future<JobPage> Function(String? cursor) readPage;
  final Future<SmartFollowCapabilities> Function() readCapabilities;
  final Future<SmartFollowSession?> Function(String jobId) readSession;
  final bool Function() isCurrent;

  Future<SmartFollowEntryDecision> read() async {
    const unavailable = SmartFollowEntryDecision(phase: RecognitionEntryPhase.unknown, notice: '识别状态暂时无法确认，请检查连接后重新检测。');
    try {
      if (!isCurrent() || batchId.trim().isEmpty) return unavailable;
      SmartFollowCapabilities capabilities;
      try {
        capabilities = await readCapabilities();
      } catch (_) {
        capabilities = SmartFollowCapabilities.none;
      }
      if (!isCurrent()) return unavailable;
      final jobs = <String, BirdJobStatus>{};
      final cursors = <String>{};
      String? cursor;
      for (var pageIndex = 0; pageIndex < 200; pageIndex++) {
        final page = await readPage(cursor);
        if (!isCurrent()) return unavailable;
        for (final job in page.items) {
          final previous = jobs[job.id];
          if (previous != null && previous != job) return unavailable;
          jobs[job.id] = job;
        }
        if (page.hasMore) {
          final next = page.nextCursor;
          if (page.items.isEmpty || next == null || next.trim().isEmpty || !cursors.add(next)) return unavailable;
          cursor = next;
          continue;
        }
        if (page.nextCursor != null) return unavailable;
        final decision = SmartFollowEntryDecision.resolve(batchId: batchId, jobs: jobs.values, capabilities: capabilities, recognitionJobId: recognitionJobId);
        final job = decision.job;
        if (!capabilities.canShowEntry || job == null) return decision;
        // Even a finished recognition run may still own a draining session.
        final session = await readSession(job.id);
        if (!isCurrent()) return unavailable;
        if (session != null && session.recognitionJobId != job.id) return unavailable;
        return SmartFollowEntryDecision.resolve(batchId: batchId, jobs: jobs.values, capabilities: capabilities, recognitionJobId: recognitionJobId, session: session);
      }
    } catch (_) {
      return unavailable;
    }
    return unavailable;
  }
}
