import 'dart:async';

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
    late StreamController<DeviceStatus> controller;
    StreamSubscription<DeviceEvent>? eventSubscription;
    Timer? fallbackTimer;
    var fallbackInFlight = false;

    Future<void> pollWhenEventsUnavailable() async {
      if (_eventClient.currentState == EventConnectionState.connected || fallbackInFlight) return;
      fallbackInFlight = true;
      try {
        controller.add(await _api.fetchStatus());
      } catch (_) {
        // Keep the last valid status visible; the normal page retry and
        // diagnostics screen surface persistent API failures to the user.
      } finally {
        fallbackInFlight = false;
      }
    }

    controller = StreamController<DeviceStatus>(
      onListen: () {
        eventSubscription = _eventClient.events
            .where((event) => event.type == 'device_status_changed' || event.type == 'device_status' || event.type == 'status_changed')
            .listen(
              (event) => controller.add(DeviceStatus.fromJson(event.payload, fallbackBaseUri: _apiClient.baseUri)),
              onError: (_) {},
            );
        fallbackTimer = Timer.periodic(const Duration(seconds: 5), (_) => pollWhenEventsUnavailable());
      },
      onCancel: () async {
        fallbackTimer?.cancel();
        await eventSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> controlJob({
    required String jobId,
    required String action,
    required int version,
  }) => _api.controlJob(jobId: jobId, action: action, version: version);
}
