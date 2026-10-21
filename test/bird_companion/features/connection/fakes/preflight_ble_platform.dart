import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/pairing_preflight_platform.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/pairing_preflight_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

/// App-side transport simulation, never proof of Android/BlueZ behavior.
class PreflightBlePlatform implements BirdBoxBlePlatform, BirdBoxPairingPlatform, BirdBoxPairingPreflightPlatform {
  static const client = 'a870bcb1-d423-4d66-96f7-f809ce786543';
  static const device = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
  static final advertisement = BirdBoxAdvertisement(localName: 'BirdBox-82F41C9E', serviceUuids: {BleProtocolConstants.serviceUuid}, platformDeviceId: 'opaque-test-device', rssi: -45);
  final scan = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final notify = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final diagnostic = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final disconnectEvents = StreamController<BleDisconnectEvent>.broadcast(sync: true);
  final requests = <Map<String, dynamic>>[];
  final calls = <String>[];
  final missingServiceGenerations = <int>{};
  final responseErrors = <String>[];
  final _reads = <String, int>{};
  final _incoming = BleFragmentReassembler();
  final _secureIncoming = BleFragmentReassembler();
  bool boardOld = false, capability = true, connected = false;
  bool dropResponses = false, dropConfirmation = false, omitDisconnect = false, advertise = true;
  bool mismatchedFreshDevice = false, resetAgain = false, releaseFails = false, staleCallbacks = false;
  bool staleDuringScan = false;
  bool omitCharacteristicInventory = false;
  bool snapshotFails = false;
  bool retiring = false;
  NativeGattReleaseSnapshot? lastRelease;
  BleAdapterState adapter = BleAdapterState.enabled;
  String? nativeRequest;
  int instance = 1;
  void Function()? beforePublicWrite;
  ProvisioningException? publicWriteError, controlledReleaseError;
  ProvisioningException? securityPreparationError;
  Completer<void>? releaseBarrier;
  final publicWriteOwners = <(int, int)>[];
  final publicReleaseOwners = <(int, int)>[];
  int ownershipGenerationOffset = 0;
  int snapshotGenerationOffset = 0;
  NativeBondState bond = NativeBondState.notBonded;
  int generation = 0, bondsInitiated = 0, protectedWrites = 0;
  Map<String, dynamic>? _secureRequest;
  Map<String, dynamic> fixture(String name) => jsonDecode(File('test/contracts/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

  @override
  Stream<Map<String, dynamic>> get scanResults => scan.stream;
  @override
  Stream<Map<String, dynamic>> get notifications => notify.stream;
  @override
  Stream<Map<String, dynamic>> get diagnostics => diagnostic.stream;
  @override
  Stream<BleDisconnectEvent> get disconnects => disconnectEvents.stream;
  @override
  Future<BleScanEnvironment> readScanEnvironment() async => BleScanEnvironment(permission: BleScanPermissionState.granted, adapter: adapter);
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<void> startScan(Duration timeout, {required String scanSessionId}) async {
    calls.add('scan');
    if (staleDuringScan) scheduleMicrotask(() => loseLink(oldGeneration: generation));
    if (advertise) {
      scheduleMicrotask(
        () => scan.add({
          'deviceId': advertisement.platformDeviceId,
          'localName': advertisement.localName,
          'serviceUuids': [BleProtocolConstants.serviceUuid],
          'rssi': -45,
        }),
      );
    }
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<int> connect(String platformDeviceId, {required String traceId}) async {
    generation++;
    calls.add('connect:$generation');
    connected = true;
    _reads.clear();
    if (staleCallbacks && generation > 1) scheduleMicrotask(() => disconnectEvents.add(BleDisconnectEvent(reason: 'link_lost', gattStatus: 19, unexpected: true, connectionGeneration: generation - 1)));
    return generation;
  }

  void loseLink({String reason = 'link_lost', int status = 19, int? oldGeneration}) {
    if (oldGeneration == null) connected = false;
    disconnectEvents.add(BleDisconnectEvent(reason: reason, gattStatus: status, unexpected: true, connectionGeneration: oldGeneration ?? generation, gattInstanceId: instance));
  }

  @override
  Future<void> disconnect() async {
    if (connected) loseLink(reason: 'requested', status: 0);
  }

  @override
  Future<void> disconnectOwned(String? requestId, BlePairingReady? ready, int? connectionGeneration) => disconnect();
  @override
  Future<int> requestMtu(int mtu) async => 517;
  @override
  Future<void> setNotify(String characteristicUuid, {required bool enabled}) async {
    calls.add('notify:$characteristicUuid');
  }

  @override
  Future<Uint8List> readCharacteristic(String characteristicUuid) async {
    calls.add('read:$characteristicUuid');
    final info = fixture('ble-device-info.rc4.json');
    if (capability) (info['capabilities'] as Map)['pairing_preflight_v1'] = true;
    if (mismatchedFreshDevice && generation > 1) info['device_id'] = 'bbx-00000000000000000000000000000000';
    final message = characteristicUuid == BleProtocolConstants.deviceInfoCharacteristicUuid ? info : fixture('ble-network-status.rc4.json');
    final frames = const BleFragmentCodec().fragment(Uint8List.fromList(utf8.encode(jsonEncode(message))), messageId: characteristicUuid == BleProtocolConstants.deviceInfoCharacteristicUuid ? 8 : 9, maximumFragmentBytes: 512);
    final index = _reads[characteristicUuid] ?? 0;
    _reads[characteristicUuid] = (index + 1) % frames.length;
    return frames[index];
  }

  @override
  Future<NativeBondSnapshot> getNativeBondState(int connectionGeneration, {required String platformDeviceId}) async {
    calls.add('bond:$generation');
    return NativeBondSnapshot(state: bond, connectionGeneration: generation + snapshotGenerationOffset, gattInstanceId: instance);
  }

  @override
  Future<PublicGattSnapshot> getGattOwnershipState(int connectionGeneration) async {
    calls.add('ownership:$generation');
    if (snapshotFails) throw const ProvisioningException(code: ProvisioningErrorCode.blePairingPreflightUnavailable, retryable: false);
    return PublicGattSnapshot(
      connectionGeneration: generation + ownershipGenerationOffset,
      gattInstanceId: connected && !retiring ? instance : 0,
      connected: connected && !retiring,
      linkReady: connected && !retiring,
      retiring: retiring,
      lastRelease: lastRelease,
      inflightRequest: nativeRequest,
      hasCharacteristicInventory: !omitCharacteristicInventory,
      characteristicUuids: {...BleProtocolConstants.characteristicUuids, if (!missingServiceGenerations.contains(generation)) BleProtocolConstants.pairingPreflightCharacteristicUuid},
    );
  }

  @override
  Future<void> prepareControlledReconnect({required String requestId, required int connectionGeneration, required int gattInstanceId, required String reason}) async {
    publicReleaseOwners.add((connectionGeneration, gattInstanceId));
    if (connectionGeneration != generation || gattInstanceId != instance) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOwnerMismatch, retryable: false);
    if (retiring) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: false);
    if (controlledReleaseError != null) {
      if (controlledReleaseError!.code == ProvisioningErrorCode.bleGattReleaseUnconfirmed) connected = false;
      throw controlledReleaseError!;
    }
    calls.add('release:$connectionGeneration');
    if (releaseFails) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattRecoveryFailed, retryable: false);
    await releaseBarrier?.future;
    await disconnect();
  }

  @override
  Future<void> writePairingPreflight({required String requestId, required int connectionGeneration, required int gattInstanceId, required Uint8List fragmentBytes}) async {
    beforePublicWrite?.call();
    publicWriteOwners.add((connectionGeneration, gattInstanceId));
    if (connectionGeneration != generation || gattInstanceId != instance) throw const ProvisioningException(code: ProvisioningErrorCode.bleGattOwnerMismatch, retryable: false);
    if (retiring) throw const ProvisioningException(code: ProvisioningErrorCode.bleOperationBusy, retryable: false);
    if (publicWriteError != null) throw publicWriteError!;
    if (bond != NativeBondState.notBonded) throw const ProvisioningException(code: ProvisioningErrorCode.bleBondStateNotNone, retryable: false);
    if (missingServiceGenerations.contains(generation)) throw const ProvisioningException(code: ProvisioningErrorCode.pairingPreflightCommandUnsupported, retryable: false, diagnosticMessage: 'native_preflight_characteristic_missing');
    final message = _incoming.add(Uint8List.fromList(fragmentBytes));
    if (message == null) return;
    final request = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
    message.fillRange(0, message.length, 0);
    requests.add(request);
    final type = request['type'];
    calls.add(type as String);
    if (dropResponses) return;
    if (responseErrors.isNotEmpty) {
      emit({
        'type': 'error',
        'request_id': requestId,
        'ok': false,
        'error': {'code': responseErrors.removeAt(0), 'message': 'FAKE_ONLY', 'retryable': true, 'retry_after_ms': 0},
      });
    } else if (type == 'prepare_system_pairing') {
      emit({
        'type': 'pairing_preflight_result',
        'request_id': requestId,
        'ok': true,
        'payload': {
          'action': boardOld ? 'reset_required' : 'none',
          'board_bond_before': {'paired': boardOld, 'bonded': boardOld},
          if (boardOld) ...{'reset_token': 'FAKE_RESET_TOKEN_ONLY', 'expires_in_ms': 15000},
        },
      });
    } else {
      if (!dropConfirmation) {
        emit({
          'type': 'pairing_reset_scheduled',
          'request_id': requestId,
          'ok': true,
          'payload': {
            'action': 'remove_scheduled',
            'prepare_request_id': (request['payload'] as Map)['prepare_request_id'],
            'board_bond_before': {'paired': true, 'bonded': true},
            'disconnect_expected': true,
            'remove_after_ms': 750,
          },
        });
      }
      boardOld = resetAgain;
      if (!omitDisconnect) loseLink();
    }
  }

  void emit(Map<String, dynamic> envelope, {int? fromGeneration, bool metadata = true}) {
    final frames = const BleFragmentCodec().fragment(Uint8List.fromList(utf8.encode(jsonEncode(envelope))), messageId: 70 + requests.length, maximumFragmentBytes: 512);
    for (final frame in frames) {
      notify.add({
        'characteristicUuid': BleProtocolConstants.networkStatusCharacteristicUuid,
        'value': frame,
        if (metadata) ...{'connectionGeneration': fromGeneration ?? generation, 'gattGeneration': instance},
      });
    }
  }

  @override
  Future<BlePairingReady> preparePairing(String requestId, String commandType) async {
    calls.add('secure:$commandType');
    if (securityPreparationError != null) throw securityPreparationError!;
    if (bond == NativeBondState.notBonded) {
      bondsInitiated++;
      bond = NativeBondState.bonded;
    }
    return BlePairingReady(requestId: requestId, attemptId: requestId, connectionGeneration: generation, gattGeneration: 1, mtu: 517);
  }

  @override
  Future<void> beginSecurityWrite(String requestId, {required String commandType}) async {}
  @override
  Future<BlePairingReady> recoverPairing(String requestId) => throw UnimplementedError();
  @override
  Future<bool> awaitSecurityReady(String requestId) => throw UnimplementedError();
  @override
  Future<void> beginSecurityRetry(String requestId) async {}
  @override
  Future<void> writeWithResponse(String characteristicUuid, Uint8List value) async {
    protectedWrites++;
    final message = _secureIncoming.add(Uint8List.fromList(value));
    if (message != null) _secureRequest = jsonDecode(utf8.decode(message)) as Map<String, dynamic>;
  }

  @override
  Future<void> markSecurityWriteSent(String requestId) async {
    final request = _secureRequest!;
    emit({
      'protocol_version': '1.0-rc4',
      'type': request['type'] == 'open_pairing' ? 'pairing_opened' : 'network_status',
      'request_id': requestId,
      'device_id': device,
      'ok': true,
      'payload': request['type'] == 'open_pairing' ? {'pairing_code_mode': 'fixed_dev', 'code_expires_in': 0, 'attempts_remaining': 5} : fixture('ble-network-status.rc4.json')['payload'],
    });
  }

  @override
  Future<void> completeSecurityWrite(String requestId, {required String responseType}) async {}
  @override
  Future<void> failSecurityWrite(String requestId, {required String errorCode}) async {}
  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<void> dispose() async {
    await scan.close();
    await notify.close();
    await diagnostic.close();
    await disconnectEvents.close();
  }
}
