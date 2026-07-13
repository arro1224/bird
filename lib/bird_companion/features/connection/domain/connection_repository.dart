import 'package:aves/bird_companion/core/models/device_models.dart';

abstract interface class ConnectionRepository {
  Future<List<DeviceConnection>> discover();
  Future<List<DeviceConnection>> recentDevices();
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode});
  Future<DeviceStatus> reconnect();
  Future<void> disconnect();
  Future<void> forgetDevice();
}
