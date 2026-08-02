import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BirdJobStatus round-trips the complete v1 fixture', () {
    final fixture = <String, dynamic>{
      'job_id': 'job-analysis-7',
      'job_type': 'analysis',
      'job_state': 'queued',
      'workflow_stage': 'analyzing',
      'source_project_id': 'project-7',
      'source_project_name': '河岸翠鸟',
      'progress': .25,
      'total_count': 100,
      'finished_count': 25,
      'failed_count': 2,
      'skipped_count': 1,
      'current_file': 'DSC_0026.NEF',
      'speed_bytes_per_second': 1048576,
      'estimated_remaining_seconds': 180,
      'available_actions': ['cancel'],
      'created_at': '2026-07-29T08:00:00Z',
      'updated_at': '2026-07-29T08:01:00Z',
    };

    final job = BirdJobStatus.fromJson(fixture);
    final roundTrip = BirdJobStatus.fromJson(job.toJson());

    expect(job.state, BirdJobState.queued);
    expect(job.sourceProjectId, 'project-7');
    expect(job.workflowStage, 'analyzing');
    expect(job.skippedCount, 1);
    expect(job.estimatedRemainingSeconds, 180);
    expect(job.availableActions, ['cancel']);
    expect(roundTrip, job);
  });

  test('rejects empty ids, 0-100 progress, negative bytes and bad time', () {
    Map<String, dynamic> valid() => {
      'job_id': 'job-1',
      'job_type': 'copy',
      'job_state': 'running',
      'progress': .5,
    };

    expect(
      () => BirdJobStatus.fromJson({...valid(), 'job_id': ''}),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
    expect(
      () => BirdJobStatus.fromJson({...valid(), 'progress': 50}),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
    expect(
      () => BirdJobStatus.fromJson({
        ...valid(),
        'speed_bytes_per_second': -1,
      }),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
    expect(
      () => BirdJobStatus.fromJson({
        ...valid(),
        'created_at': 'not-a-time',
      }),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
  });
}
