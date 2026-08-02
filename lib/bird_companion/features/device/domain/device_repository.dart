import 'package:aves/bird_companion/core/models/device_models.dart';

abstract interface class DeviceRepository {
  Future<DeviceStatus> fetchStatus();
  Stream<DeviceStatus> watchStatus();
  Future<void> controlJob({
    required String jobId,
    required String action,
    required int version,
  });
}
