import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:dio/dio.dart';

abstract interface class ConnectionRepository {
  Future<List<DeviceConnection>> discover();
  Future<List<DeviceConnection>> recentDevices();
  Future<DeviceConnection?> savedDevice();
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  });
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  });
  Future<DeviceStatus> reconnect({CancelToken? cancelToken});
  Future<void> disconnect();
  Future<void> forgetDevice();
}
