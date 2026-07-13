import 'package:aves/bird_companion/core/models/device_models.dart';

abstract interface class DeviceDiscoverySource {
  Future<List<DeviceConnection>> discover();
}

/// 盒子端尚未锁定 mDNS/UDP 发现协议前，先从已知设备中恢复可连接对象。
/// 未来只需以 mDNS 或 UDP 实现替换此类，不需要改动页面和 Repository。
class KnownDeviceDiscoverySource implements DeviceDiscoverySource {
  KnownDeviceDiscoverySource(this._knownDevices);

  final Future<List<DeviceConnection>> Function() _knownDevices;

  @override
  Future<List<DeviceConnection>> discover() => _knownDevices();
}

class CompositeDeviceDiscoverySource implements DeviceDiscoverySource {
  const CompositeDeviceDiscoverySource(this.sources);
  final List<DeviceDiscoverySource> sources;

  @override
  Future<List<DeviceConnection>> discover() async {
    final lists = await Future.wait(sources.map((source) => source.discover()));
    return lists.expand((items) => items).toList();
  }
}
