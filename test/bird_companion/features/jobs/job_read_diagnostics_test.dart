import 'dart:convert';

import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/jobs/data/job_api.dart';
import 'package:aves/bird_companion/features/jobs/data/job_read_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadClient extends ApiClient {
  Map<String, dynamic> raw = const BirdJobStatus(id: 'job-test', type: BirdJobType.analysis, state: BirdJobState.running, sourceProjectId: 'batch-test').toJson();
  Object? error;
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    if (error != null) throw error!;
    return raw;
  }
}

void main() {
  test('detail diagnostic contains task, batch, endpoint and HTTP success, not response payload', () async {
    final events = <Map<String, Object?>>[];
    final client = ReadClient()..raw['secret'] = 'Bearer secret-test';
    await JobApi(client, diagnostics: JobReadDiagnostics(events.add)).detail('job-test');
    expect(events.single['job_id'], 'job-test');
    expect(events.single['batch_id'], 'batch-test');
    expect(events.single['endpoint'], '/api/v1/jobs/job-test');
    expect(events.single['http_status'], 200);
    expect(jsonEncode(events), isNot(contains('secret-test')));
  });
  test('wrong task response is rejected and logged as parsing failure after HTTP 200', () async {
    final events = <Map<String, Object?>>[];
    final client = ReadClient()..raw['job_id'] = 'other-job';
    await expectLater(JobApi(client, diagnostics: JobReadDiagnostics(events.add)).detail('job-test'), throwsA(isA<ProtocolCompatibilityException>()));
    expect(events.single['http_status'], 200);
    expect(events.single['parse_field'], 'job_id');
    expect(events.single['outcome'], 'failed');
  });
  test('HTTP errors retain status/code without exception secrets', () async {
    final events = <Map<String, Object?>>[];
    final client = ReadClient()..error = const ApiException(message: 'Bearer hidden-token /home/private', statusCode: 404, code: 'JOB_NOT_FOUND');
    await expectLater(JobApi(client, diagnostics: JobReadDiagnostics(events.add)).detail('job-test'), throwsA(isA<ApiException>()));
    expect(events.single['http_status'], 404);
    expect(events.single['error_code'], 'JOB_NOT_FOUND');
    expect(jsonEncode(events), isNot(contains('hidden-token')));
    expect(jsonEncode(events), isNot(contains('/home/private')));
  });
  test('diagnostic sink failure never prevents opening a valid task', () async {
    final job = await JobApi(ReadClient(), diagnostics: JobReadDiagnostics((_) => throw StateError('journal failure'))).detail('job-test');
    expect(job.id, 'job-test');
  });
  test('task errors distinguish missing, conflict, parse and authentication', () {
    expect(UserMessageMapper.fromTaskReadError(const ApiException(message: '', statusCode: 404)).title, '任务不存在');
    expect(UserMessageMapper.fromTaskReadError(const ApiException(message: '', statusCode: 409)).title, '任务状态已变化');
    expect(UserMessageMapper.fromTaskReadError(const ProtocolCompatibilityException('progress', 'invalid')).title, '任务数据无法解析');
    expect(UserMessageMapper.fromTaskReadError(const ApiException(message: '', statusCode: 401)).message, isNot(contains('任务不存在')));
  });
}
