import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/$name').readAsStringSync()) as Map);
final advertisement = BirdBoxAdvertisement(localName: 'BirdBox-TEST', serviceUuids: const {'6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000'}, rssi: -45);
final device = ProvisioningDevice(scanId: 'device', advertisement: advertisement);

class GateBle implements BirdBoxBleDataSource, BleProvisioningControl {
  final delegate = FakeBirdBoxBleDataSource(
    deviceInfo: ProvisioningDeviceInfo.fromJson(fixture('ble-device-info.rc4.json')),
    networkStatus: ProvisioningNetworkStatus.fromJson(fixture('ble-network-status.rc4.json')['payload'] as Map<String, dynamic>),
    advertisements: [advertisement],
  );
  final order = <String>[];
  Object? owner;
  final release = Completer<void>();
  Object? releaseError;
  int claims = 0, releases = 0, lostReleaseOwners = 0, writes = 0;
  @override
  Object claimSession() {
    claims++;
    order.add('claim');
    return owner = Object();
  }

  @override
  bool ownsSession(Object candidate) => identical(candidate, owner);
  @override
  Future<void> endSession(Object candidate) async {
    if (!ownsSession(candidate)) return;
    releases++;
    order.add('release-start');
    await release.future;
    if (releaseError != null) throw releaseError!;
    if (!ownsSession(candidate)) {
      lostReleaseOwners++;
      return;
    }
    await delegate.disconnect();
    order.add('release-complete');
  }

  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) {
    order.add('scan');
    return delegate.scan(timeout: timeout);
  }

  @override
  Future<void> connect(BirdBoxAdvertisement advertisement) async {
    order.add('connect');
    await delegate.connect(advertisement);
  }

  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) {
    writes++;
    return delegate.writeCommand(request);
  }

  @override
  Future<void> disconnect() => delegate.disconnect();
  @override
  Future<void> stopScan() => delegate.stopScan();
  @override
  bool get isConnected => delegate.isConnected;
  @override
  bool get requiredNotificationsSubscribed => delegate.requiredNotificationsSubscribed;
  @override
  Future<void> subscribeRequiredNotifications() => delegate.subscribeRequiredNotifications();
  @override
  Future<ProvisioningDeviceInfo> readDeviceInfo() => delegate.readDeviceInfo();
  @override
  Future<ProvisioningNetworkStatus> readNetworkStatus() => delegate.readNetworkStatus();
  @override
  Stream<ProvisioningEvent> get events => delegate.events;
  @override
  Stream<void> get disconnects => delegate.disconnects;
  @override
  Future<void> dispose() => delegate.dispose();
  @override
  Future<void> pauseDiscovery(Object owner) async {}
  @override
  Future<void> resumeDiscovery(Object owner) async {}
  @override
  Future<void> openLocationSettings(Object owner) async {}
  @override
  Future<void> locationSettingsReturned(Object owner, {required bool enabled}) async {}
  @override
  Future<BleScanEnvironment> readScanEnvironment() async => const BleScanEnvironment.unknown();
  @override
  Stream<BlePairingProgress> get pairingProgress => const Stream.empty();
}

void main() {
  late GateBle ble;
  late ApiClient api;
  late ProvisioningRepositoryImpl repository;
  setUp(() {
    ble = GateBle();
    api = ApiClient();
    repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: 'a870bcb1-d423-4d66-96f7-f809ce786543'),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
    );
  });
  tearDown(() async {
    ble.releaseError = null;
    if (!ble.release.isCompleted) ble.release.complete();
    await repository.dispose();
    await api.dispose();
  });

  test('new page owner waits for the old native owner to finish before scanning or connecting', () async {
    final old = repository.claimSession();
    final first = repository.endSession(old);
    final duplicate = repository.endSession(old);
    expect(identical(first, duplicate), true);
    final current = repository.claimSession();
    expect(repository.ownsSession(old), false);
    expect(repository.ownsSession(current), true);
    expect(ble.claims, 1);
    final scan = repository.discoverDevices().toList();
    final connecting = repository.connect(device);
    await Future<void>.delayed(Duration.zero);
    await expectLater(repository.openPairing(), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleOperationBusy)));
    expect(ble.order, isNot(contains('scan')));
    expect(ble.order, isNot(contains('connect')));
    expect(ble.writes, 0);
    ble.release.complete();
    await first;
    await scan;
    await connecting;
    expect(ble.lostReleaseOwners, 0);
    expect(ble.releases, 1);
    expect(ble.claims, 2);
    expect(ble.order.indexOf('release-complete'), lessThan(ble.order.indexOf('scan')));
    expect(ble.order.indexOf('release-complete'), lessThan(ble.order.indexOf('connect')));
    await repository.endSession(old);
    expect(ble.releases, 1);
  });

  test('release failure blocks new GATT work until explicit release retry', () async {
    final old = repository.claimSession();
    ble.releaseError = StateError('private release failure');
    final release = expectLater(repository.endSession(old), throwsA(isA<ProvisioningException>()));
    final current = repository.claimSession();
    final connect = expectLater(repository.connect(device), throwsA(isA<ProvisioningException>()));
    ble.release.complete();
    await release;
    await connect;
    await expectLater(repository.discoverDevices().drain<void>(), throwsA(isA<ProvisioningException>()));
    expect(repository.sessionReleaseFailed, true);
    expect(ble.order, isNot(contains('scan')));
    expect(ble.order, isNot(contains('connect')));
    expect(ble.releases, 1);
    ble.releaseError = null;
    await repository.endSession(current);
    await repository.connect(device);
    expect(repository.sessionReleaseFailed, false);
    expect(ble.releases, 2);
    expect(ble.order.where((e) => e == 'connect'), hasLength(1));
  });

  test('page recreation renders release pending and does not steal native ownership', () async {
    final old = ProvisioningCubit(repository);
    final closing = old.close();
    final current = ProvisioningCubit(repository);
    final discovering = current.discover();
    await Future<void>.delayed(Duration.zero);
    expect(current.state.phase, ProvisioningPhase.disconnecting);
    expect(ble.claims, 1);
    expect(ble.order, isNot(contains('scan')));
    ble.release.complete();
    await closing;
    await discovering;
    await Future<void>.delayed(Duration.zero);
    expect(current.state.phase, ProvisioningPhase.discovered);
    expect(current.state.linkStatus, BleLinkStatus.disconnected);
    expect(ble.claims, 2);
    expect(ble.lostReleaseOwners, 0);
    await current.close();
  });
}
