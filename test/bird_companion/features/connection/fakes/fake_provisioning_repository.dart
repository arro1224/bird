import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_repository.dart';

final class FakeProvisioningRepository implements ProvisioningRepository {
  FakeProvisioningRepository({
    Iterable<ProvisioningDevice> devices = const [],
    this.deviceInfo,
    this.pairingWindow,
    this.discoverError,
    this.connectError,
    this.openPairingError,
    this.authorizeError,
  }) : _devices = List.of(devices);

  final List<ProvisioningDevice> _devices;
  final ProvisioningDeviceInfo? deviceInfo;
  final PairingWindow? pairingWindow;
  final Object? discoverError;
  final Object? connectError;
  final Object? openPairingError;
  final Object? authorizeError;
  final StreamController<ProvisioningEvent> _events = StreamController.broadcast();
  final List<String> calls = [];

  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) {
    calls.add('discover');
    if (discoverError != null) return Stream.error(discoverError!);
    return Stream.fromIterable(_devices);
  }

  @override
  Future<void> stopDiscovery() async => calls.add('stopDiscovery');

  @override
  Future<ProvisioningDeviceInfo> connect(ProvisioningDevice device) async {
    calls.add('connect:${device.scanId}');
    if (connectError != null) throw connectError!;
    return deviceInfo ?? (throw StateError('deviceInfo must be configured'));
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  Stream<ProvisioningEvent> get events => _events.stream;

  @override
  Future<PairingWindow> openPairing() async {
    calls.add('openPairing');
    if (openPairingError != null) throw openPairingError!;
    return pairingWindow ?? (throw StateError('pairingWindow must be configured'));
  }

  @override
  Future<PairingAuthorization> authorizePairing(String pairingCode) async {
    calls.add('authorize:$pairingCode');
    if (authorizeError != null) throw authorizeError!;
    return PairingAuthorization.fromJson(const {
      'pairing_session_id': 'pairing-session-test',
      'expires_in': 60,
    });
  }

  @override
  Future<ProvisioningNetworkStatus> getNetworkStatus() => throw UnimplementedError();

  @override
  Future<CommandAccepted> startDirectAp() => throw UnimplementedError();

  @override
  Future<CommandAccepted> stopDirectAp() => throw UnimplementedError();

  @override
  Future<CommandAccepted> scanWifi() => throw UnimplementedError();

  @override
  Future<CommandAccepted> setStaConfig(StaNetworkConfiguration configuration) => throw UnimplementedError();

  @override
  Future<CommandAccepted> startDppProvisioning() => throw UnimplementedError();

  @override
  Future<CommandAccepted> cancelNetworkOperation(String operationId) => throw UnimplementedError();

  @override
  Future<void> dispose() => _events.close();
}
