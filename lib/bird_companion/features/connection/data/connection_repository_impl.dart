import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';

class ConnectionRepositoryImpl implements ConnectionRepository {
  ConnectionRepositoryImpl(this._api, this._cache, this._discoverySource);

  static const _recentDevicesKey = 'recent_devices';
  static const _activeDeviceKey = 'active_device';

  final ConnectionApi _api;
  final LocalCache _cache;
  final DeviceDiscoverySource _discoverySource;

  @override
  Future<List<DeviceConnection>> discover() async {
    final discovered = await _discoverySource.discover();
    return _unique([...discovered, ...await recentDevices()]);
  }

  @override
  Future<List<DeviceConnection>> recentDevices() async {
    final raw = _cache.read<List<dynamic>>(_recentDevicesKey) ?? const [];
    return raw.whereType<Map>().map((value) => DeviceConnection.fromJson(Map<String, dynamic>.from(value))).where((device) => device.baseUri.host.isNotEmpty).toList();
  }

  @override
  Future<DeviceConnection?> savedDevice() async {
    final raw = _cache.read<Map>(_activeDeviceKey);
    if (raw == null) return null;
    final device = DeviceConnection.fromJson(Map<String, dynamic>.from(raw));
    return device.baseUri.host.isEmpty ? null : device;
  }

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async {
    final status = await _api.handshake(baseUri, networkMode, cancelToken: cancelToken);
    await _save(status, cancelToken);
    return status;
  }

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) async {
    final status = await _api.pair(
      baseUri,
      networkMode,
      pairingCode: pairingCode,
      cancelToken: cancelToken,
    );
    await _save(status, cancelToken);
    return status;
  }

  Future<void> _save(
    DeviceStatus status,
    CancelToken? cancelToken,
  ) async {
    if (cancelToken?.isCancelled == true) {
      throw StateError('Connection cancelled before the device was saved.');
    }
    final device = status.connection;
    final recent = _unique([device, ...await recentDevices()]).take(10).toList();
    await _cache.write(_recentDevicesKey, recent.map((item) => item.toJson()).toList());
    await _cache.write(_activeDeviceKey, device.toJson());
  }

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    final device = await savedDevice();
    if (device == null) throw StateError('没有可重连的盒子设备。');
    return connect(device.baseUri, networkMode: device.networkMode, cancelToken: cancelToken);
  }

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<void> forgetDevice() async {
    final device = await savedDevice();
    if (device == null) {
      await _api.disconnect();
    } else {
      await _api.forget(device.id);
    }
    await _cache.remove(_activeDeviceKey);
    await _cache.remove(_recentDevicesKey);
  }

  List<DeviceConnection> _unique(List<DeviceConnection> devices) {
    final ids = <String>{};
    return devices.where((device) => ids.add(device.id.isEmpty ? device.baseUri.toString() : device.id)).toList();
  }
}
