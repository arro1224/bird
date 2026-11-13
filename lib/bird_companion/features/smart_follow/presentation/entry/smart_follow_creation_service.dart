import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_create_requests.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';

class SmartFollowCreationPending implements Exception {
  const SmartFollowCreationPending();
  @override
  String toString() => '上次创建结果仍待确认。请查询原请求，或保持原配置用同一次请求重试；不要重新创建任务。';
}

class SmartFollowConfirmationRequired extends StateError {
  SmartFollowConfirmationRequired(super.message);
}

/// Durable App intent, not a local copy queue. All discovery uses existing REST
/// jobs/events/session reads. An unresolved intent is never replaced by a new key.
class SmartFollowCreationService {
  SmartFollowCreationService({required this.jobs, required this.follows, required this.cache, required this.deviceId, required this.contextKey});
  final JobRepository jobs;
  final SmartFollowRepository follows;
  final LocalCache cache;
  final String? Function() deviceId, contextKey;
  final Map<String, Future<SmartFollowSession>> _inFlight = {};

  String _slot(String batch) => 'smart-follow-create:${deviceId()}:$batch';
  Map<String, dynamic>? _record(String batch) {
    final raw = cache.read<Map>(_slot(batch));
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  bool hasPending(String batch) => _inFlight.containsKey(_slot(batch)) || _record(batch)?['resolved'] == false;
  bool hasCreationRecord(String batch) => _record(batch) != null;
  bool hasStaged(String batch) => cache.read<Map>('smart-follow-staged:${deviceId()}:$batch') != null;

  Future<void> discardStaged(String batch) async {
    if (hasPending(batch)) throw const SmartFollowCreationPending();
    await cache.remove('smart-follow-staged:${deviceId()}:$batch');
  }

  void _check(String? context) {
    if (context == null || contextKey() != context) throw SmartFollowConfirmationRequired('盒子连接已变化，请返回原盒子查询任务。');
  }

  Future<void> stageForBatch(String batch, SmartFollowConfiguredIntent intent) async {
    _check(intent.contextKey);
    await cache.write('smart-follow-staged:${deviceId()}:$batch', {...intent.forBatch(batch).toLocalJson(), 'auto_attempted': false});
  }

  Future<SmartFollowSession> startStaged(String batch, SmartFollowConfigurationReader reader) async {
    final raw = cache.read<Map>('smart-follow-staged:${deviceId()}:$batch');
    if (raw == null) throw SmartFollowConfirmationRequired('请重新确认本批次的复制配置。');
    if (raw['auto_attempted'] == true) {
      if (hasPending(batch)) return recover(batch);
      throw SmartFollowConfirmationRequired('导入已完成，请从识别入口重新核对设备与跟随复制策略。');
    }
    await cache.write('smart-follow-staged:${deviceId()}:$batch', {...raw, 'auto_attempted': true});
    return start(SmartFollowConfiguredIntent.fromLocalJson(Map<String, dynamic>.from(raw)), reader);
  }

  Future<SmartFollowSession> start(SmartFollowConfiguredIntent intent, SmartFollowConfigurationReader reader) {
    final batch = intent.batchId;
    if (batch == null || batch.trim().isEmpty) throw SmartFollowConfirmationRequired('导入完成后才能创建本轮识别与复制。');
    final slot = _slot(batch);
    return _inFlight[slot] ??= _start(intent, reader).whenComplete(() {
      _inFlight.remove(slot);
    });
  }

  Future<SmartFollowSession> recover(String batch) async {
    final context = contextKey();
    _check(context);
    final record = _record(batch);
    if (record == null) throw SmartFollowConfirmationRequired('没有待查询的创建请求。');
    final result = await _recover(batch, record, context!);
    if (result == null) throw const SmartFollowCreationPending();
    return result;
  }

  Future<SmartFollowSession> _start(SmartFollowConfiguredIntent intent, SmartFollowConfigurationReader reader) async {
    final batch = intent.batchId!, context = contextKey();
    _check(context);
    var record = _record(batch);
    if (record != null) {
      if (record['resolved'] == true && (record['created_job'] ?? record['job']) != intent.recognitionJobId && intent.recognitionJobId != null) {
        record = null; // Explicitly entered a different recognition round.
      } else {
        final recovered = await _recover(batch, record, context!);
        if (recovered != null) return recovered;
        if (jsonEncode(record['request']) != jsonEncode(intent.request.toJson()) || record['job'] != intent.recognitionJobId || (record['source_media_id'] != null && record['source_media_id'] != intent.sourceMediaId)) {
          throw const SmartFollowCreationPending();
        }
      }
    }
    _check(context);
    if (intent.contextKey != context ||
        reader.contextKey != context ||
        reader.batchId != batch ||
        intent.request.eligibilityMode != SmartFollowContract.eligibilityMode ||
        !reader.isCurrent() ||
        !DateTime.now().isBefore(intent.sourceBindingExpiresAt)) {
      throw SmartFollowConfirmationRequired('复制确认已失效，请重新检测并确认配置。');
    }
    final validation = SmartFollowConfigurationController(
      reader,
      expectedRecognitionJobId: intent.recognitionJobId,
      expectedRecognitionPhase: intent.recognitionJobId == null ? RecognitionEntryPhase.notStarted : RecognitionEntryPhase.running,
    );
    try {
      if (!await validation.refresh()) throw SmartFollowConfirmationRequired('设备状态无法确认，请重新检测。');
      _check(context);
      final data = validation.snapshot!;
      final existing = data.entry.session;
      if (existing != null && existing.recognitionJobId == intent.recognitionJobId) return existing;
      validation.selectTarget(intent.request.targetMediaId);
      validation.selectPairPolicy(PairPolicy.fromWire(intent.request.pairPolicy));
      validation.selectConflict(ConflictStrategy.fromWire(intent.request.conflictStrategy));
      validation.setReviewExport(intent.request.reviewExportEnabled);
      final reason = validation.blockReason;
      if (reason != null) throw SmartFollowConfirmationRequired(reason);
      final target = validation.target!;
      if (data.binding.sourceMediaId != intent.sourceMediaId ||
          data.preferences.version != intent.preferencesVersion ||
          target.identityConfidence != intent.targetIdentityConfidence ||
          target.capacityBytes != intent.targetCapacityBytes ||
          target.freeBytes != intent.targetFreeBytes ||
          validation.reviewExportEnabled != intent.request.reviewExportEnabled ||
          validation.snapshot!.entry.capabilities.copy.continuousQueueAvailable != intent.request.continuousQueue) {
        throw SmartFollowConfirmationRequired('设备或策略已变化，请重新核对并确认配置。');
      }
    } finally {
      validation.dispose();
    }
    if (record == null) {
      final baseline = await _batchJobs(batch, context!);
      if (intent.recognitionJobId == null && baseline.isNotEmpty) throw SmartFollowConfirmationRequired('本批次已有识别任务，请刷新入口后选择原任务。');
      record = {
        'resolved': false,
        'request': intent.request.toJson(),
        'source_media_id': intent.sourceMediaId,
        'job': intent.recognitionJobId,
        'key': intent.recognitionJobId == null ? 'sf-atomic-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}' : 'follow-start-${intent.recognitionJobId}',
        'baseline': baseline.map((job) => job.id).toList(),
        'sent': false,
      };
    }
    _check(context);
    if (!reader.isCurrent()) throw SmartFollowConfirmationRequired('配置页面已离开，请重新确认后提交。');
    final slot = _slot(batch);
    record['sent'] = true;
    await cache.write(slot, Map<String, dynamic>.from(record));
    _check(context);
    if (!reader.isCurrent()) throw SmartFollowConfirmationRequired('配置页面已离开，请查询原请求后重试。');
    try {
      SmartFollowSession result;
      if (intent.recognitionJobId != null) {
        result = await follows.startOnRecognitionJob(intent.recognitionJobId!, intent.request);
      } else {
        final job = await jobs.createAnalysis(batch, AnalysisJobRequest(smartFollow: intent.request.toJson(), idempotencyKey: record['key'] as String));
        _check(context);
        _ownedJob(job, batch);
        record['created_job'] = job.id;
        record['session'] = job.smartFollowSessionId;
        await cache.write(slot, Map<String, dynamic>.from(record));
        result = await _recover(batch, record, context!) ?? (throw const SmartFollowCreationPending());
      }
      _check(context);
      if (intent.recognitionJobId != null && result.recognitionJobId != intent.recognitionJobId) throw const SmartFollowCreationPending();
      await _resolved(batch, record, result, context!);
      return result;
    } catch (error) {
      _check(context);
      if (error is ApiException && error.statusCode != null && error.statusCode! >= 400 && error.statusCode! < 500 && !const {408, 409, 429}.contains(error.statusCode)) {
        await cache.remove(slot); // Definite rejection, no new task was accepted.
        rethrow;
      }
      final recovered = await _recover(batch, record, context!);
      if (recovered != null) return recovered;
      throw const SmartFollowCreationPending();
    }
  }

  void _ownedJob(BirdJobStatus job, String batch) {
    if (job.id.trim().isEmpty || job.type != BirdJobType.analysis || job.sourceProjectId != batch) throw const SmartFollowCreationPending();
  }

  Future<List<BirdJobStatus>> _batchJobs(String batch, String context) async {
    final result = <String, BirdJobStatus>{}, cursors = <String>{};
    String? cursor;
    for (var index = 0; index < 200; index++) {
      _check(context);
      final page = await jobs.page(cursor: cursor, type: 'analysis');
      _check(context);
      for (final job in page.items.where((job) => job.type == BirdJobType.analysis)) {
        if (job.sourceProjectId == null) throw const SmartFollowCreationPending();
        if (job.sourceProjectId == batch) result[job.id] = job;
      }
      if (!page.hasMore) return result.values.toList();
      final next = page.nextCursor;
      if (next == null || page.items.isEmpty || !cursors.add(next)) throw const SmartFollowCreationPending();
      cursor = next;
    }
    throw const SmartFollowCreationPending();
  }

  Future<SmartFollowSession?> _recover(String batch, Map<String, dynamic> record, String context) async {
    _check(context);
    try {
      String? jobId = (record['created_job'] ?? record['job']) as String?;
      BirdJobStatus? job;
      if (jobId == null) {
        final baseline = (record['baseline'] as List).cast<String>().toSet();
        final candidates = (await _batchJobs(batch, context)).where((job) => !baseline.contains(job.id)).toList();
        if (candidates.length > 1) throw const SmartFollowCreationPending();
        job = candidates.singleOrNull;
        if (job == null) return null;
        jobId = job.id;
      }
      job ??= await jobs.detail(jobId);
      _check(context);
      _ownedJob(job, batch);
      final sessionId = (record['session'] as String?) ?? job.smartFollowSessionId;
      final session = sessionId == null ? await follows.refreshForJob(jobId) : await follows.refresh(sessionId);
      _check(context);
      if (session == null) {
        if (record['job'] == null) throw const SmartFollowCreationPending();
        return null;
      }
      if (session.recognitionJobId != jobId) throw const SmartFollowCreationPending();
      if (record['job'] == null && session.targetMediaId != null && session.targetMediaId != (record['request'] as Map)['target_media_id']) throw const SmartFollowCreationPending();
      await _resolved(batch, record, session, context);
      return session;
    } on SmartFollowCreationPending {
      rethrow;
    } catch (_) {
      _check(context);
      throw const SmartFollowCreationPending();
    }
  }

  Future<void> _resolved(String batch, Map<String, dynamic> record, SmartFollowSession session, String context) async {
    _check(context);
    record.addAll({'session': session.sessionId, 'created_job': session.recognitionJobId, 'resolved': true});
    await cache.write(_slot(batch), Map<String, dynamic>.from(record));
    await cache.remove('smart-follow-staged:${deviceId()}:$batch');
  }
}
