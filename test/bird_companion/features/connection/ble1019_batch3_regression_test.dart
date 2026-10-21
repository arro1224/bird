import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ble1019_batch2_release_test.dart' show ActivePlatform, Sink, until, open, code;
import 'fakes/preflight_ble_platform.dart';

void main() {
  PlatformBirdBoxBleDataSource source(PreflightBlePlatform platform, {Sink? sink}) {
    final ble = PlatformBirdBoxBleDataSource(platform: platform, connectionDiagnosticSink: sink, releaseTimeout: const Duration(milliseconds: 80));
    addTearDown(ble.dispose);
    return ble;
  }

  Future<void> prepare(PlatformBirdBoxBleDataSource ble) => ble.prepareConnection(PreflightBlePlatform.advertisement, clientId: PreflightBlePlatform.client);

  test('exact disconnect callback alone cannot complete release while native remains retiring', () async {
    final platform = ActivePlatform();
    final sink = Sink();
    final ble = source(platform, sink: sink);
    await prepare(ble);
    final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
    await until(() => platform.nativeRequest != null);
    final released = expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await until(() => platform.rawRequested);
    platform.terminal(physicallyReleased: false);
    await released;
    await command;
    expect(ble.nativeReleaseBlocked, isTrue);
    expect(sink.events.any((event) => event.eventType == 'gatt_release_confirmed'), isFalse);
    expect(sink.events.any((event) => event.eventType == 'teardown_completed' && event.source == 'dart' && event.connectionGeneration == 1), isFalse);
  });

  for (final idempotent in [false, true]) {
    test('${idempotent ? 'idempotent success event' : 'foreign trace confirmation'} cannot prove this release', () async {
      final platform = ActivePlatform();
      final ble = source(platform);
      await prepare(ble);
      final command = expectLater(ble.writeCommand(open), throwsA(isA<ProvisioningException>()));
      await until(() => platform.nativeRequest != null);
      final released = expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
      await until(() => platform.rawRequested);
      platform.retiring = false;
      platform.diagnostic.add({
        'traceId': idempotent ? platform.trace : 'foreign-trace',
        'eventType': idempotent ? 'controlled_reconnect_already_released' : 'controlled_release_disconnect_confirmed',
        'resultCode': idempotent ? 'idempotent_release' : 'retired_gatt_disconnected',
        'connectionGeneration': 1,
        'gattInstanceId': 1,
      });
      await released;
      await command;
      expect(ble.nativeReleaseBlocked, isTrue);
    });
  }

  test('late held Future after timeout cannot reopen the gate or launch another release', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await prepare(ble);
    platform.releaseBarrier = Completer<void>();
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    platform.releaseBarrier!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(ble.nativeReleaseBlocked, isTrue);
    await expectLater(ble.scan().toList(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.disconnect(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    expect(platform.generation, 1);
  });

  test('foreground same-generation replacement cannot inherit pairing permission or be cleaned up', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await prepare(ble);
    platform.instance = 2;
    await ble.resumeDiscovery(owner);
    expect(ble.isConnected, isFalse);
    await expectLater(ble.writeCommand(open), code(ProvisioningErrorCode.bleGattNotReady));
    await ble.endSession(owner);
    expect(platform.connected, isTrue);
    expect(platform.publicReleaseOwners, isEmpty);
    expect(platform.bondsInitiated, 0);
  });

  test('foreground cannot adopt native ready state without a known instance', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.connect(PreflightBlePlatform.advertisement);
    await ble.resumeDiscovery(owner);
    expect(ble.isConnected, isFalse);
    expect(platform.connected, isTrue);
    await ble.endSession(owner);
    expect(platform.publicReleaseOwners, isEmpty);
  });

  test('write-time external bonding rejected by system never starts a fallback bond', () async {
    final platform = PreflightBlePlatform();
    platform.beforePublicWrite = () {
      platform.beforePublicWrite = null;
      platform.bond = NativeBondState.bonding;
    };
    final ble = source(platform);
    final rejected = expectLater(prepare(ble), code(ProvisioningErrorCode.blePairingRejected));
    await until(() => platform.publicWriteOwners.isNotEmpty);
    platform.bond = NativeBondState.notBonded;
    await rejected;
    expect(platform.bondsInitiated, 0);
    expect(platform.protectedWrites, 0);
    expect(platform.requests, isEmpty);
    expect(platform.generation, 1);
  });
}
