import 'dart:async';
import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_critical_event_policy.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_pairing_progress.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/preflight_ble_platform.dart';

void main() {
  const client = PreflightBlePlatform.client;
  final advertisement = PreflightBlePlatform.advertisement;
  PlatformBirdBoxBleDataSource source(PreflightBlePlatform platform, {_Sink? diagnostics}) {
    final result = PlatformBirdBoxBleDataSource(
      platform: platform,
      connectionDiagnosticSink: diagnostics,
      preflightResponseTimeout: const Duration(milliseconds: 60),
      freshAdvertisementTimeout: const Duration(milliseconds: 120),
      preparationTimeout: const Duration(seconds: 2),
    );
    addTearDown(result.dispose);
    return result;
  }

  Future<void> until(bool Function() predicate) async {
    for (var i = 0; i < 200; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('Expected transport stage was not reached');
  }

  Matcher errorCode(ProvisioningErrorCode code) => throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', code));
  const open = BleCommandRequest(type: BleCommandType.openPairing, requestId: '550e8400-e29b-41d4-a716-446655440000', clientId: client);

  test('fresh pairing prepares publicly and starts system bond only on explicit open', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    expect(platform.requests.map((r) => r['type']), ['prepare_system_pairing']);
    expect(platform.bondsInitiated, 0);
    expect(platform.protectedWrites, 0);
    expect(platform.calls.where((call) => call.startsWith('notify:')), ['notify:6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000']);
    expect(platform.calls.indexOf('bond:1'), lessThan(platform.calls.indexWhere((c) => c.startsWith('notify:'))));
    final window = await ble.writeCommand(open);
    expect(window.type, ProvisioningEventType.pairingOpened);
    expect(platform.bondsInitiated, 1);
  });

  test('asymmetric reset acknowledges then disconnects synchronously and reconnects once', () async {
    final platform = PreflightBlePlatform()..boardOld = true;
    final sink = _Sink();
    final ble = source(platform, diagnostics: sink);
    final disconnects = <void>[];
    final subscription = ble.disconnects.listen(disconnects.add);
    addTearDown(subscription.cancel);
    final stages = <BlePairingStage>[];
    final progress = ble.pairingProgress.listen((p) => stages.add(p.stage));
    addTearDown(progress.cancel);
    final info = await ble.prepareConnection(advertisement, clientId: client);
    expect(info.deviceId, PreflightBlePlatform.device);
    expect(platform.requests.map((r) => r['type']), ['prepare_system_pairing', 'confirm_pairing_reset', 'prepare_system_pairing']);
    expect(platform.generation, 2);
    // A matched real peer disconnect plus native absence needs no second release.
    expect(platform.calls.where((c) => c.startsWith('release:')), isEmpty);
    expect(disconnects, isEmpty);
    expect(platform.bondsInitiated, 0);
    expect(
      stages,
      containsAllInOrder([BlePairingStage.preflightPending, BlePairingStage.resetConfirming, BlePairingStage.resetPending, BlePairingStage.waitingFreshAdvertisement, BlePairingStage.freshGattReconnecting, BlePairingStage.preflightPending]),
    );
    expect(jsonEncode(sink.events.map((e) => e.toJson()).toList()), isNot(contains('FAKE_RESET_TOKEN_ONLY')));
    await ble.writeCommand(open);
    expect(platform.bondsInitiated, 1);
  });

  test('disconnect before reset acknowledgement is terminal rather than expected', () async {
    final platform = PreflightBlePlatform()
      ..boardOld = true
      ..dropConfirmation = true;
    final ble = source(platform);
    await expectLater(ble.prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattOperationFailed));
    expect(platform.generation, 1);
    expect(platform.calls, isNot(contains('scan')));
    expect(platform.bondsInitiated, 0);
  });

  test('a later ordinary status19 still reaches subscribers', () async {
    final platform = PreflightBlePlatform()..boardOld = true;
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    final lost = ble.disconnects.first;
    platform.loseLink();
    await lost;
    expect(ble.isConnected, isFalse);
    expect(platform.bondsInitiated, 0);
  });

  test('old generation callbacks cannot terminate fresh reconnect', () async {
    final platform = PreflightBlePlatform()
      ..boardOld = true
      ..staleCallbacks = true;
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    platform.loseLink(oldGeneration: 1);
    expect(ble.isConnected, isTrue);
    await ble.writeCommand(open);
    expect(platform.bondsInitiated, 1);
  });

  for (final code in ['PAIRING_PREFLIGHT_BUSY', 'PAIRING_PREFLIGHT_EXPIRED']) {
    test('$code retries preparation once after release without bonding', () async {
      final platform = PreflightBlePlatform()..responseErrors.add(code);
      final ble = source(platform);
      await ble.prepareConnection(advertisement, clientId: client);
      expect(platform.generation, 2);
      expect(platform.requests, hasLength(2));
      expect(platform.bondsInitiated, 0);
    });
  }
  test('busy retry budget is finite', () async {
    final platform = PreflightBlePlatform()..responseErrors.addAll(['PAIRING_PREFLIGHT_BUSY', 'PAIRING_PREFLIGHT_BUSY']);
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightBusy));
    expect(platform.requests, hasLength(2));
    expect(platform.generation, 2);
  });
  for (final code in [ProvisioningErrorCode.pairingPreflightInvalidPeer, ProvisioningErrorCode.pairingPreflightConfirmationRejected, ProvisioningErrorCode.requestIdConflict]) {
    test('${code.wireValue} cannot trigger reset, rescan or bond fallback', () async {
      final platform = PreflightBlePlatform()..responseErrors.add(code.wireValue);
      await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(code));
      expect(platform.requests, hasLength(1));
      expect(platform.calls, isNot(contains('scan')));
      expect(platform.protectedWrites, 0);
      expect(platform.bondsInitiated, 0);
    });
  }

  test('unanswered preflight times out without any createBond fallback', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleCommandResponseTimeout));
    expect(platform.generation, 1);
    expect(platform.protectedWrites, 0);
  });

  test('expected disconnect and advertisement both have bounded waits', () async {
    final platform = PreflightBlePlatform()
      ..boardOld = true
      ..omitDisconnect = true;
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattRecoveryFailed));
    expect(platform.generation, 1);
    final absent = PreflightBlePlatform()
      ..boardOld = true
      ..advertise = false;
    await expectLater(source(absent).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattRecoveryFailed));
    expect(absent.generation, 1);
  });

  test('cancellation and stale page ownership cannot produce late writes', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final ble = source(platform);
    final owner = ble.claimSession();
    final result = ble.prepareConnection(advertisement, clientId: client);
    final failed = expectLater(result, errorCode(ProvisioningErrorCode.bleSessionEnded));
    await until(() => platform.requests.isNotEmpty);
    await ble.endSession(owner);
    await failed;
    final newer = ble.claimSession();
    platform.dropResponses = false;
    await ble.prepareConnection(advertisement, clientId: client);
    await ble.endSession(owner);
    expect(ble.ownsSession(newer), isTrue);
    expect(ble.isConnected, isTrue);
    expect(platform.bondsInitiated, 0);
  });

  test('duplicate connect and protected command during preflight are rejected', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final ble = source(platform);
    final owner = ble.claimSession();
    final pending = ble.prepareConnection(advertisement, clientId: client);
    final failed = expectLater(pending, errorCode(ProvisioningErrorCode.bleSessionEnded));
    await until(() => platform.requests.isNotEmpty);
    await expectLater(ble.prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(ble.writeCommand(open), errorCode(ProvisioningErrorCode.bleOperationBusy));
    await ble.endSession(owner);
    await failed;
  });

  test('missing optional service refreshes once and never bonds to bypass it', () async {
    final platform = PreflightBlePlatform()..missingServiceGenerations.add(1);
    await source(platform).prepareConnection(advertisement, clientId: client);
    expect(platform.generation, 2);
    expect(platform.requests, hasLength(1));
    final unsupported = PreflightBlePlatform()..missingServiceGenerations.addAll([1, 2]);
    await expectLater(source(unsupported).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightCommandUnsupported));
    expect(unsupported.requests, isEmpty);
    expect(unsupported.bondsInitiated, 0);
  });

  test('native ABI without inventory refreshes a missing 0007 once from write error', () async {
    final platform = PreflightBlePlatform()
      ..omitCharacteristicInventory = true
      ..missingServiceGenerations.add(1);
    await source(platform).prepareConnection(advertisement, clientId: client);
    expect(platform.generation, 2);
    expect(platform.requests, hasLength(1));
    expect(platform.bondsInitiated, 0);
    final absent = PreflightBlePlatform()
      ..omitCharacteristicInventory = true
      ..missingServiceGenerations.addAll([1, 2]);
    await expectLater(source(absent).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightCommandUnsupported));
    expect(absent.generation, 2);
    expect(absent.requests, isEmpty);
    expect(absent.bondsInitiated, 0);
  });

  test('board command unsupported remains terminal when native has no inventory', () async {
    final platform = PreflightBlePlatform()
      ..omitCharacteristicInventory = true
      ..responseErrors.add('PAIRING_PREFLIGHT_COMMAND_UNSUPPORTED');
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightCommandUnsupported));
    expect(platform.generation, 1);
    expect(platform.calls, isNot(contains('scan')));
  });

  test('foreground sync reuses identical owned GATT and preserves explicit pairing permit', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    await ble.pauseDiscovery(owner);
    await ble.resumeDiscovery(owner);
    expect(ble.isConnected, isTrue);
    expect(platform.generation, 1);
    expect(platform.bondsInitiated, 0);
    await ble.writeCommand(open);
    expect(platform.bondsInitiated, 1);
  });

  test('foreground sync detects native loss without callback and never auto-reconnects', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    final lost = ble.disconnects.first;
    platform.connected = false;
    await ble.resumeDiscovery(owner);
    await lost;
    expect(ble.isConnected, isFalse);
    expect(platform.generation, 1);
    expect(platform.bondsInitiated, 0);
    await expectLater(ble.writeCommand(open), errorCode(ProvisioningErrorCode.bleGattNotReady));
  });

  test('foreground sync invalidates foreign native generation without retiring it', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    final before = platform.calls.length;
    platform.ownershipGenerationOffset = 1;
    await ble.resumeDiscovery(owner);
    expect(ble.isConnected, isFalse);
    expect(platform.connected, isTrue);
    expect(platform.calls.skip(before), ['ownership:1']);
    expect(platform.bondsInitiated, 0);
  });

  test('foreground snapshot failure clears stale ready state and surfaces typed failure', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    platform.snapshotFails = true;
    await expectLater(ble.resumeDiscovery(owner), errorCode(ProvisioningErrorCode.blePairingPreflightUnavailable));
    expect(ble.isConnected, isFalse);
    expect(platform.bondsInitiated, 0);
  });

  test('foreground resume during public request preserves the owned attempt', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final ble = source(platform);
    final owner = ble.claimSession();
    final pending = ble.prepareConnection(advertisement, clientId: client);
    final failed = expectLater(pending, errorCode(ProvisioningErrorCode.bleSessionEnded));
    await until(() => platform.requests.isNotEmpty);
    final before = platform.calls.length;
    await ble.resumeDiscovery(owner);
    expect(platform.calls.length, before);
    await ble.endSession(owner);
    await failed;
  });

  test('legacy unbonded boxes stop clearly while bonded legacy boxes bypass preflight', () async {
    final old = PreflightBlePlatform()..capability = false;
    await expectLater(source(old).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightCommandUnsupported));
    expect(old.requests, isEmpty);
    final bonded = PreflightBlePlatform()
      ..capability = false
      ..bond = NativeBondState.bonded;
    final ble = source(bonded);
    await ble.prepareConnection(advertisement, clientId: client);
    await ble.writeCommand(open);
    expect(bonded.requests, isEmpty);
    expect(bonded.bondsInitiated, 0);
  });

  test('fresh identity mismatch and repeated reset fail without deleting a second peer', () async {
    final wrong = PreflightBlePlatform()
      ..boardOld = true
      ..mismatchedFreshDevice = true;
    await expectLater(source(wrong).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.deviceIdMismatch));
    expect(wrong.requests.where((r) => r['type'] == 'confirm_pairing_reset'), hasLength(1));
    final again = PreflightBlePlatform()
      ..boardOld = true
      ..resetAgain = true;
    await expectLater(source(again).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.pairingPreflightConfirmationRejected));
    expect(again.requests.where((r) => r['type'] == 'confirm_pairing_reset'), hasLength(1));
  });

  test('release failure never proceeds to a second connect', () async {
    final platform = PreflightBlePlatform()
      ..missingServiceGenerations.add(1)
      ..releaseFails = true;
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattRecoveryFailed));
    expect(platform.generation, 1);
  });

  test('read-only reconnect cannot consume permission to start pairing', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    await expectLater(ble.writeCommand(const BleCommandRequest(type: BleCommandType.getNetworkStatus, requestId: '550e8400-e29b-41d4-a716-446655440002', clientId: client)), errorCode(ProvisioningErrorCode.authorizationRequired));
    expect(platform.bondsInitiated, 0);
    await ble.writeCommand(open);
    expect(platform.bondsInitiated, 1);
  });

  test('old release callbacks during scanning cannot cancel the logical transaction', () async {
    final platform = PreflightBlePlatform()
      ..boardOld = true
      ..staleDuringScan = true;
    await source(platform).prepareConnection(advertisement, clientId: client);
    expect(platform.generation, 2);
  });

  test('notification metadata and request IDs must match the current public request', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final ble = source(platform);
    var ready = false;
    final result = ble.prepareConnection(advertisement, clientId: client).then((info) {
      ready = true;
      return info;
    });
    await until(() => platform.requests.isNotEmpty);
    final id = platform.requests.single['request_id'];
    Map<String, dynamic> response(Object? requestId) => {
      'type': 'pairing_preflight_result',
      'request_id': requestId,
      'ok': true,
      'payload': {
        'action': 'none',
        'board_bond_before': {'paired': false, 'bonded': false},
      },
    };
    platform.emit(response(id), fromGeneration: 0);
    platform.emit(response(id), metadata: false);
    platform.emit(response('old-request'));
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    platform.emit(response(id));
    await result;
    expect(ready, isTrue);
    expect(platform.bondsInitiated, 0);
  });

  test('native snapshot generation mismatch cannot start a preflight write', () async {
    final platform = PreflightBlePlatform()..snapshotGenerationOffset = -1;
    await expectLater(source(platform).prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattOwnerMismatch));
    expect(platform.requests, isEmpty);
  });

  test('existing native bonding is observed without another bond request', () async {
    final platform = PreflightBlePlatform()..bond = NativeBondState.bonding;
    final timer = Timer(const Duration(milliseconds: 5), () => platform.bond = NativeBondState.bonded);
    addTearDown(timer.cancel);
    await source(platform).prepareConnection(advertisement, clientId: client);
    expect(platform.requests, isEmpty);
    expect(platform.bondsInitiated, 0);
  });

  test('cancelling while waiting for fresh advertisement releases the scan', () async {
    final platform = PreflightBlePlatform()
      ..boardOld = true
      ..advertise = false;
    final ble = source(platform);
    final owner = ble.claimSession();
    final operation = ble.prepareConnection(advertisement, clientId: client);
    final failed = expectLater(operation, errorCode(ProvisioningErrorCode.bleSessionEnded));
    await until(() => platform.calls.contains('scan'));
    await ble.endSession(owner);
    await failed;
    platform.advertise = true;
    ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    expect(ble.isConnected, isTrue);
  });

  test('lost bond cannot consume the same preparation for a second system attempt', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    await ble.writeCommand(open);
    platform.bond = NativeBondState.notBonded;
    await expectLater(ble.writeCommand(open), errorCode(ProvisioningErrorCode.bleBondLost));
    expect(platform.bondsInitiated, 1);
  });

  test('request retention joins public prepare and confirm by logical attempt', () {
    final a = {'operation_name': 'pairing_preflight', 'request_id': 'prepare', 'attempt_id': 'transaction'};
    final b = {'operation_name': 'pairing_preflight', 'request_id': 'confirm', 'attempt_id': 'transaction'};
    expect(BleCriticalEventPolicy.requestKey(a, 'flow'), BleCriticalEventPolicy.requestKey(b, 'flow'));
    expect(BleCriticalEventPolicy.requestKey({'request_id': 'business', 'attempt_id': 'transaction'}, 'flow'), isNot(BleCriticalEventPolicy.requestKey(a, 'flow')));
  });

  test('replacing a live prepared connection waits for controlled release first', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    await ble.prepareConnection(advertisement, clientId: client);
    expect(platform.calls.indexOf('release:1'), lessThan(platform.calls.indexOf('connect:2')));
    expect(platform.bondsInitiated, 0);
  });

  test('native-reset platform retains stale client for native connect park barrier', () async {
    final platform = _NativeResetPreflightPlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    platform.releaseGate = Completer<void>();
    var completed = false;
    final replacement = ble.prepareConnection(advertisement, clientId: client).then((_) => completed = true);
    await until(() => platform.calls.contains('native-owned-reset'));
    expect(completed, isFalse);
    expect(platform.calls.where((call) => call.startsWith('release:')), isEmpty);
    expect(platform.generation, 1);
    platform.releaseGate!.complete();
    await replacement;
    expect(platform.generation, 2);
    expect(platform.bondsInitiated, 0);
  });

  for (final changeGeneration in [false, true]) {
    test('public owner mismatch leaves replacement ${changeGeneration ? 'generation' : 'instance'} untouched through cleanup', () async {
      final platform = PreflightBlePlatform();
      final sink = _Sink();
      platform.beforePublicWrite = () {
        platform.beforePublicWrite = null;
        if (changeGeneration) {
          platform.generation++;
        } else {
          platform.instance++;
        }
      };
      final ble = source(platform, diagnostics: sink);
      await expectLater(ble.prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattOwnerMismatch));
      expect(ble.isConnected, isFalse);
      await ble.disconnect();
      await ble.dispose();
      expect(platform.connected, isTrue);
      expect(platform.publicReleaseOwners, isEmpty);
      expect(platform.requests, isEmpty);
      expect(platform.bondsInitiated, 0);
      final failed = sink.events.lastWhere((e) => e.eventType == 'pairing_preflight_failed');
      expect(failed.errorCode, 'BLE_GATT_OWNER_MISMATCH');
    });
  }

  test('cleanup after another first error still uses original atomic owner and preserves first error', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final sink = _Sink();
    final ble = source(platform, diagnostics: sink);
    final result = ble.prepareConnection(advertisement, clientId: client);
    final failed = expectLater(result, errorCode(ProvisioningErrorCode.bleCommandResponseTimeout));
    await until(() => platform.requests.isNotEmpty);
    platform.instance = 2;
    await failed;
    expect(platform.publicReleaseOwners, isEmpty);
    expect(platform.connected, isTrue);
    await ble.disconnect();
    expect(platform.publicReleaseOwners, isEmpty);
    final finalized = sink.events.lastWhere((e) => e.eventType == 'teardown_failed' && e.failureDetails != null);
    expect(jsonEncode(finalized.failureDetails), contains('BLE_GATT_OWNER_MISMATCH'));
    expect(finalized.errorCode, 'BLE_COMMAND_RESPONSE_TIMEOUT');
  });

  for (final initial in [NativeBondState.bonded, NativeBondState.bonding]) {
    test('write-time ${initial.name} follows existing system bond without another createBond', () async {
      final platform = PreflightBlePlatform();
      platform.beforePublicWrite = () {
        platform.beforePublicWrite = null;
        platform.bond = initial;
      };
      final ble = source(platform);
      final preparing = ble.prepareConnection(advertisement, clientId: client);
      await until(() => platform.publicWriteOwners.isNotEmpty);
      if (initial == NativeBondState.bonding) {
        expect(ble.isConnected, isTrue);
        platform.bond = NativeBondState.bonded;
      }
      await preparing;
      expect(platform.requests, isEmpty);
      expect(platform.generation, 1);
      await ble.writeCommand(open);
      expect(platform.bondsInitiated, 0);
    });
  }

  test('unconfirmed release blocks scan, connect and cleanup without automatic retry', () async {
    final platform = PreflightBlePlatform()..missingServiceGenerations.add(1);
    platform.controlledReleaseError = const ProvisioningException(code: ProvisioningErrorCode.bleGattReleaseUnconfirmed, retryable: false);
    final ble = source(platform);
    await expectLater(ble.prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    await expectLater(ble.connect(advertisement), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.scan().toList(), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.disconnect(), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, [(1, 1)]);
    expect(platform.bondsInitiated, 0);
  });

  test('foreground retiring clears ready and blocks new work without another release', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    final owner = ble.claimSession();
    await ble.prepareConnection(advertisement, clientId: client);
    platform.retiring = true;
    await expectLater(ble.resumeDiscovery(owner), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(ble.isConnected, isFalse);
    await expectLater(ble.scan().toList(), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.connect(advertisement), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(ble.disconnect(), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.publicReleaseOwners, isEmpty);
    expect(platform.bondsInitiated, 0);
  });

  test('controlled release in flight blocks scan and connect until held completion', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    platform.releaseBarrier = Completer<void>();
    final replacement = ble.prepareConnection(advertisement, clientId: client);
    await until(() => platform.publicReleaseOwners.isNotEmpty);
    await expectLater(ble.scan().toList(), errorCode(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(ble.connect(advertisement), errorCode(ProvisioningErrorCode.bleOperationBusy));
    expect(platform.generation, 1);
    expect(platform.publicReleaseOwners, [(1, 1)]);
    platform.releaseBarrier!.complete();
    await replacement;
    expect(platform.generation, 2);
    expect(ble.isConnected, isTrue);
  });

  test('retiring during public preparation cannot write or release an absent parked GATT', () async {
    final platform = PreflightBlePlatform()..retiring = true;
    final ble = source(platform);
    await expectLater(ble.prepareConnection(advertisement, clientId: client), errorCode(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(ble.isConnected, isFalse);
    expect(platform.publicWriteOwners, isEmpty);
    expect(platform.publicReleaseOwners, isEmpty);
    expect(platform.bondsInitiated, 0);
  });

  test('idle GATT after security preparation failure uses atomically owned release', () async {
    final platform = PreflightBlePlatform();
    final ble = source(platform);
    await ble.prepareConnection(advertisement, clientId: client);
    platform.securityPreparationError = const ProvisioningException(code: ProvisioningErrorCode.blePairingRejected, retryable: false);
    await expectLater(ble.writeCommand(open), errorCode(ProvisioningErrorCode.blePairingRejected));
    await ble.disconnect();
    expect(platform.connected, isFalse);
    expect(platform.publicReleaseOwners, [(1, 1)]);
    expect(platform.bondsInitiated, 0);
  });
}

final class _NativeResetPreflightPlatform extends PreflightBlePlatform implements BirdBoxNativeConnectReset {
  Completer<void>? releaseGate;
  @override
  Future<int> connect(String platformDeviceId, {required String traceId}) async {
    if (connected) {
      calls.add('native-owned-reset');
      await releaseGate?.future;
    }
    return super.connect(platformDeviceId, traceId: traceId);
  }
}

final class _Sink implements BleConnectionDiagnosticSink {
  final events = <BleConnectionDiagnosticEvent>[];
  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async => events.add(event);
}
