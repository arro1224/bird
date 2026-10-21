import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/pairing_preflight_platform.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';
import 'fakes/preflight_ble_platform.dart';

const open = BleCommandRequest(type: BleCommandType.openPairing, requestId: '550e8400-e29b-41d4-a716-446655440000', clientId: PreflightBlePlatform.client);
const unconfirmed = ProvisioningException(code: ProvisioningErrorCode.bleGattReleaseUnconfirmed, retryable: false);
Matcher code(ProvisioningErrorCode value) => throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', value));

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 300; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Expected release stage was not reached');
}

final class Sink implements BleConnectionDiagnosticSink {
  final events = <BleConnectionDiagnosticEvent>[];
  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async => events.add(event);
}

final class ActivePlatform extends PreflightBlePlatform {
  String? trace;
  bool rawRequested = false;
  final security = Completer<BlePairingReady>();
  @override
  Future<int> connect(String platformDeviceId, {required String traceId}) {
    trace = traceId;
    return super.connect(platformDeviceId, traceId: traceId);
  }

  @override
  Future<BlePairingReady> preparePairing(String requestId, String commandType) {
    nativeRequest = requestId;
    return security.future;
  }

  @override
  Future<void> disconnectOwned(String? requestId, BlePairingReady? ready, int? connectionGeneration) async {
    expect(requestId, nativeRequest);
    rawRequested = true;
    connected = false;
    retiring = true;
    nativeRequest = null;
    disconnectEvents.add(BleDisconnectEvent(reason: 'requested', gattStatus: 0, unexpected: false, connectionGeneration: generation, gattInstanceId: instance));
    if (!security.isCompleted) security.completeError(const ProvisioningException(code: ProvisioningErrorCode.bleSessionEnded, retryable: false));
  }

  void terminal({int? instanceId = 1, int? fromGeneration, bool timeout = false, bool physicallyReleased = true}) {
    if (physicallyReleased) retiring = false;
    diagnostic.add({
      'traceId': trace,
      'eventType': timeout ? 'controlled_release_disconnect_timeout' : 'controlled_release_disconnect_confirmed',
      'resultCode': timeout ? 'disconnect_callback_missing' : 'retired_gatt_disconnected',
      'connectionGeneration': fromGeneration ?? generation,
      'gattInstanceId': ?instanceId,
    });
  }
}

void main() {
  PlatformBirdBoxBleDataSource source(PreflightBlePlatform platform, {Sink? sink}) {
    final ble = PlatformBirdBoxBleDataSource(platform: platform, connectionDiagnosticSink: sink, releaseTimeout: const Duration(milliseconds: 80));
    addTearDown(ble.dispose);
    return ble;
  }

  Future<void> prepared(PlatformBirdBoxBleDataSource ble) => ble.prepareConnection(PreflightBlePlatform.advertisement, clientId: PreflightBlePlatform.client);

  NativeGattReleaseSnapshot record({String? trace, int instance = 1, String state = 'confirmed'}) => NativeGattReleaseSnapshot(
    connectionGeneration: 1,
    gattInstanceId: instance,
    state: state,
    resultCode: state == 'confirmed' ? 'retired_gatt_disconnected' : 'disconnect_callback_missing',
    disconnectObserved: state == 'confirmed',
    closeCompleted: true,
    traceId: trace,
  );

  test('raw release recovers missed terminal event from exact native release record', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    final release = ble.disconnect();
    await until(() => platform.rawRequested);
    platform.retiring = false;
    platform.lastRelease = record(trace: platform.trace);
    await release;
    await command;
    expect(ble.nativeReleaseBlocked, isFalse);
  });

  test('release query cannot substitute a foreign trace or same-generation instance', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    var done = false;
    final release = ble.disconnect().then((_) => done = true);
    await until(() => platform.rawRequested);
    platform.lastRelease = record(trace: 'foreign');
    await Future<void>.delayed(const Duration(milliseconds: 22));
    expect(done, isFalse);
    platform.lastRelease = record(trace: platform.trace, instance: 2);
    await Future<void>.delayed(const Duration(milliseconds: 22));
    expect(done, isFalse);
    platform.lastRelease = record(trace: platform.trace);
    platform.retiring = false;
    await release;
    await command;
  });

  test('queried native timeout remains failure after missed event', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    final release = expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await until(() => platform.rawRequested);
    platform.retiring = false;
    platform.lastRelease = record(trace: platform.trace, state: 'unconfirmed');
    await release;
    await command;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(ble.nativeReleaseBlocked, isTrue);
  });

  test('terminal success cannot override contradictory native release snapshot', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    final release = expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await until(() => platform.rawRequested);
    platform.lastRelease = record(trace: platform.trace, state: 'unconfirmed');
    platform.terminal();
    await release;
    await command;
    expect(ble.nativeReleaseBlocked, isTrue);
  });

  test('explicit retry can use subsequently queried confirmation without toggling Bluetooth', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await prepared(ble);
    platform.controlledReleaseError = unconfirmed;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    platform.lastRelease = record();
    expect(ble.nativeReleaseBlocked, isTrue);
    await ble.disconnect();
    expect(ble.nativeReleaseBlocked, isFalse);
    expect(platform.adapter, BleAdapterState.enabled);
    expect(platform.publicReleaseOwners, [(1, 1)]);
  });

  test('idle bonded disconnect shares one held owned release and blocks reads, writes, scans and dials', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await prepared(ble);
    await ble.writeCommand(open);
    platform.releaseBarrier = Completer<void>();
    final first = ble.disconnect(), duplicate = ble.disconnect();
    expect(identical(first, duplicate), isTrue);
    await until(() => platform.publicReleaseOwners.isNotEmpty);
    await expectLater(ble.scan().toList(), code(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(ble.connect(PreflightBlePlatform.advertisement), code(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(ble.readDeviceInfo(), code(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(ble.writeCommand(open), code(ProvisioningErrorCode.bleOperationBusy));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    platform.releaseBarrier!.complete();
    await first;
    expect(ble.isConnected, isFalse);
  });

  for (final missingInstance in [false, true]) {
    test('raw disconnect request waits for ${missingInstance ? 'missing-instance contract repair' : 'exact instance confirmation and native close'}', () async {
      final platform = ActivePlatform();
      final sink = Sink();
      final ble = source(platform, sink: sink);
      await prepared(ble);
      final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
      await until(() => platform.nativeRequest != null);
      var done = false;
      final release = ble.disconnect().then((_) => done = true);
      final checked = missingInstance ? expectLater(release, code(ProvisioningErrorCode.bleGattReleaseUnconfirmed)) : release;
      await until(() => platform.rawRequested);
      expect(done, isFalse);
      platform.terminal(instanceId: missingInstance ? null : 1);
      await checked;
      await command;
      expect(done, !missingInstance);
      expect(ble.nativeReleaseBlocked, missingInstance);
      if (missingInstance) {
        expect(sink.events.any((e) => e.eventType == 'gatt_release_completion_unattributed'), isTrue);
        expect(sink.events.any((e) => e.eventType == 'gatt_release_confirmed'), isFalse);
      } else {
        expect(sink.events.singleWhere((e) => e.eventType == 'gatt_release_confirmed').gattInstanceId, 1);
      }
    });
  }

  test('wrong generation and same-generation foreign instance cannot complete raw release', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    var done = false;
    final release = ble.disconnect().then((_) => done = true);
    await until(() => platform.rawRequested);
    platform.terminal(fromGeneration: 2, physicallyReleased: false);
    platform.terminal(instanceId: 2, physicallyReleased: false);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    platform.terminal();
    await release;
    await command;
    expect(done, isTrue);
  });

  test('timeout followed by late confirmation never automatically reopens connection gate', () async {
    final platform = ActivePlatform();
    final ble = source(platform);
    await prepared(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    final release = expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await until(() => platform.rawRequested);
    platform.terminal(timeout: true);
    await release;
    await command;
    platform.terminal();
    await expectLater(ble.connect(PreflightBlePlatform.advertisement), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(ble.nativeReleaseBlocked, isTrue);
    platform.adapter = BleAdapterState.disabled;
    await ble.disconnect();
    expect(ble.nativeReleaseBlocked, isFalse);
  });

  test('explicit retry requires adapter off and non-retiring absence, keeps original timeout evidence', () async {
    final platform = PreflightBlePlatform();
    final sink = Sink();
    final ble = source(platform, sink: sink);
    await prepared(ble);
    platform.controlledReleaseError = unconfirmed;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    platform.adapter = BleAdapterState.disabled;
    platform.retiring = true;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    platform.retiring = false;
    await ble.disconnect();
    expect(ble.nativeReleaseBlocked, isFalse);
    expect(sink.events.any((e) => e.eventType == 'gatt_release_recovered' && e.resultCode == 'adapter_disabled_and_native_absent'), isTrue);
    expect(jsonEncode(sink.events.map((e) => e.toJson()).toList()), contains('BLE_GATT_RELEASE_UNCONFIRMED'));
    platform.adapter = BleAdapterState.enabled;
    platform.controlledReleaseError = null;
    await prepared(ble);
    expect(platform.generation, 2);
  });

  test('explicit recovery never disconnects a replacement instance', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await prepared(ble);
    platform.controlledReleaseError = unconfirmed;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    platform.connected = true;
    platform.instance = 2;
    platform.controlledReleaseError = null;
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.connected, isTrue);
    expect(platform.publicReleaseOwners, [(1, 1)]);
  });

  test('foreground retiring enters visible release failure and explicit recovery survives page recreation', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final api = ApiClient();
    final repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: PreflightBlePlatform.client),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
    );
    final first = ProvisioningCubit(repository);
    await first.selectDevice(ProvisioningDevice(scanId: 'test', advertisement: PreflightBlePlatform.advertisement));
    platform.retiring = true;
    await first.onAppResumed();
    expect(first.state.linkStatus, BleLinkStatus.releaseFailed);
    expect((first.state.error as ProvisioningException).code, ProvisioningErrorCode.bleGattReleaseUnconfirmed);
    await first.close();
    final second = ProvisioningCubit(repository);
    await second.discover();
    expect(second.state.linkStatus, BleLinkStatus.releaseFailed);
    expect(platform.generation, 1);
    platform.adapter = BleAdapterState.disabled;
    platform.connected = false;
    platform.retiring = false;
    await second.reset();
    expect(repository.sessionReleaseFailed, isFalse);
    expect(second.state.linkStatus, BleLinkStatus.disconnected);
    await second.close();
    await repository.dispose();
    await api.dispose();
  });
}
