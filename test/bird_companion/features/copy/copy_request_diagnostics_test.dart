import 'dart:convert';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_connection_diagnostic_store.dart';
import 'package:aves/bird_companion/features/copy/data/copy_request_diagnostics.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只输出诊断元数据，不输出响应、路径或授权凭据；保留请求关联 ID', () async {
    final records = <Map<String, Object?>>[];
    final diagnostics = CopyRequestDiagnostics(records.add);
    final dio = DioException(
      requestOptions: RequestOptions(path: 'http://box/private?token=secret-token', headers: {'Authorization': 'Bearer secret-token'}),
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: RequestOptions(),
        statusCode: 503,
        data: {
          'request_id': 'req-1',
          'error': {'code': 'COPY_TEMPORARY', 'message': '/private/file.jpg secret-token'},
        },
      ),
    );
    await expectLater(diagnostics.request('detail', 'job-1', () async => throw ApiException.fromDio(dio), deviceId: 'box-a'), throwsA(isA<ApiException>()));
    expect(records.single['http_status'], 503);
    expect(records.single['request_id'], 'req-1');
    expect(records.single['error_code'], 'COPY_TEMPORARY');
    expect(records.single['elapsed_ms'], isNonNegative);
    expect(jsonEncode(records), isNot(contains('secret-token')));
    expect(jsonEncode(records), isNot(contains('file.jpg')));
    expect(jsonEncode(records), isNot(contains('http://')));
  });

  test('诊断 sink 抛错不影响请求成功或原始异常', () async {
    final diagnostics = CopyRequestDiagnostics((_) => throw StateError('journal failed'));
    expect(await diagnostics.request('report', 'job-1', () async => 42), 42);
    await expectLater(diagnostics.request('events', 'job-1', () async => throw const FormatException('private payload')), throwsFormatException);
  });

  test('复制诊断进入已有可导出的 journal，并受条数/字节上限约束', () async {
    final journal = BleConnectionDiagnosticStore(_Disk(), maximumEvents: 3, maximumBytes: 4096);
    addTearDown(journal.dispose);
    final diagnostics = CopyRequestDiagnostics.forJournal(journal);
    for (var i = 0; i < 10; i++) {
      await diagnostics.request('detail', 'job-$i', () async => i, deviceId: 'box-a');
    }
    await journal.flush();
    expect(journal.readAll().length, lessThanOrEqualTo(3));
    expect(journal.exportJson(), contains('copy_request_result'));
    expect(journal.exportJson(), contains('app_copy'));
    expect(journal.exportJson(), contains('elapsed_ms'));
  });
}

class _Disk implements DiagnosticStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}
