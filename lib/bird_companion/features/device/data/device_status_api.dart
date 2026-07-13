import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_endpoints.dart';

class DeviceStatusApi {
  DeviceStatusApi(this._client);

  final ApiClient _client;

  Future<DeviceStatus> fetchStatus() async {
    final payload = await _client.get(ApiEndpoints.deviceStatus);
    return DeviceStatus.fromJson(payload, fallbackBaseUri: _client.baseUri);
  }

  Future<void> controlJob({required String jobId, required String action}) async {
    await _client.post(ApiEndpoints.taskControl.replaceFirst('{jobId}', jobId), data: {'action': action});
  }
}
