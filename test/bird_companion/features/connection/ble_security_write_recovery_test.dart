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
    expect(cleanup.errorCode, 'StateError');
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

final class _RecoveryPlatform implements BirdBoxBlePlatform {
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

final class _RecordingConnectionDiagnosticSink implements BleConnectionDiagnosticSink {
  final List<BleConnectionDiagnosticEvent> events = [];

  @override
  Future<void> record(BleConnectionDiagnosticEvent event) async {
    events.add(event);
  }
}
