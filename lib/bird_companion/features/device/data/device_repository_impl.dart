import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:aves/bird_companion/features/device/domain/device_repository.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl(this._api, this._eventClient, this._apiClient);

  final DeviceStatusApi _api;
  final EventClient _eventClient;
  final ApiClient _apiClient;

  @override
  Future<DeviceStatus> fetchStatus() => _api.fetchStatus();

  @override
  Stream<DeviceStatus> watchStatus() {
    return _eventClient.events
        .where((event) => event.type == 'device_status' || event.type == 'status_changed')
        .map(
          (event) => DeviceStatus.fromJson(event.payload, fallbackBaseUri: _apiClient.baseUri),
        );
  }

  @override
  Future<void> controlJob({required String jobId, required String action}) => _api.controlJob(jobId: jobId, action: action);
}
