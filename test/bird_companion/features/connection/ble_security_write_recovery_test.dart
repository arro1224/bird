import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = BleCommandRequest(
    type: BleCommandType.getNetworkStatus,
    requestId: '550e8400-e29b-41d4-a716-446655440000',
    clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
  );

  test('no-callback recovery retries the same request id and bytes exactly once', () async {
    final platform = _RecoveryPlatform(securityFailures: 1);
    final dataSource = await _connectedDataSource(platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.writeCommand(request);
    await _waitForWrites(platform, 2);
    _emitNetworkStatus(platform);
    _emitNetworkStatus(platform); // A duplicate response cannot complete the request twice.
    await result;

    expect(platform.beginRequestIds, [request.requestId]);
    expect(platform.retryRequestIds, [request.requestId]);
    expect(platform.writeAttempts, hasLength(2));
    expect(
      platform.writeAttempts[1],
      orderedEquals(platform.writeAttempts[0]),
    );
    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.completeSecurityWriteCalls, 1);
    expect(platform.failSecurityWriteCalls, 0);
  });

  test('a second unencrypted result terminates without another recovery loop', () async {
    final platform = _RecoveryPlatform(securityFailures: 2);
    final dataSource = await _connectedDataSource(platform);
    addTearDown(dataSource.dispose);

    await expectLater(
      dataSource.writeCommand(request),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.bleEncryptedRetryFailed,
        ),
      ),
    );

    expect(platform.writeAttempts, hasLength(2));
    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.retryRequestIds, [request.requestId]);
    expect(platform.failSecurityWriteCalls, 1);
  });

  test('cleanup failure is diagnostic only and cannot replace the first root cause', () async {
    final diagnostics = _RecordingConnectionDiagnosticSink();
    final platform = _RecoveryPlatform(
      securityFailures: 1,
      securityReadyError: const ProvisioningException(
        code: ProvisioningErrorCode.blePairingTimeout,
        retryable: true,
      ),
      failCleanup: true,
    );
    final dataSource = await _connectedDataSource(
      platform,
      diagnostics: diagnostics,
    );
    addTearDown(dataSource.dispose);

    await expectLater(
      dataSource.writeCommand(request),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.blePairingTimeout,
        ),
      ),
    );

    final cleanup = diagnostics.events.singleWhere(
      (event) => event.eventType == 'security_cleanup_failed',
    );
    expect(cleanup.terminalOutcome, 'BLE_PAIRING_TIMEOUT');
    expect(cleanup.cleanupOutcome, 'failed');
    expect(cleanup.errorCode, 'BLE_PAIRING_TIMEOUT');
    final details = cleanup.failureDetails!;
    expect((details['first_terminal_error'] as Map)['error_code'], 'BLE_PAIRING_TIMEOUT');
    final secondary = (details['secondary_errors'] as List).single as Map;
    expect(secondary['runtime_type'], 'StateError');
    expect(secondary['trigger_method'], 'failSecurityWrite');
    expect(secondary['stack_trace_available'], true);
    expect(secondary['stack_trace'], contains('ble_security_write_recovery_test.dart:'));
    expect(jsonEncode(details), isNot(contains('simulated cleanup failure')));
  });

  test('engine dispose releases an active command once and is idempotent', () async {
    final platform = _RecoveryPlatform(securityFailures: 0);
    final dataSource = await _connectedDataSource(platform);

    final result = dataSource.writeCommand(request);
    final resultExpectation = expectLater(
      result,
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.bleGattOperationFailed,
        ),
      ),
    );
    await _waitForWrites(platform, 1);
    await dataSource.dispose();
    await dataSource.dispose();
    await resultExpectation;
    expect(platform.failSecurityWriteCalls, 1);
    expect(platform.completeSecurityWriteCalls, 0);
    expect(platform.disposeCalls, 1);
  });

  test('native terminal rejection wins over a later timeout and cleanup failure', () async {
    final diagnostics = _RecordingConnectionDiagnosticSink();
    final gate = Completer<bool>();
    final platform = _RecoveryPlatform(securityFailures: 1, failCleanup: true)..pendingSecurityReady = gate;
    final dataSource = await _connectedDataSource(platform, diagnostics: diagnostics);
    addTearDown(dataSource.dispose);
    final result = dataSource.writeCommand(request);
    while (platform.awaitSecurityReadyCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    platform.emitTerminal(request.requestId, generation: 1);
    await Future<void>.delayed(Duration.zero);
    gate.completeError(const ProvisioningException(code: ProvisioningErrorCode.blePairingTimeout, retryable: true));
    try {
      await result;
      fail('expected rejection');
    } on ProvisioningException catch (error) {
      expect(error.code, ProvisioningErrorCode.blePairingRejected);
      final first = error.failureDetails!['first_terminal_error'] as Map;
      expect(first['trigger_method'], 'native.security_write_terminal');
      expect(first['previous_bond_state'], 'bonding');
      expect(first['current_bond_state'], 'not_bonded');
      final secondary = error.failureDetails!['secondary_errors'] as List;
      expect(secondary.map((e) => (e as Map)['error_code']), contains('BLE_PAIRING_TIMEOUT'));
      expect(secondary.map((e) => (e as Map)['runtime_type']), contains('StateError'));
    }
    expect(diagnostics.events.lastWhere((e) => e.eventType == 'command_failed').errorCode, 'BLE_PAIRING_REJECTED');
  });

  test('stale native terminal cannot fail a current request and success cleanup is secondary', () async {
    final diagnostics = _RecordingConnectionDiagnosticSink();
    final platform = _RecoveryPlatform(securityFailures: 0)..failSuccessCleanup = true;
    final dataSource = await _connectedDataSource(platform, diagnostics: diagnostics);
    addTearDown(dataSource.dispose);
    final result = dataSource.writeCommand(request);
    await _waitForWrites(platform, 1);
    platform.emitTerminal(request.requestId, generation: 99);
    platform.emitTerminal('foreign', generation: 1);
    await Future<void>.delayed(Duration.zero);
    _emitNetworkStatus(platform);
    await result;
    final cleanup = diagnostics.events.singleWhere((e) => e.eventType == 'security_cleanup_failed');
    expect(cleanup.terminalOutcome, 'success');
    expect(cleanup.failureDetails!['first_terminal_error'], isNull);
    expect((cleanup.failureDetails!['secondary_errors'] as List).single['trigger_method'], 'completeSecurityWrite');
    expect(platform.failSecurityWriteCalls, 0);
    expect(diagnostics.events.where((e) => e.eventType == 'command_failed'), isEmpty);
  });

  test('secure preparation blocks writes and uses the rebuilt MTU', () async {
    final platform = _PreparedPlatform()..preparation = Completer<BlePairingReady>();
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final result = source.writeCommand(request);
    await Future<void>.delayed(Duration.zero);
    expect(platform.writeAttempts, isEmpty);
    expect(platform.beginRequestIds, [request.requestId]);
    platform.preparation!.complete(platform.ready(request.requestId, 23));
    await platform.sent.future;
    expect(platform.writeAttempts.length, greaterThan(1));
    expect(platform.writeAttempts.every((packet) => packet.length <= 20), isTrue);
    _emitNetworkStatus(platform);
    await result;
    expect(platform.notifyCalls, 2); // Only the initial unprotected connection.
    expect(platform.mtuCalls, 1); // Preparation owns the rebuilt native MTU.
  });

  test('large MTU frames obey the 512-byte Android attribute bound', () async {
    final platform = _PreparedPlatform()..preparedMtu = 517;
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    // Transport boundary fixture only; this synthetic payload is not a board command contract.
    const identity = '550e8400-e29b-41d4-a716-446655440000';
    final result = source.writeCommand(BleCommandRequest(type: BleCommandType.getNetworkStatus, requestId: identity, clientId: request.clientId, payload: {'synthetic_test_padding': 'x' * 1000}));
    await platform.sent.future;
    expect(platform.writeAttempts.length, greaterThan(2));
    expect(platform.writeAttempts.every((frame) => frame.length <= 512), isTrue);
    final assembler = BleFragmentReassembler();
    Uint8List? complete;
    for (final frame in platform.writeAttempts) {
      complete = assembler.add(Uint8List.fromList(frame));
    }
    expect((jsonDecode(utf8.decode(complete!)) as Map)['request_id'], identity);
    _emitNetworkStatus(platform);
    await result;
  });

  test('native engine destruction completes a waiting command as a lifecycle error', () async {
    final platform = _RecoveryPlatform(securityFailures: 0);
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final expectation = expectLater(
      source.writeCommand(request),
      throwsA(
        isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleSessionEnded),
      ),
    );
    await _waitForWrites(platform, 1);
    platform._disconnects.add(const BleDisconnectEvent(reason: 'engine_destroyed', gattStatus: 0, unexpected: true));
    await expectation;
    expect(source.isConnected, isFalse);
    expect(platform.completeSecurityWriteCalls, 0);
  });

  test('preparation failure sends zero bytes and preserves the bond error', () async {
    final platform = _PreparedPlatform()..preparation = Completer<BlePairingReady>();
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final expectation = expectLater(source.writeCommand(request), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleBondStartFailed)));
    await Future<void>.delayed(Duration.zero);
    platform.preparation!.completeError(const ProvisioningException(code: ProvisioningErrorCode.bleBondStartFailed, retryable: true));
    await expectation;
    expect(platform.writeAttempts, isEmpty);
  });

  test('single native recovery refragments the same command at a smaller MTU', () async {
    final platform = _PreparedPlatform(failures: 1)..preparedMtu = 517;
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final result = source.writeCommand(request);
    await platform.sent.future;
    expect(platform.recoveryCalls, 1);
    final initial = platform.writeAttempts.first;
    final retry = platform.writeAttempts.skip(1).toList();
    expect(initial.length, greaterThan(20));
    expect(retry.every((packet) => packet.length <= 20), isTrue);
    final decoder = BleFragmentReassembler();
    Uint8List? decoded;
    for (final packet in retry) {
      decoded = decoder.add(packet);
    }
    final envelope = jsonDecode(utf8.decode(decoded!)) as Map;
    expect(envelope['request_id'], request.requestId);
    expect(envelope['type'], 'get_network_status');
    expect(platform.notifyCalls, 2);
    expect(platform.mtuCalls, 1);
    _emitNetworkStatus(platform);
    await result;
  });

  test('cancel while preparing names its request and rejects late readiness', () async {
    final platform = _PreparedPlatform()..preparation = Completer<BlePairingReady>();
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final owner = source.claimSession();
    final expectation = expectLater(source.writeCommand(request), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.bleGattOperationFailed)));
    await Future<void>.delayed(Duration.zero);
    await source.endSession(owner);
    expect(platform.disconnectOwners.last, request.requestId);
    platform.preparation!.complete(platform.ready(request.requestId, 23));
    await expectation;
    expect(platform.writeAttempts, isEmpty);
  });

  test('stale page owner cannot disconnect an active newer session', () async {
    final platform = _PreparedPlatform();
    final source = await _connectedDataSource(platform);
    addTearDown(source.dispose);
    final old = source.claimSession();
    final current = source.claimSession();
    final disconnects = platform.disconnectOwners.length;
    await source.endSession(old);
    expect(platform.disconnectOwners.length, disconnects);
    expect(source.ownsSession(current), isTrue);
    expect(source.isConnected, isTrue);
  });

  test('new scan compatibility facts survive source builder and persisted JSON', () async {
    final platform = _PreparedPlatform();
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(source.dispose);
    final diagnostic = source.scanDiagnostics.first;
    await source.scan(timeout: const Duration(milliseconds: 1)).drain<void>();
    final restored = BleScanDiagnosticSession.fromJson((await diagnostic).toJson());
    expect(restored.locationRequiredByApp, isFalse);
    expect(restored.locationPermissionRequiredByPlatform, isFalse);
    expect(restored.locationRequiredForDeviceCompatibility, isTrue);
    expect(restored.locationCompatibilityRule, 'huawei_mis_al00_sdk31');
    expect(restored.locationPermissionAfter, BleScanPermissionState.notRequested);
    expect(restored.locationServiceAfter, BleLocationServiceState.disabled);
  });

  test('settings departure and rescan retain one flow and distinct scan IDs', () async {
    final platform = _PreparedPlatform();
    final diagnostics = _RecordingConnectionDiagnosticSink();
    final source = PlatformBirdBoxBleDataSource(platform: platform, connectionDiagnosticSink: diagnostics);
    addTearDown(source.dispose);
    final owner = source.claimSession();
    final scans = <BleScanDiagnosticSession>[];
    final subscription = source.scanDiagnostics.listen(scans.add);
    addTearDown(subscription.cancel);
    await source.scan(timeout: const Duration(milliseconds: 1)).drain<void>();
    await source.openLocationSettings(owner);
    await source.locationSettingsReturned(owner, enabled: true);
    await source.scan(timeout: const Duration(milliseconds: 1)).drain<void>();
    expect(scans, hasLength(2));
    final first = BleScanDiagnosticSession.fromJson(scans.first.toJson());
    final second = BleScanDiagnosticSession.fromJson(scans.last.toJson());
    expect(second.flowId, first.flowId);
    expect(second.scanSessionId, isNot(first.scanSessionId));
    expect(second.previousScanSessionId, first.scanSessionId);
    expect(second.scanTrigger, 'location_settings_return');
    final settings = diagnostics.events.where((e) => e.eventType.startsWith('location_settings'));
    expect(settings.map((e) => e.eventType), ['location_settings_open_requested', 'location_settings_opened', 'location_settings_returned']);
    expect(settings.every((e) => e.flowId == first.flowId), isTrue);
  });
}

Future<PlatformBirdBoxBleDataSource> _connectedDataSource(
  _RecoveryPlatform platform, {
  BleConnectionDiagnosticSink? diagnostics,
}) async {
  final dataSource = PlatformBirdBoxBleDataSource(
    platform: platform,
    connectionDiagnosticSink: diagnostics,
    scanSessionIdFactory: () => 'ble-14-trace',
  );
  final advertisement = advertisementFromPlatform({
    'deviceId': 'opaque-device',
    'localName': 'BirdBox-TEST',
    'serviceUuids': [BleProtocolConstants.serviceUuid],
    'rssi': -40,
    'addressHash': List.filled(64, 'a').join(),
  });
  await dataSource.scan(timeout: const Duration(milliseconds: 1)).drain<void>();
  await dataSource.connect(advertisement);
  await dataSource.subscribeRequiredNotifications();
  return dataSource;
}

Future<void> _waitForWrites(_RecoveryPlatform platform, int count) async {
  for (var i = 0; i < 50 && platform.writeAttempts.length < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(platform.writeAttempts.length, greaterThanOrEqualTo(count));
}

void _emitNetworkStatus(_RecoveryPlatform platform) {
  final response = Uint8List.fromList(
    utf8.encode(
      File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync(),
    ),
  );
  final packets = const BleFragmentCodec().fragment(
    response,
    messageId: 31,
    maximumFragmentBytes: 512,
  );
  for (final packet in packets) {
    platform.emitNotification(
      BleProtocolConstants.networkStatusCharacteristicUuid,
      packet,
    );
  }
}

class _RecoveryPlatform implements BirdBoxBlePlatform {
  _RecoveryPlatform({
    required this.securityFailures,
    this.securityReadyError,
    this.failCleanup = false,
  });

  int securityFailures;
  final Object? securityReadyError;
  final bool failCleanup;
  final _scan = StreamController<Map<String, dynamic>>.broadcast();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _diagnostics = StreamController<Map<String, dynamic>>.broadcast();
  final _disconnects = StreamController<BleDisconnectEvent>.broadcast();
  final List<String> beginRequestIds = [];
  final List<String> retryRequestIds = [];
  final List<Uint8List> writeAttempts = [];
  int awaitSecurityReadyCalls = 0;
  int completeSecurityWriteCalls = 0;
  int failSecurityWriteCalls = 0;
  int disposeCalls = 0;
  Completer<bool>? pendingSecurityReady;
  bool failSuccessCleanup = false;

  void emitTerminal(String requestId, {required int generation}) => _diagnostics.add({
    'traceId': 'ble-14-trace',
    'eventType': 'security_write_terminal',
    'requestId': requestId,
    'connectionGeneration': generation,
    'terminalOutcome': 'ble_pairing_rejected',
    'securityPhase': 'bonding',
    'previousBondState': 'bonding',
    'actualBondState': 'not_bonded',
    'attemptId': 'native-attempt',
  });

  @override
  Stream<Map<String, dynamic>> get scanResults => _scan.stream;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  @override
  Stream<Map<String, dynamic>> get diagnostics => _diagnostics.stream;
  @override
  Stream<BleDisconnectEvent> get disconnects => _disconnects.stream;

  void emitNotification(String uuid, Uint8List value) {
    _notifications.add({'characteristicUuid': uuid, 'value': value});
  }

  @override
  Future<BleScanEnvironment> readScanEnvironment() async => const BleScanEnvironment.unknown();
  @override
  Future<bool> ensurePermissions() async => true;
  @override
  Future<void> startScan(
    Duration timeout, {
    required String scanSessionId,
  }) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<int> connect(String platformDeviceId, {required String traceId}) async => 1;
  @override
  Future<void> disconnect() async {}
  @override
  Future<int> requestMtu(int mtu) async => 517;
  @override
  Future<Uint8List> readCharacteristic(String characteristicUuid) => throw UnimplementedError();
  @override
  Future<void> setNotify(
    String characteristicUuid, {
    required bool enabled,
  }) async {}

  @override
  Future<void> writeWithResponse(
    String characteristicUuid,
    Uint8List value,
  ) async {
    writeAttempts.add(Uint8List.fromList(value));
    if (securityFailures > 0) {
      securityFailures -= 1;
      throw const ProvisioningException(
        code: ProvisioningErrorCode.authorizationRequired,
        retryable: true,
      );
    }
  }

  @override
  Future<void> beginSecurityWrite(
    String requestId, {
    required String commandType,
  }) async {
    beginRequestIds.add(requestId);
  }

  @override
  Future<bool> awaitSecurityReady(String requestId) async {
    awaitSecurityReadyCalls += 1;
    if (pendingSecurityReady != null) return pendingSecurityReady!.future;
    final error = securityReadyError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<void> beginSecurityRetry(String requestId) async {
    retryRequestIds.add(requestId);
  }

  @override
  Future<void> markSecurityWriteSent(String requestId) async {}

  @override
  Future<void> completeSecurityWrite(
    String requestId, {
    required String responseType,
  }) async {
    completeSecurityWriteCalls += 1;
    if (failSuccessCleanup) throw StateError('private completion cleanup');
  }

  @override
  Future<void> failSecurityWrite(
    String requestId, {
    required String errorCode,
  }) async {
    failSecurityWriteCalls += 1;
    if (failCleanup) throw StateError('simulated cleanup failure');
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _scan.close();
    await _notifications.close();
    await _diagnostics.close();
    await _disconnects.close();
  }
}

class _PreparedPlatform extends _RecoveryPlatform implements BirdBoxPairingPlatform {
  _PreparedPlatform({int failures = 0}) : super(securityFailures: failures);
  Completer<BlePairingReady>? preparation;
  final sent = Completer<void>();
  int preparedMtu = 23, recoveryCalls = 0, mtuCalls = 0, notifyCalls = 0;
  final disconnectOwners = <String?>[];
  @override
  Future<BleScanEnvironment> readScanEnvironment() async => BleScanEnvironment.fromPlatform({
    'permissionGranted': true,
    'adapterState': 'enabled',
    'locationRequiredByApp': false,
    'locationPermissionRequiredByPlatform': false,
    'locationRequiredForDeviceCompatibility': true,
    'locationCompatibilityRule': 'huawei_mis_al00_sdk31',
    'locationPermission': 'not_requested',
    'locationService': 'disabled',
  });
  BlePairingReady ready(String requestId, int mtu) => BlePairingReady(requestId: requestId, attemptId: 'stable-attempt', connectionGeneration: 1, gattGeneration: 2 + recoveryCalls, mtu: mtu);
  @override
  Future<BlePairingReady> preparePairing(String requestId, String commandType) async {
    beginRequestIds.add(requestId);
    return preparation == null ? ready(requestId, preparedMtu) : await preparation!.future;
  }

  @override
  Future<BlePairingReady> recoverPairing(String requestId) async {
    recoveryCalls++;
    return ready(requestId, 23);
  }

  @override
  Future<void> disconnectOwned(String? requestId, BlePairingReady? ready, int? connectionGeneration) async {
    disconnectOwners.add(requestId);
  }

  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<int> requestMtu(int mtu) async {
    mtuCalls++;
    return 517;
  }

  @override
  Future<void> setNotify(String uuid, {required bool enabled}) async {
    notifyCalls++;
  }

  @override
  Future<void> markSecurityWriteSent(String requestId) async {
    if (!sent.isCompleted) sent.complete();
  }
}

final class _RecordingConnectionDiagnosticSink implements BleConnectionDiagnosticSink {
  final List<BleConnectionDiagnosticEvent> events = [];

  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async {
    events.add(event);
  }
}
