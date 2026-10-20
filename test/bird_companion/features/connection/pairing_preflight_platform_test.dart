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
  Map<String, Object?> snapshot({bool connected = true, int generation = 4, int instance = 2, bool preparing = false, String? request}) => {
    'connected': connected,
    'linkReady': connected,
    'connectionGeneration': generation,
    'gattInstanceId': connected ? instance : 0,
    'discoveryState': connected ? 'ready' : 'absent',
    'inflightRequest': request,
    'preparing': preparing,
  };
  Matcher code(ProvisioningErrorCode expected) => throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', expected));

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

  for (final state in {'not_bonded': NativeBondState.notBonded, 'bonding': NativeBondState.bonding, 'bonded': NativeBondState.bonded}.entries) {
    test('e160043ef bond ABI sends deviceId and decodes ${state.key}', () async {
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
    await expectLater(MethodChannelBirdBoxBlePlatform().getNativeBondState(4, platformDeviceId: 'opaque'), code(ProvisioningErrorCode.bleGattNotReady));
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
    expect(calls.last.arguments, {'value': bytes});
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
    expect(calls[1].arguments, isNull);
  });

  test('peer-reset already-closed GATT is idempotent; foreign generation is never retired', () async {
    for (final generation in [4, 5]) {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return snapshot(connected: false, generation: generation);
      });
      final release = MethodChannelBirdBoxBlePlatform().prepareControlledReconnect(requestId: 'request', connectionGeneration: 4, gattInstanceId: 2, reason: 'pairing_reset');
      if (generation == 4) {
        await release;
      } else {
        await expectLater(release, code(ProvisioningErrorCode.bleGattRecoveryFailed));
      }
      expect(calls, ['getGattOwnershipState']);
    }
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
