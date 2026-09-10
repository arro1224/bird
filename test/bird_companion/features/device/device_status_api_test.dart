import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device task control sends the current job version', () async {
    final client = _RecordingApiClient();

    await DeviceStatusApi(client).controlJob(
      jobId: 'job-7',
      action: 'pause',
      version: 4,
    );

    expect(
      client.path,
      ApiEndpoints.taskControl.replaceFirst('{jobId}', 'job-7'),
    );
    expect(client.data, {'action': 'pause', 'version': 4});
  });
}

class _RecordingApiClient extends ApiClient {
  String? path;
  Object? data;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.data = data;
    return const {};
  }
}
