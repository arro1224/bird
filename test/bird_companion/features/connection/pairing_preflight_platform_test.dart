import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bird_companion/birdbox_ble/methods');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, Object?> snapshot({bool connected = true, int generation = 4, int instance = 2, bool preparing = false, bool retiring = false, String? request}) => {
    'connected': connected,
    'linkReady': connected,
    'connectionGeneration': generation,
    'gattInstanceId': connected ? instance : 0,
    'discoveryState': connected ? 'ready' : 'absent',
    'inflightRequest': request,
    'preparing': preparing,
    'retiring': retiring,
  };
  Matcher code(ProvisioningErrorCode expected) => throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', expected));

  Map<String, Object?> releaseRecord() => {'connectionGeneration': 4, 'gattInstanceId': 2, 'traceId': 'old-trace', 'state': 'confirmed', 'resultCode': 'retired_gatt_disconnected', 'disconnectObserved': true, 'closeCompleted': true};

  test('fresh adapter recovers confirmed release from native snapshot without calling disconnect', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return snapshot(connected: false)..['lastRelease'] = releaseRecord();
    });
    await MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'new-page', connectionGeneration: 4, gattInstanceId: 2, reason: 'cleanup');
    expect(calls, ['getGattOwnershipState']);
  });

  test('release snapshot rejects malformed records and false confirmation', () async {
    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('connectionGeneration', 0),
      const MapEntry('gattInstanceId', '2'),
      const MapEntry('state', 'unknown'),
      const MapEntry('resultCode', 'idempotent_release'),
      const MapEntry('disconnectObserved', false),
      const MapEntry('closeCompleted', false),
      const MapEntry('traceId', ''),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => snapshot(connected: false)..['lastRelease'] = (releaseRecord()..[entry.key] = entry.value));
      await expectLater(MethodChannelBirdBoxBlePlatform().getGattOwnershipState(4), throwsA(isA<ProvisioningProtocolException>()));
    }
  });

  test('foreign or unconfirmed native release cannot clear absent-owner gate', () async {
    for (final record in [
      releaseRecord()..['gattInstanceId'] = 3,
      releaseRecord()..addAll({'state': 'unconfirmed', 'resultCode': 'disconnect_callback_missing', 'disconnectObserved': false}),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => snapshot(connected: false)..['lastRelease'] = record);
      await expectLater(MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'new-page', connectionGeneration: 4, gattInstanceId: 2, reason: 'cleanup'), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    }
  });

  test('native disconnect stream preserves generation and instance for release correlation', () async {
    const events = EventChannel('bird_companion/birdbox_ble/disconnects');
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success({'reason': 'requested', 'gattStatus': 0, 'unexpected': false, 'connectionGeneration': 4, 'gattInstanceId': 2});
        },
      ),
    );
    final result = await MethodChannelBirdBoxBlePlatform().disconnects.first;
    expect(result.connectionGeneration, 4);
    expect(result.gattInstanceId, 2);
  });

  test('malformed native disconnect instance is rejected instead of losing correlation', () async {
    const events = EventChannel('bird_companion/birdbox_ble/disconnects');
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          sink.success({'reason': 'requested', 'gattStatus': 0, 'unexpected': false, 'connectionGeneration': 4, 'gattInstanceId': '2'});
        },
      ),
    );
    await expectLater(MethodChannelBirdBoxBlePlatform().disconnects.first, throwsA(isA<ProvisioningProtocolException>()));
  });

  test('production adapter delegates stale reset to native connect without a preceding disconnect', () async {
    expect(MethodChannelBirdBoxBlePlatform(), isA<BirdBoxNativeConnectReset>());
    final platform = _NativeResetPlatform();
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(source.dispose);
    var completed = false;
    final connecting = source.connect(BirdBoxAdvertisement(localName: 'BirdBox-Test', serviceUuids: const {}, platformDeviceId: 'opaque', rssi: -40)).then((_) => completed = true);
    await platform.called.future;
    expect(completed, isFalse);
    expect(source.isConnected, isFalse);
    expect(platform.disconnectCalls, 0);
    platform.ready.complete(7);
    await connecting;
    expect(source.isConnected, isTrue);
    expect(platform.disconnectCalls, 0);
  });

  test('connect preserves native release-unconfirmed code and blocks subsequent scan and dial', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'gatt_release_unconfirmed'));
    await expectLater(MethodChannelBirdBoxBlePlatform().connect('opaque', traceId: 'test'), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    final platform = _NativeResetPlatform();
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(source.dispose);
    final ad = BirdBoxAdvertisement(localName: 'BirdBox-Test', serviceUuids: const {}, platformDeviceId: 'opaque', rssi: -40);
    final connect = expectLater(source.connect(ad), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await platform.called.future;
    platform.ready.completeError(const ProvisioningException(code: ProvisioningErrorCode.bleGattReleaseUnconfirmed, retryable: false));
    await connect;
    expect(source.nativeReleaseBlocked, isTrue);
    await expectLater(source.connect(ad), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    await expectLater(source.scan().toList(), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    expect(platform.disconnectCalls, 0);
  });

  for (final state in {'not_bonded': NativeBondState.notBonded, 'bonding': NativeBondState.bonding, 'bonded': NativeBondState.bonded}.entries) {
    test('bond ABI sends deviceId and decodes ${state.key}', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getNativeBondState' ? state.key : snapshot();
      });
      final result = await MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque-handle');
      expect(result.state, state.value);
      expect(result.connectionGeneration, 4);
      expect(result.gattInstanceId, 2);
      expect(calls.map((c) => c.method), ['getGattOwnershipState', 'getNativeBondState', 'getGattOwnershipState']);
      expect(calls[1].arguments, {'deviceId': 'opaque-handle'});
      expect(calls.first.arguments, isNull);
    });
  }

  test('bond query rejects GATT replacement between real native reads', () async {
    var reads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'getNativeBondState' ? 'not_bonded' : snapshot(instance: ++reads == 1 ? 2 : 3));
    await expectLater(MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque'), code(ProvisioningErrorCode.bleGattOwnerMismatch));
  });

  test('ownership ABI permits absent inventory without claiming 0007 is missing', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => snapshot());
    final value = await MethodChannelBirdBoxBlePlatform().getGattOwnershipState(4);
    expect(value.connected, isTrue);
    expect(value.hasCharacteristicInventory, isFalse);
    expect(value.characteristicUuids, isEmpty);
  });

  test('write ABI sends exact value bytes and null is ATT completion only', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getGattOwnershipState' ? snapshot() : null;
    });
    final bytes = Uint8List.fromList([0x42, 0x42, 1]);
    await MethodChannelBirdBoxBlePlatform().writePairingPreflight(requestId: 'local-only', connectionGeneration: 4, gattInstanceId: 2, fragmentBytes: bytes);
    expect(calls.last.method, 'writePairingPreflight');
    expect(calls.last.arguments, {'value': bytes, 'expectedConnectionGeneration': 4, 'expectedGattInstanceId': 2});
  });

  test('wrong owner or native pairing prevents public write before bytes leave Dart', () async {
    for (final state in [snapshot(generation: 5), snapshot(instance: 3), snapshot(preparing: true), snapshot(request: 'active')]) {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return state;
      });
      await expectLater(MethodChannelBirdBoxBlePlatform().writePairingPreflight(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, fragmentBytes: Uint8List(3)), throwsA(isA<ProvisioningException>()));
      expect(calls, ['getGattOwnershipState']);
    }
  });

  test('controlled release verifies absent snapshot without waiting for nonexistent event', () async {
    final calls = <MethodCall>[];
    var retired = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getGattOwnershipState') return snapshot(connected: !retired);
      retired = true;
      return null;
    });
    await MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, reason: 'pairing_reset');
    expect(calls.map((c) => c.method), ['getGattOwnershipState', 'prepareControlledReconnect', 'getGattOwnershipState']);
    expect(calls[1].arguments, {'expectedConnectionGeneration': 4, 'expectedGattInstanceId': 2});
  });

  test('unobserved absent GATT is unconfirmed; foreign generation is never retired', () async {
    for (final generation in [4, 5]) {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'getGattOwnershipState' ? snapshot(connected: false, generation: generation) : null;
      });
      final release = MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, reason: 'pairing_reset');
      if (generation == 4) {
        await expectLater(release, code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
      } else {
        await expectLater(release, code(ProvisioningErrorCode.bleGattOwnerMismatch));
      }
      expect(calls, ['getGattOwnershipState']);
    }
  });

  test('observed confirmed release is idempotent without issuing another native release', () async {
    var released = false, releases = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getGattOwnershipState') return snapshot(connected: !released);
      releases++;
      released = true;
      return null;
    });
    final platform = MethodChannelBirdBoxBlePlatform();
    for (var i = 0; i < 2; i++) {
      await platform.prepareControlledReconnect(requestId: 'r', connectionGeneration: 4, gattInstanceId: 2, reason: 'test');
    }
    expect(releases, 1);
  });

  test('null release receipt cannot hide still-live or replaced native GATT', () async {
    for (final generation in [4, 5]) {
      var retired = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getGattOwnershipState') return snapshot(generation: retired ? generation : 4);
        retired = true;
        return null;
      });
      await expectLater(MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, reason: 'pairing_reset'), code(ProvisioningErrorCode.bleGattRecoveryFailed));
    }
  });

  test('missing native method fails explicitly without guessed NONE state', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw MissingPluginException());
    await expectLater(MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque'), code(ProvisioningErrorCode.blePairingPreflightUnavailable));
  });

  test('native missing-characteristic error is identifiable and secret free', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getGattOwnershipState') return snapshot();
      throw PlatformException(code: 'pairing_preflight_unsupported', message: 'FAKE_RESET_TOKEN_ONLY', details: {'reset_token': 'FAKE_RESET_TOKEN_ONLY'});
    });
    try {
      await MethodChannelBirdBoxBlePlatform().writePairingPreflight(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, fragmentBytes: Uint8List(3));
      fail('Expected error');
    } on ProvisioningException catch (error) {
      expect(error.code, ProvisioningErrorCode.pairingPreflightCommandUnsupported);
      expect(error.diagnosticMessage, 'native_preflight_characteristic_missing');
      expect(error.toString(), isNot(contains('FAKE_RESET_TOKEN_ONLY')));
    }
  });

  test('native errors retain stable codes without arbitrary secret text', () async {
    for (final entry in {
      'PAIRING_PREFLIGHT_INVALID_PEER': ProvisioningErrorCode.pairingPreflightInvalidPeer,
      'bond_state_unknown': ProvisioningErrorCode.bleBondStateUnknown,
      'bluetooth_unavailable': ProvisioningErrorCode.bluetoothUnavailable,
      'invalid_request': ProvisioningErrorCode.invalidRequest,
      'ble_gatt_operation_failed': ProvisioningErrorCode.bleGattOperationFailed,
      'gatt_owner_mismatch': ProvisioningErrorCode.bleGattOwnerMismatch,
      'bond_state_not_none': ProvisioningErrorCode.bleBondStateNotNone,
      'gatt_release_unconfirmed': ProvisioningErrorCode.bleGattReleaseUnconfirmed,
    }.entries) {
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: entry.key, message: 'FAKE_RESET_TOKEN_ONLY'));
      try {
        await MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque');
        fail('Expected error');
      } on ProvisioningException catch (error) {
        expect(error.code, entry.value);
        expect(error.diagnosticMessage, isNull);
      }
    }
  });

  test('invalid native snapshot and unknown bond value fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'connected': true});
    await expectLater(MethodChannelBirdBoxBlePlatform().getGattOwnershipState(4), throwsA(isA<ProvisioningProtocolException>()));
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'getNativeBondState' ? 'unknown' : snapshot());
    await expectLater(MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque'), throwsA(isA<ProvisioningProtocolException>()));
  });

  test('retiring snapshot prevents public write and duplicate release despite absent GATT', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return snapshot(connected: false, retiring: true);
    });
    final platform = MethodChannelBirdBoxBlePlatform();
    expect((await platform.getGattOwnershipState(4)).retiring, isTrue);
    calls.clear();
    await expectLater(platform.writePairingPreflight(requestId: 'old', connectionGeneration: 4, gattInstanceId: 2, fragmentBytes: Uint8List(3)), code(ProvisioningErrorCode.bleOperationBusy));
    await expectLater(platform.prepareControlledReconnect(requestId: 'old', connectionGeneration: 4, gattInstanceId: 2, reason: 'test'), code(ProvisioningErrorCode.bleOperationBusy));
    expect(calls, ['getGattOwnershipState', 'getGattOwnershipState']);
  });

  test('retiring field is optional for old ABI but malformed and contradictory values fail closed', () async {
    final platform = MethodChannelBirdBoxBlePlatform();
    messenger.setMockMethodCallHandler(channel, (_) async => snapshot()..remove('retiring'));
    expect((await platform.getGattOwnershipState(4)).retiring, isFalse);
    for (final value in [null, 'true', 1, true]) {
      messenger.setMockMethodCallHandler(channel, (_) async => snapshot()..['retiring'] = value);
      await expectLater(platform.getGattOwnershipState(4), throwsA(isA<ProvisioningProtocolException>()));
    }
  });

  test('controlled release does not complete before native held Future completes', () async {
    final held = Completer<void>(), requested = Completer<void>();
    var released = false, completed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getGattOwnershipState') return snapshot(connected: !released);
      requested.complete();
      await held.future;
      released = true;
      return null;
    });
    final pending = MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'r', connectionGeneration: 4, gattInstanceId: 2, reason: 'test').then((_) => completed = true);
    await requested.future;
    expect(completed, isFalse);
    held.complete();
    await pending;
    expect(completed, isTrue);
  });

  test('release timeout stays unconfirmed on repeated call even if native would answer idempotent success', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getGattOwnershipState') return snapshot(connected: attempts == 0);
      if (++attempts == 1) throw PlatformException(code: 'gatt_release_unconfirmed', message: 'FAKE_RESET_TOKEN_ONLY');
      return null;
    });
    final platform = MethodChannelBirdBoxBlePlatform();
    for (var i = 0; i < 2; i++) {
      await expectLater(platform.prepareControlledReconnect(requestId: 'r', connectionGeneration: 4, gattInstanceId: 2, reason: 'test'), code(ProvisioningErrorCode.bleGattReleaseUnconfirmed));
    }
    expect(attempts, 1);
  });

  for (final method in ['writePairingPreflight', 'prepareControlledReconnect']) {
    for (final replaceInstance in [false, true]) {
      test('$method atomic guard rejects ${replaceInstance ? 'instance' : 'generation'} replacement after snapshot', () async {
        var sideEffects = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getGattOwnershipState') return snapshot();
          final args = call.arguments as Map;
          expect(args['expectedConnectionGeneration'], 4);
          expect(args['expectedGattInstanceId'], 2);
          final actualGeneration = replaceInstance ? 4 : 5, actualInstance = replaceInstance ? 3 : 2;
          if (args['expectedConnectionGeneration'] != actualGeneration || args['expectedGattInstanceId'] != actualInstance) throw PlatformException(code: 'gatt_owner_mismatch');
          sideEffects++;
          return null;
        });
        final platform = MethodChannelBirdBoxBlePlatform();
        await expectLater(
          method == 'writePairingPreflight'
              ? platform.writePairingPreflight(requestId: 'r', connectionGeneration: 4, gattInstanceId: 2, fragmentBytes: Uint8List(3))
              : platform.prepareControlledReconnect(requestId: 'r', connectionGeneration: 4, gattInstanceId: 2, reason: 'test'),
          code(ProvisioningErrorCode.bleGattOwnerMismatch),
        );
        expect(sideEffects, 0);
      });
    }
  }
}

class _NativeResetPlatform extends Fake implements BirdBoxBlePlatform, BirdBoxNativeConnectReset {
  final called = Completer<void>(), ready = Completer<int>();
  int disconnectCalls = 0;
  @override
  Stream<Map<String, dynamic>> get notifications => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get diagnostics => const Stream.empty();
  @override
  Stream<BleDisconnectEvent> get disconnects => const Stream.empty();
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<void> stopScan() async {}
  @override
  Future<int> connect(String platformDeviceId, {required String traceId}) async {
    called.complete();
    return ready.future;
  }

  @override
  Future<int> requestMtu(int mtu) async => 517;
  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> dispose() async {}
}
