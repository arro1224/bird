import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual Python HTTP: RC3 DTOs, export failures and >1000 event replay', () async {
    HttpOverrides.global = null;
    final base = Uri.parse(Platform.environment['BIRDBOX_CONTRACT_BASE']!);
    final http = HttpClient();
    final response = await (await http.getUrl(base.resolve('/local-fixture'))).close();
    final fixture = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    http.close();
    final client = ApiClient()..configure(base);
    final pair = await client.post(ApiEndpoints.devicePair, data: {'pairing_code': '123456', 'client_name': 'Dart HTTP contract check'}, idempotencyKey: 'dart-http-contract');
    client.setSession(accessToken: pair['access_token'] as String);
    final api = CopyApi(client);
    final normal = fixture['normal_job'] as String;
    final report = await api.jobReport(normal);
    expect(report.failedFiles, 0);
    expect(report.csvStatus, 'success');
    expect(report.embedDegradedCount, 1);
    expect(report.isPartialSuccess, isTrue);
    final failed = await api.jobReport(fixture['failed_export_job'] as String);
    expect(failed.failedFiles, 0);
    expect(failed.csvStatus, 'failed');
    expect(failed.isPartialSuccess, isTrue);
    final cubit = CopyJobDetailCubit(CopyRepositoryImpl(api), copyJobId: normal);
    await cubit.load();
    expect(cubit.state.error, isNull);
    expect(cubit.state.events.length, greaterThan(1000));
    expect(cubit.state.lastEventSeq, cubit.state.events.length);
    await cubit.close();
  }, skip: Platform.environment['BIRDBOX_CONTRACT_BASE'] == null ? 'Requires the separately started Python HTTP contract fixture.' : false);
}
