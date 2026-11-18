import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/run/smart_follow_stage.dart';
import 'package:flutter_test/flutter_test.dart';

// Shape taken from the 2026-11-11 installed API contract_samples.json.
// These are contract/parser tests, NOT proof of running the deployed Python code.
Map<String, dynamic> envelope({Map<String, dynamic>? summary}) => {
  'session': {
    'id': 'follow-example', 'job_id': 'analysis-example',
    'state': 'completed', 'state_version': 4, 'event_seq': 9,
    'execution_mode': 'continuous_queue', 'allowed_actions': ['retry'],
  },
  'counts': {'copied': 2}, 'child_jobs': <dynamic>[],
  'summary': summary ?? {
    'session_id': 'follow-example', 'recognition_job_id': 'analysis-example',
    'execution_mode': 'continuous_queue', 'phase': 'completed',
    'recognition_processed': 2, 'recognition_total': 2,
    'eligible_asset_count': 2, 'planned_file_count': 2,
    'asset_identity': 'indexed_file_id', 'copied_bytes': 61260,
    'file_counts': {'copied': 2, 'queued': 0, 'blocked': 0},
  },
};

void main() {
  test('legacy partial session shows 65 eligible, 44 copied, 15 skipped and 6 unprocessed', () {
    final legacy = SmartFollowSession.fromJson({
      'session': {'id': 's-old', 'job_id': 'j-old', 'state': 'completed_partial'},
      'recognition_task': {'job_id': 'j-old', 'last_event_seq': 182},
      'summary': {
        'execution_mode': 'legacy_microbatch',
        'eligible_asset_count': 65,
        'file_counts': {'copied': 44, 'skipped_conflict': 15, 'blocked': 6},
        'legacy_unprocessed_files': 6,
      },
    });
    expect(legacy.recognizedCount, 182);
    expect(legacy.eligibleCount, 65);
    expect(legacy.copiedFileCount, 44);
    expect(legacy.raw['skipped_file_count'], 15);
    expect(legacy.raw['legacy_unprocessed_files'], 6);
    expect(legacy.displayCount('copied_asset_count'), '未知');
    final child = SmartFollowChildJob.fromJson({
      'copy_job_id': 'old-child', 'state': 'completed_with_errors', 'batch_number': 1,
      'file_count': 65, 'stats': {'total_files': 65, 'copied_files': 44, 'skipped_files': 15},
    });
    expect([child.index, child.fileCount, child.copiedFileCount, child.skippedFileCount], [1, 65, 44, 15]);
    expect(child.displayCount('failed', child.failedFileCount), '未知');
  });

  test('continuous queue phases keep waiting and pause completion distinct', () {
    for (final phase in ['waiting_for_writer', 'awaiting_results', 'pause_requested', 'waiting_for_storage']) {
      final json = envelope(summary: {'execution_mode': 'continuous_queue', 'phase': phase});
      (json['session'] as Map)['state'] = 'following';
      final stage = resolveSmartFollowStage(session: SmartFollowSession.fromJson(json));
      expect(stage.id, phase);
      expect(stage.isWaiting, isTrue);
    }
  });
  test('installed envelope preserves identity, summary, actions and zero child history', () {
    final session = SmartFollowSession.fromJson(envelope());
    expect(session.sessionId, 'follow-example');
    expect(session.recognitionJobId, 'analysis-example');
    expect(session.stateVersion, 4);
    expect(session.isContinuous, isTrue);
    expect(session.summary!.recognitionProcessed, 2);
    expect(session.summary!.plannedFileCount, 2);
    expect(session.summary!.fileCounts['copied'], 2);
    expect(session.summary!.copiedBytes, 61260);
    expect(session.recognizedCount, 2);
    expect(session.eligibleCount, 2);
    expect(session.copiedFileCount, 2);
    expect(session.supports(SmartFollowAction.retry), isTrue);
    expect(session.canShowCompletion, isTrue);
  });
  test('HTTP data wrapper and preparing summary keep absent counters unknown', () {
    final session = SmartFollowSession.fromJson({'data': envelope(summary: {
      'session_id': 'follow-example', 'execution_mode': 'continuous_queue', 'phase': 'created',
    })});
    expect(session.summary!.recognitionTotal, isNull);
    expect(session.summary!.plannedFileCount, isNull);
    expect(session.summary!.fileCounts, isEmpty);
    expect(session.summary!.phase, 'created');
  });
  test('outstanding blocked/queued files cannot establish complete success', () {
    for (final state in ['queued', 'copying', 'retry_wait', 'blocked']) {
      final session = SmartFollowSession.fromJson(envelope(summary: {
        'execution_mode': 'continuous_queue', 'file_counts': {state: 1},
      }));
      expect(session.canShowCompletion, isFalse, reason: state);
    }
  });
  test('negative summary file counts are protocol errors, not zero', () {
    expect(() => SmartFollowSession.fromJson(envelope(summary: {
      'file_counts': {'failed': -1},
    })), throwsA(isA<ProtocolCompatibilityException>()));
  });
  test('summary for a different session or recognition job is rejected', () {
    for (final key in ['session_id', 'recognition_job_id']) {
      expect(() => SmartFollowSession.fromJson(envelope(summary: {key: 'another-task'})), throwsA(isA<ProtocolCompatibilityException>()));
    }
  });
  test('startup failure remains failure even before a summary is available', () {
    final session = SmartFollowSession.fromJson({
      'session_id': 'failed-start', 'recognition_job_id': 'rec-start',
      'state': 'failed', 'execution_mode': 'continuous_queue', 'error_message': '目标盘暂不可用',
    });
    expect(resolveSmartFollowStage(session: session).tone, SmartFollowStageTone.failure);
  });
  test('legacy flat DTO remains supported without inventing continuous capability', () {
    final session = SmartFollowSession.fromJson({
      'session_id': 'legacy', 'recognition_job_id': 'old-job',
      'state': 'following', 'state_version': 1, 'eligible_count': 3,
    });
    expect(session.isContinuous, isFalse);
    expect(session.eligibleCount, 3);
    expect(session.summary, isNull);
    expect(SmartFollowCapability.fromJson({'available': true}).continuousQueueAvailable, isFalse);
    final capability = SmartFollowCapability.fromJson({
      'available': true, 'execution_mode': 'continuous_queue',
      'continuous_queue_available': true, 'continuous_contract_version': 'smart-follow-continuous-v2.0',
    });
    expect(capability.continuousQueueAvailable, isTrue);
    expect(capability.continuousContractVersion, 'smart-follow-continuous-v2.0');
  });
}
