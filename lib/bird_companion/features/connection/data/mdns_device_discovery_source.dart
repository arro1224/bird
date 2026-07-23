import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/features/connection/data/device_discovery_source.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// The default service name follows the Bird Box integration convention.
class MdnsDeviceDiscoverySource implements DeviceDiscoverySource {
  MdnsDeviceDiscoverySource({
    this.serviceName = '_birdbox._tcp.local',
    this.timeout = const Duration(seconds: 3),
  });

  final String serviceName;
  final Duration timeout;

  @override
  Future<List<DeviceConnection>> discover() async {
    final client = MDnsClient();
    final result = <DeviceConnection>[];
    try {
      await client.start();
      await for (final pointer in client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceName),
          )
          .timeout(timeout)) {
        await for (final service in client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(pointer.domainName),
            )
            .timeout(timeout)) {
          await for (final address in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(service.target),
              )
              .timeout(timeout)) {
            result.add(
              DeviceConnection(
                id: service.target,
                name: service.target.replaceFirst('.local', ''),
                baseUri: Uri(
                  scheme: 'http',
                  host: address.address.address,
                  port: service.port,
                ),
                networkMode: NetworkMode.lan,
              ),
            );
          }
        }
      }
    } on TimeoutException {
      // No device found is expected; manual entry remains available.
    } on SocketException catch (error, stackTrace) {
      // Some Android 8 kernels do not support SO_REUSEPORT. The mDNS package
      // requests it while opening its socket, so discovery cannot run there.
      // Discovery is optional: keep QR and manual connection usable.
      log(
        'mDNS discovery is unavailable on this device: $error',
        name: 'bird_companion.connection',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      // Vendor network stacks can reject multicast joins after the socket has
      // opened. Treat that as an empty discovery result as well.
      log(
        'mDNS discovery failed: $error',
        name: 'bird_companion.connection',
        stackTrace: stackTrace,
      );
    } finally {
      client.stop();
    }

    final seen = <String>{};
    return result.where((item) => seen.add(item.baseUri.toString())).toList();
  }
}
