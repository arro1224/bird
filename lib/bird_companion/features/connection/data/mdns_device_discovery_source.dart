import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// 默认服务名是联调约定，真实盒子端若使用其它服务名只需改此构造参数。
class MdnsDeviceDiscoverySource implements DeviceDiscoverySource {
  MdnsDeviceDiscoverySource({this.serviceName = '_birdbox._tcp.local', this.timeout = const Duration(seconds: 3)});

  final String serviceName;
  final Duration timeout;

  @override
  Future<List<DeviceConnection>> discover() async {
    final client = MDnsClient();
    final result = <DeviceConnection>[];
    try {
      await client.start();
      await for (final pointer in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(serviceName)).timeout(timeout)) {
        await for (final service in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(pointer.domainName)).timeout(timeout)) {
          await for (final address in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(service.target)).timeout(timeout)) {
            result.add(
              DeviceConnection(
                id: service.target,
                name: service.target.replaceFirst('.local', ''),
                baseUri: Uri(scheme: 'http', host: address.address.address, port: service.port),
                networkMode: NetworkMode.lan,
              ),
            );
          }
        }
      }
    } on TimeoutException {
      // 未发现设备属于正常结果，页面会提供手动地址入口。
    } finally {
      client.stop();
    }
    final seen = <String>{};
    return result.where((item) => seen.add(item.baseUri.toString())).toList();
  }
}
