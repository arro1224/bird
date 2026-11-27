import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble_peer_hint_store.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

const _id = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _other = 'bbx-11111111111111111111111111111111';
Map<String, dynamic> _fixture(String name) => Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/$name').readAsStringSync()) as Map);
ProvisioningDeviceInfo _info(String id) => ProvisioningDeviceInfo.fromJson({..._fixture('ble-device-info.rc4.json'), 'device_id': id});
BirdBoxAdvertisement _ad(String handle, {String name = 'BirdBox-82F41C9E', bool service = true}) => BirdBoxAdvertisement(localName: name, serviceUuids: service ? [BleProtocolConstants.serviceUuid] : [], rssi: -40, platformDeviceId: handle);

void main() {
  test('STA-only verified BLE hints survive repository restart without any AP profile', () async {
    final storage = MemoryDirectApAuthorizationStore();
    final first = _Harness(storage: storage);
    first.ble.advertisements = [_ad('verified-sta')];
    await first.repo.connect(await first.repo.discoverDevices().first);
    final saved = await first.hints.load(_id);
    expect(saved?.platformId, 'verified-sta');
    expect(saved?.deviceId, _id);
    expect(jsonEncode(await storage.load(_id)), isNot(contains('passphrase')));
    await first.close();
    final reopened = _Harness(storage: storage);
    addTearDown(reopened.close);
    expect((await reopened.repo.recoverBleControl(_id, CancelToken())).deviceId, _id);
    expect(reopened.ble.connections, ['verified-sta']);
    expect(reopened.ble.scans, 0);
    expect(reopened.http.calls, 0);
    expect(reopened.wifi.requestedSsids, isEmpty);
  });

  test('cold recovery with no hints scans and validates Device Info', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('new')];
    expect((await h.repo.recoverBleControl(_id, CancelToken())).deviceId, _id);
    expect(h.ble.scans, 1);
    expect(h.ble.notifications, 1);
    expect(h.ble.connections, ['new']);
    expect(h.http.calls, 0);
    expect(h.ble.commands, isEmpty);
  });

  test('no advertisement terminates with a distinct not-found result', () async {
    final h = _Harness();
    addTearDown(h.close);
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<BleControlRecoveryException>().having((e) => e.reason, 'reason', BleControlRecoveryFailure.notFound)));
    expect(h.ble.connections, isEmpty);
    expect(h.wifi.releaseCount, 0);
  });

  test('advertisement names without the BirdBox service cannot become candidates', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('name-only', service: false)];
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<BleControlRecoveryException>()));
    expect(h.ble.connections, isEmpty);
  });

  test('an existing different BLE identity is preserved rather than replaced', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.identities['other'] = _other;
    await h.repo.connect(ProvisioningDevice(scanId: 'other', advertisement: _ad('other')));
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.deviceIdMismatch)));
    expect(h.repo.connectedDeviceInfo?.deviceId, _other);
    expect(h.ble.connections, ['other']);
    expect(h.wifi.releaseCount, 0);
  });

  test('the total recovery deadline includes hint storage reads', () async {
    final h = _Harness(storage: _SlowStore(), timeout: const Duration(milliseconds: 80));
    addTearDown(h.close);
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<BleControlRecoveryException>().having((e) => e.reason, 'reason', BleControlRecoveryFailure.timeout)));
    expect(h.ble.scans, 0);
    expect(h.ble.connections, isEmpty);
  });

  test('a stale platform hint can be replaced by a fresh advertisement', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.seed('stale');
    h.ble.failures['stale'] = [_gatt];
    h.ble.advertisements = [_ad('fresh')];
    await h.repo.recoverBleControl(_id, CancelToken());
    expect(h.ble.connections, ['stale', 'fresh']);
    expect((await h.hints.load(_id))!.platformId, 'fresh');
  });

  test('the same address may recover after a fresh advertisement and one transient failure', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.seed('same');
    h.ble.failures['same'] = [_gatt];
    h.ble.advertisements = [_ad('same')];
    await h.repo.recoverBleControl(_id, CancelToken());
    expect(h.ble.connections, ['same', 'same']);
    expect(h.ble.scans, 1);
  });

  test('advertising without usable GATT has a finite attempt budget', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('no-gatt')];
    h.ble.failures['no-gatt'] = [_gatt, _gatt, _gatt, _gatt];
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleGattOperationFailed)));
    expect(h.ble.connections, hasLength(2));
    expect(h.ble.scans, 1);
  });

  for (final code in [ProvisioningErrorCode.bluetoothPermissionDenied, ProvisioningErrorCode.bluetoothUnavailable, ProvisioningErrorCode.locationServicesDisabled]) {
    test('scan ${code.wireValue} is preserved without connection retries', () async {
      final h = _Harness();
      addTearDown(h.close);
      h.ble.scanError = ProvisioningException(code: code, retryable: true);
      await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', code)));
      expect(h.ble.connections, isEmpty);
      expect(h.ble.scans, 1);
    });
  }

  test('permission denial on a saved hint cannot trigger a fallback scan', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.seed('denied');
    h.ble.failures['denied'] = [const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: true)];
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<ProvisioningException>()));
    expect(h.ble.scans, 0);
    expect(h.ble.connections, hasLength(1));
  });

  test('a same-name wrong peer is rejected before it can replace the trusted target', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('spoof')];
    h.ble.identities['spoof'] = _other;
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.deviceIdMismatch)));
    expect(h.repo.connectedDeviceInfo, isNull);
    expect(await h.hints.load(_other), isNull);
    expect(await h.hints.load(_id), isNull);
    expect(h.wifi.releaseCount, 0);
    expect(h.http.calls, 0);
  });

  test('unhinted discovery can reject one peer and verify the next', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('wrong'), _ad('right')];
    h.ble.identities['wrong'] = _other;
    expect((await h.repo.recoverBleControl(_id, CancelToken())).deviceId, _id);
    expect(h.ble.connections, ['wrong', 'right']);
    expect((await h.hints.load(_id))?.platformId, 'right');
  });

  test('ten concurrent recoveries share one discovery and one connection', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('shared')];
    final result = await Future.wait(List.generate(10, (_) => h.repo.recoverBleControl(_id, CancelToken())));
    expect(result, hasLength(10));
    expect(h.ble.scans, 1);
    expect(h.ble.connections, hasLength(1));
  });

  test('cancelling a joined waiter does not cancel the original recovery', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.seed('shared');
    h.ble.connectGate = Completer<void>();
    final first = h.repo.recoverBleControl(_id, CancelToken());
    await _until(() => h.ble.connections.isNotEmpty);
    final token = CancelToken();
    final joined = h.repo.recoverBleControl(_id, token);
    final rejected = expectLater(joined, throwsA(isA<DioException>()));
    token.cancel('joined view closed');
    await rejected;
    h.ble.connectGate!.complete();
    expect((await first).deviceId, _id);
    expect(h.ble.connections, hasLength(1));
  });

  test('cancel during discovery stops without a late connection', () async {
    final h = _Harness();
    addTearDown(h.close);
    final scan = StreamController<BirdBoxAdvertisement>();
    addTearDown(scan.close);
    h.ble.liveScan = scan.stream;
    final token = CancelToken();
    final future = h.repo.recoverBleControl(_id, token);
    final rejected = expectLater(future, throwsA(isA<DioException>()));
    await _until(() => h.ble.scans == 1);
    token.cancel('cancel');
    await rejected;
    scan.add(_ad('late'));
    await Future<void>.delayed(Duration.zero);
    expect(h.ble.connections, isEmpty);
    expect(h.wifi.releaseCount, 0);
  });

  test('the overall deadline also bounds a stalled GATT connect', () async {
    final h = _Harness(timeout: const Duration(milliseconds: 80));
    addTearDown(h.close);
    await h.seed('slow');
    h.ble.connectGate = Completer<void>();
    await expectLater(h.repo.recoverBleControl(_id, CancelToken()), throwsA(isA<BleControlRecoveryException>().having((e) => e.reason, 'reason', BleControlRecoveryFailure.timeout)));
    h.ble.connectGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(h.repo.connectedDeviceInfo, isNull);
    expect(h.wifi.releaseCount, 0);
  });

  test('a wrong-key or malformed persisted hint never becomes a trusted identity', () async {
    final storage = MemoryDirectApAuthorizationStore();
    final h = _Harness(storage: storage);
    addTearDown(h.close);
    await storage.write(_id, {'version': 1, 'device_id': _other, 'platform_id': 'wrong', 'name': 'BirdBox', 'verified_at': '2026-11-25T12:00:00Z'});
    h.ble.advertisements = [_ad('verified')];
    await h.repo.recoverBleControl(_id, CancelToken());
    expect(h.ble.connections, ['verified']);
    expect((await h.hints.load(_id))!.deviceId, _id);
  });

  test('recovery diagnostics include safe stages and results, never opaque handles', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.ble.advertisements = [_ad('private-platform-handle')];
    await h.repo.recoverBleControl(_id, CancelToken());
    expect(h.diagnostics.map((e) => e['event']), containsAll(['ble_control_recovery_started', 'ble_control_scan_started', 'ble_control_scan_finished', 'ble_control_candidate_connecting', 'ble_control_recovery_finished']));
    expect(h.diagnostics.last['outcome'], 'connected');
    expect(h.diagnostics.last['candidate_source'], 'scan');
    expect(jsonEncode(h.diagnostics), isNot(contains('private-platform-handle')));
  });
}

const _gatt = ProvisioningException(code: ProvisioningErrorCode.bleGattOperationFailed, retryable: true);
Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('operation did not start');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Harness {
  _Harness({DirectApAuthorizationStore? storage, Duration timeout = const Duration(seconds: 2)}) {
    hints = BlePeerHintStore(storage ?? MemoryDirectApAuthorizationStore());
    repo = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: wifi,
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: 'a870bcb1-d423-4d66-96f7-f809ce786543'),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(http),
      pairingApi: PairingApi(http),
      blePeerHintStore: hints,
      diagnostic: diagnostics.add,
      controlRecoveryTimeout: timeout,
      controlScanTimeout: const Duration(milliseconds: 40),
    );
  }
  final ble = _Ble();
  final wifi = FakeBirdBoxWifiPlatform();
  final http = _NoHttp();
  final diagnostics = <Map<String, dynamic>>[];
  late final BlePeerHintStore hints;
  late final ProvisioningRepositoryImpl repo;
  Future<void> seed(String handle) => hints.save(BlePeerHint(deviceId: _id, platformId: handle, name: 'BirdBox-82F41C9E', verifiedAt: DateTime.utc(2026, 11, 25)));
  Future<void> close() async {
    await repo.dispose();
    await http.dispose();
  }
}

class _SlowStore implements DirectApAuthorizationStore {
  @override
  Future<Map<String, dynamic>?> load(String id) => Completer<Map<String, dynamic>?>().future;
  @override
  Future<void> write(String id, Map<String, dynamic> value) async {}
  @override
  Future<void> remove(String id) async {}
}

class _NoHttp extends ApiClient {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    calls++;
    throw StateError('Control recovery must not request HTTP');
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) async {
    calls++;
    throw StateError('Control recovery must not request HTTP');
  }
}

class _Ble implements BirdBoxBleDataSource {
  List<BirdBoxAdvertisement> advertisements = [];
  final connections = <String>[];
  final failures = <String, List<ProvisioningException>>{};
  final identities = <String, String>{};
  final commands = <BleCommandRequest>[];
  final _events = StreamController<ProvisioningEvent>.broadcast();
  final _disconnects = StreamController<void>.broadcast();
  int scans = 0, notifications = 0;
  bool _connected = false;
  String? current;
  Completer<void>? connectGate;
  Stream<BirdBoxAdvertisement>? liveScan;
  Object? scanError;
  @override
  Stream<BirdBoxAdvertisement> scan({Duration? timeout}) {
    scans++;
    if (scanError != null) return Stream.error(scanError!);
    return liveScan ?? Stream.fromIterable(advertisements);
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BirdBoxAdvertisement ad) async {
    final id = ad.platformDeviceId!;
    connections.add(id);
    current = id;
    final errors = failures[id];
    if (errors != null && errors.isNotEmpty) throw errors.removeAt(0);
    await connectGate?.future;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _disconnects.add(null);
  }

  @override
  bool get isConnected => _connected;
  @override
  Future<ProvisioningDeviceInfo> readDeviceInfo() async => _info(identities[current] ?? _id);
  @override
  Future<ProvisioningNetworkStatus> readNetworkStatus() async => ProvisioningEvent.fromJson(_fixture('ble-network-status.rc4.json')).payload as ProvisioningNetworkStatus;
  @override
  Future<void> subscribeRequiredNotifications() async {
    notifications++;
  }

  @override
  bool get requiredNotificationsSubscribed => notifications > 0;
  @override
  Future<ProvisioningEvent> writeCommand(BleCommandRequest request) async {
    commands.add(request);
    return ProvisioningEvent.fromJson({..._fixture('ble-network-status.rc4.json'), 'request_id': request.requestId});
  }

  @override
  Stream<ProvisioningEvent> get events => _events.stream;
  @override
  Stream<void> get disconnects => _disconnects.stream;
  @override
  Future<void> dispose() async {
    await _events.close();
    await _disconnects.close();
  }
}
