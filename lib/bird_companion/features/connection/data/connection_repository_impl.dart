import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/storage/local_cache.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';

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
  Future<DeviceStatus> connect(Uri baseUri, {required NetworkMode networkMode}) async {
    final status = await _api.handshake(baseUri, networkMode);
    final device = status.connection;
    final recent = _unique([device, ...await recentDevices()]).take(10).toList();
    await _cache.write(_recentDevicesKey, recent.map((item) => item.toJson()).toList());
    await _cache.write(_activeDeviceKey, device.toJson());
    return status;
  }

  @override
  Future<DeviceStatus> reconnect() async {
    final raw = _cache.read<Map>(_activeDeviceKey);
    if (raw == null) throw StateError('没有可重连的盒子设备。');
    final device = DeviceConnection.fromJson(Map<String, dynamic>.from(raw));
    return connect(device.baseUri, networkMode: device.networkMode);
  }

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<void> forgetDevice() async {
    await _api.disconnect();
    await _cache.remove(_activeDeviceKey);
    await _cache.remove(_recentDevicesKey);
  }

  List<DeviceConnection> _unique(List<DeviceConnection> devices) {
    final ids = <String>{};
    return devices.where((device) => ids.add(device.id.isEmpty ? device.baseUri.toString() : device.id)).toList();
  }
}
