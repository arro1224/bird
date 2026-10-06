import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/features/connection/data/ble/ble_fragment_codec.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_connection_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_scan_diagnostics.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  test('compact, full and malformed optional advertisements remain candidates', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitAdvertisement(_advertisement('compact'));
    platform.emitAdvertisement(_advertisement('full', companyIdentifier: 0xFFFF, manufacturerPayload: Uint8List.fromList([1, 0, 0x9E, 0x1C, 0xF4, 0x82, 1, 4])));
    platform.emitAdvertisement(_advertisement('invalid', companyIdentifier: 1, manufacturerPayload: Uint8List.fromList([9])));
    final advertisements = await result;

    expect(advertisements, hasLength(3));
    expect(advertisements.every((item) => item.hasBirdBoxService), isTrue);
    expect(advertisements[0].platformDeviceId, 'handle-compact');
    expect(advertisements[1].hasValidManufacturerExtension, isTrue);
    expect(advertisements[2].hasValidManufacturerExtension, isFalse);
  });

  test('Local Name fallback is discoverable but never becomes a trusted identity', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitAdvertisement({..._advertisement('fallback'), 'serviceUuids': <String>[]});
    final advertisement = (await result).single;

    expect(advertisement.hasValidLocalName, isTrue);
    expect(advertisement.hasBirdBoxService, isFalse);
    expect(advertisement.toString(), isNot(contains('handle-fallback')));
  });

  test('merges split Local Name and Service UUID callbacks by device handle', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);

    platform.emitAdvertisement({
      ..._advertisement('service-first'),
      'localName': '',
    });
    platform.emitAdvertisement({
      ..._advertisement('service-first'),
      'serviceUuids': <String>[],
    });
    platform.emitAdvertisement({
      ..._advertisement('name-first'),
      'serviceUuids': <String>[],
    });
    platform.emitAdvertisement({
      ..._advertisement('name-first'),
      'localName': '',
    });

    final advertisements = await result;
    expect(advertisements, hasLength(4));
    for (final advertisement in [advertisements[1], advertisements[3]]) {
      expect(advertisement.hasValidLocalName, isTrue);
      expect(advertisement.hasBirdBoxService, isTrue);
    }
  });

  test('records a secret-safe scan session with raw and filtered evidence', () async {
    final platform = _FakeBlePlatform();
    final sink = _RecordingDiagnosticSink();
    final dataSource = PlatformBirdBoxBleDataSource(
      platform: platform,
      diagnosticSink: sink,
      scanSessionIdFactory: () => 'scan-session-b7-1',
    );
    addTearDown(dataSource.dispose);
    final diagnosticFuture = dataSource.scanDiagnostics.first;

    final result = dataSource.scan(timeout: const Duration(milliseconds: 20)).toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitScanStrategy(
      event: 'strategy_started',
      index: 0,
      name: 'NULL_FILTER_LOW_LATENCY',
      generation: 1,
      reason: 'session_started',
    );
    platform.emitFiltered('non_birdbox');
    platform.emitAdvertisement({
      ..._advertisement('accepted'),
      'strategyIndex': 0,
      'strategyName': 'NULL_FILTER_LOW_LATENCY',
      'strategyGeneration': 1,
      'deviceNamePresent': true,
    });
    platform.emitScanStrategy(
      event: 'strategy_window_elapsed',
      index: 0,
      name: 'NULL_FILTER_LOW_LATENCY',
      generation: 1,
      reason: 'raw_results_observed',
      rawResultCount: 2,
      deviceNameResultCount: 1,
      candidateCount: 1,
    );
    final advertisements = await result;
    final diagnostic = await diagnosticFuture;

    expect(advertisements, hasLength(1));
    expect(diagnostic.scanSessionId, 'scan-session-b7-1');
    expect(diagnostic.permissionBefore, BleScanPermissionState.granted);
    expect(diagnostic.permissionAfter, BleScanPermissionState.granted);
    expect(diagnostic.adapterAfter, BleAdapterState.enabled);
    expect(diagnostic.rawResultCount, 2);
    expect(diagnostic.uniqueDeviceCount, 2);
    expect(diagnostic.acceptedCount, 1);
    expect(diagnostic.filteredCount, 1);
    expect(diagnostic.reasonCounts['non_birdbox'], 1);
    expect(diagnostic.firstRawResultAt, isNotNull);
    expect(diagnostic.firstCandidateAt, isNotNull);
    expect(diagnostic.endReason, BleScanEndReason.timeout);
    expect(diagnostic.scanPermissionPolicy, 'never_for_location');
    expect(diagnostic.scanFlavor, 'birdScanA');
    expect(diagnostic.packageId, 'deckers.thibault.aves.bird.scan.a');
    expect(diagnostic.buildFlavor, 'birdScanA');
    expect(diagnostic.buildType, 'debug');
    expect(diagnostic.scanStrategyFallbackEnabled, isTrue);
    expect(diagnostic.observations, hasLength(2));
    expect(diagnostic.observations.last.name, 'BirdBox-ACCEPTED');
    expect(diagnostic.observations.last.scanRecordLength, 21);
    expect(
      diagnostic.observations.last.scanRecordRedactedHex,
      '02010603030102',
    );
    expect(diagnostic.observations.last.scanRecordTruncated, isFalse);
    expect(diagnostic.observations.last.strategyIndex, 0);
    expect(diagnostic.observations.last.deviceNamePresent, isTrue);
    expect(diagnostic.strategyEvents, hasLength(2));
    expect(
      diagnostic.strategyEvents.last.switchReason,
      'raw_results_observed',
    );
    expect(diagnostic.strategyEvents.last.rawResultCount, 2);
    expect(diagnostic.toJson()['schema_version'], 3);
    expect(sink.sessions.single.toJson(), diagnostic.toJson());
    expect(diagnostic.toJson().toString(), isNot(contains('handle-accepted')));
  });

  test('preserves Android scan error code in the terminal diagnostic', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(
      platform: platform,
      scanSessionIdFactory: () => 'scan-session-b7-error',
    );
    addTearDown(dataSource.dispose);
    final diagnosticFuture = dataSource.scanDiagnostics.first;

    final result = dataSource.scan().toList();
    await Future<void>.delayed(Duration.zero);
    platform.emitScanFailure(2);

    await expectLater(
      result,
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.diagnosticMessage,
          'diagnosticMessage',
          contains('Android scan error 2'),
        ),
      ),
    );
    final diagnostic = await diagnosticFuture;
    expect(diagnostic.endReason, BleScanEndReason.platformError);
    expect(diagnostic.androidScanErrorCode, 2);
  });

  test('gives all three fallback strategies a complete default window', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    final subscription = dataSource.scan().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(platform.startedScanTimeout, const Duration(seconds: 13));

    await dataSource.stopScan();
    await subscription.cancel();
  });

  test('records permission and disabled-adapter preflight failures without starting a scan', () async {
    final platform = _FakeBlePlatform(
      permissionGranted: false,
      adapterState: BleAdapterState.disabled,
    );
    final dataSource = PlatformBirdBoxBleDataSource(
      platform: platform,
      scanSessionIdFactory: () => 'scan-session-b7-permission',
    );
    addTearDown(dataSource.dispose);
    final diagnosticFuture = dataSource.scanDiagnostics.first;

    await expectLater(
      dataSource.scan().toList(),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.bluetoothPermissionDenied,
        ),
      ),
    );
    final diagnostic = await diagnosticFuture;

    expect(diagnostic.permissionBefore, BleScanPermissionState.denied);
    expect(diagnostic.permissionAfter, BleScanPermissionState.denied);
    expect(diagnostic.adapterAfter, BleAdapterState.disabled);
    expect(diagnostic.endReason, BleScanEndReason.permissionDenied);
    expect(platform.startedScanSessionId, isNull);
  });

  test('connect negotiates MTU, reads authoritative GATT models and subscribes both notifications', () async {
    final platform = _FakeBlePlatform(negotiatedMtu: 64);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    final advertisement = advertisementFromPlatform(_advertisement('device'));
    const fragments = BleFragmentCodec();
    final deviceInfoFrames = fragments.fragment(
      File('test/contracts/fixtures/ble-device-info.rc4.json').readAsBytesSync(),
      messageId: 1,
      maximumFragmentBytes: 412,
    );
    platform.queueRead(
      BleProtocolConstants.deviceInfoCharacteristicUuid,
      [
        Uint8List.fromList(<int>[...deviceInfoFrames[0], ...deviceInfoFrames[1]]),
        ...deviceInfoFrames.skip(2),
      ],
    );
    platform.queueRead(
      BleProtocolConstants.networkStatusCharacteristicUuid,
      fragments.fragment(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsBytesSync(), messageId: 2, maximumFragmentBytes: 52),
    );

    await dataSource.connect(advertisement);
    final info = await dataSource.readDeviceInfo();
    final status = await dataSource.readNetworkStatus();
    await dataSource.subscribeRequiredNotifications();

    expect(platform.connectedHandle, 'handle-device');
    expect(platform.requestedMtu, 517);
    expect(info.deviceId, 'bbx-82f41c9e7a3d4b68a1501e21e536c649');
    expect(status.activeMode, ProvisioningNetworkMode.directAp);
    expect(platform.subscribed, {BleProtocolConstants.networkStatusCharacteristicUuid, BleProtocolConstants.scanResultsCharacteristicUuid});
  });

  test('connect performs an idempotent native teardown before every attempt', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    await dataSource.connect(
      advertisementFromPlatform(_advertisement('pre-clean')),
    );

    expect(platform.operations.take(2), [
      'disconnect',
      'connect:handle-pre-clean',
    ]);
    expect(platform.disconnectCalls, 1);
    expect(dataSource.isConnected, isTrue);
  });

  test('failed connect is fully torn down and can reconnect in the same process', () async {
    final platform = _FakeBlePlatform(connectFailuresRemaining: 1);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    final advertisement = advertisementFromPlatform(
      _advertisement('same-process'),
    );

    await expectLater(
      dataSource.connect(advertisement),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.networkInternalError,
        ),
      ),
    );
    expect(dataSource.isConnected, isFalse);

    await dataSource.connect(advertisement);

    expect(dataSource.isConnected, isTrue);
    expect(platform.connectCalls, 2);
    expect(platform.disconnectCalls, 3);
    expect(platform.operations, [
      'disconnect',
      'connect:handle-same-process',
      'disconnect',
      'disconnect',
      'connect:handle-same-process',
    ]);
  });

  test('a stale disconnect event cannot tear down the replacement connection', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    final advertisement = advertisementFromPlatform(
      _advertisement('generation'),
    );

    await dataSource.connect(advertisement);
    await dataSource.connect(advertisement);
    await Future<void>.delayed(Duration.zero);

    expect(platform.connectCalls, 2);
    expect(dataSource.isConnected, isTrue);
  });

  test('a current-generation disconnect aborts connection readiness', () async {
    final platform = _FakeBlePlatform(disconnectDuringMtu: true);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    await expectLater(
      dataSource.connect(
        advertisementFromPlatform(_advertisement('interrupted')),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.diagnosticMessage,
          'diagnosticMessage',
          contains('becoming ready'),
        ),
      ),
    );

    expect(dataSource.isConnected, isFalse);
    expect(platform.connectCalls, 1);
  });

  test('concurrent connect taps start only one platform connection', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    final advertisement = advertisementFromPlatform(
      _advertisement('single-flight'),
    );

    final first = dataSource.connect(advertisement);
    await expectLater(
      dataSource.connect(advertisement),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.networkOperationBusy,
        ),
      ),
    );
    await first;

    expect(platform.connectCalls, 1);
  });

  test('disconnect reaches native cleanup even without a connected flag', () async {
    final platform = _FakeBlePlatform();
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);

    await dataSource.disconnect();
    await dataSource.disconnect();

    expect(platform.disconnectCalls, 2);
    expect(dataSource.isConnected, isFalse);
  });

  test('uses one trace for scan, connect and secret-safe native diagnostics', () async {
    final platform = _FakeBlePlatform();
    final sink = _RecordingConnectionDiagnosticSink();
    final dataSource = PlatformBirdBoxBleDataSource(
      platform: platform,
      connectionDiagnosticSink: sink,
      scanSessionIdFactory: () => 'ble-trace-01',
    );
    addTearDown(dataSource.dispose);

    await dataSource.scan(timeout: const Duration(milliseconds: 5)).toList();
    await dataSource.connect(
      advertisementFromPlatform(_advertisement('trace-device')),
    );
    platform.emitDiagnostic({
      'traceId': 'ble-trace-01',
      'occurredAtMs': 1789520400000,
      'eventType': 'bond_state_changed',
      'manufacturer': 'vivo',
      'model': 'PD1709',
      'androidRelease': '8.1.0',
      'sdkInt': 27,
      'operationName': 'bond',
      'bondState': 'bonding',
      'resultCode': 'not_bonded_to_bonding',
    });
    await Future<void>.delayed(Duration.zero);

    expect(platform.connectedTraceId, 'ble-trace-01');
    expect(
      sink.events.map((event) => event.eventType),
      containsAll(['connect_requested', 'connect_ready', 'bond_state_changed']),
    );
    final native = sink.events.singleWhere(
      (event) => event.eventType == 'bond_state_changed',
    );
    expect(native.traceId, 'ble-trace-01');
    expect(native.source, 'android');
    expect(native.toJson().keys, isNot(contains('deviceId')));
    expect(native.toJson().toString(), isNot(contains('trace-device')));
  });

  test('write uses rc4 fragments and waits for the matching protocol response', () async {
    final platform = _FakeBlePlatform(negotiatedMtu: 64);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.getNetworkStatus,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );

    final responseFuture = dataSource.writeCommand(request);
    await Future<void>.delayed(Duration.zero);
    final responseJson = File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync();
    final packets = const BleFragmentCodec().fragment(Uint8List.fromList(utf8.encode(responseJson)), messageId: 3, maximumFragmentBytes: 52);
    for (final packet in packets) {
      platform.emitNotification(BleProtocolConstants.networkStatusCharacteristicUuid, packet);
    }
    final response = await responseFuture;

    expect(response.type, ProvisioningEventType.networkStatus);
    expect(platform.writes, isNotEmpty);
    expect(platform.writes.every((write) => write.characteristicUuid == BleProtocolConstants.provisioningCommandCharacteristicUuid), isTrue);
    final requestBytes = BleFragmentReassembler();
    Uint8List? reassembled;
    for (final write in platform.writes) {
      reassembled = requestBytes.add(write.value) ?? reassembled;
    }
    final requestJson = jsonDecode(utf8.decode(reassembled!)) as Map<String, dynamic>;
    expect(requestJson['request_id'], request.requestId);
  });

  test('first encrypted write is attempted before Android pairing is awaited', () async {
    final platform = _FakeBlePlatform(
      securityFailuresRemaining: 1,
      securityReadyError: const ProvisioningException(
        code: ProvisioningErrorCode.bleLePairingNotStarted,
        retryable: true,
      ),
    );
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.startDirectAp,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
      payload: {
        'authorization': {'type': 'pairing_session', 'value': 'REDACTED_TEST_ONLY'},
      },
    );

    await expectLater(
      dataSource.writeCommand(request),
      throwsA(isA<ProvisioningException>().having((error) => error.code, 'code', ProvisioningErrorCode.bleLePairingNotStarted)),
    );
    expect(platform.writeAttempts, hasLength(1));
    expect(platform.beginSecurityWriteCalls, 1);
    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.beginSecurityRetryCalls, 0);
    final disconnect = dataSource.disconnects.first;
    platform.emitDisconnect();
    await disconnect;
    expect(dataSource.isConnected, isFalse);
    expect(platform.writes, isEmpty);
  });

  test('security recovery rebuilds MTU and restores both notifications', () async {
    final platform = _FakeBlePlatform(
      negotiatedMtu: 64,
      securityFailuresRemaining: 1,
      gattRebuiltAfterSecurity: true,
    );
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.getNetworkStatus,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );

    final responseFuture = dataSource.writeCommand(request);
    await Future<void>.delayed(Duration.zero);
    final responseJson = File(
      'test/contracts/fixtures/ble-network-status.rc4.json',
    ).readAsStringSync();
    final packets = const BleFragmentCodec().fragment(
      Uint8List.fromList(utf8.encode(responseJson)),
      messageId: 11,
      maximumFragmentBytes: 52,
    );
    for (final packet in packets) {
      platform.emitNotification(
        BleProtocolConstants.networkStatusCharacteristicUuid,
        packet,
      );
    }
    await responseFuture;

    expect(platform.beginSecurityWriteCalls, 1);
    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.beginSecurityRetryCalls, 1);
    expect(platform.requestedMtu, 517);
    expect(platform.writes, isNotEmpty);
    expect(
      BleProtocolConstants.notifyCharacteristicUuids.every(
        (uuid) => platform.notifyEnableCounts[uuid] == 2,
      ),
      isTrue,
    );
  });

  test('GATT security failure retries the exact same request bytes once', () async {
    final platform = _FakeBlePlatform(
      securityFailuresRemaining: 1,
    );
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    const request = BleCommandRequest(
      type: BleCommandType.getNetworkStatus,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
    );

    final responseFuture = dataSource.writeCommand(request);
    await Future<void>.delayed(Duration.zero);
    final responseJson = File(
      'test/contracts/fixtures/ble-network-status.rc4.json',
    ).readAsStringSync();
    final packets = const BleFragmentCodec().fragment(
      Uint8List.fromList(utf8.encode(responseJson)),
      messageId: 12,
      maximumFragmentBytes: 52,
    );
    for (final packet in packets) {
      platform.emitNotification(
        BleProtocolConstants.networkStatusCharacteristicUuid,
        packet,
      );
    }
    await responseFuture;

    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.beginSecurityRetryCalls, 1);
    expect(platform.securityFailuresRemaining, 0);
    expect(platform.writes, isNotEmpty);
    expect(platform.writeAttempts.first.characteristicUuid, platform.writes.first.characteristicUuid);
    expect(platform.writeAttempts.first.value, orderedEquals(platform.writes.first.value));
    expect(platform.completedSecurityRequestId, request.requestId);
    expect(platform.markSecurityWriteSentCalls, 1);
  });

  test('pairing-not-started keeps the first real write as evidence', () async {
    final platform = _FakeBlePlatform(
      securityFailuresRemaining: 1,
      securityReadyError: const ProvisioningException(
        code: ProvisioningErrorCode.bleLePairingNotStarted,
        retryable: true,
        diagnosticMessage: 'platformExceptionCode=ble_le_pairing_not_started',
      ),
    );
    final sink = _RecordingConnectionDiagnosticSink();
    final dataSource = PlatformBirdBoxBleDataSource(
      platform: platform,
      connectionDiagnosticSink: sink,
    );
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();

    await expectLater(
      dataSource.writeCommand(
        const BleCommandRequest(
          type: BleCommandType.openPairing,
          requestId: '550e8400-e29b-41d4-a716-446655440001',
          clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
        ),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.diagnosticMessage,
          'diagnosticMessage',
          contains('ble_le_pairing_not_started'),
        ),
      ),
    );

    expect(platform.writeAttempts, hasLength(1));
    expect(platform.writes, isEmpty);
    expect(
      sink.events.map((event) => event.resultCode),
      containsAll([
        'failed:BLE_LE_PAIRING_NOT_STARTED',
        'BLE_LE_PAIRING_NOT_STARTED',
      ]),
    );
  });

  test('notification restore failure blocks the encrypted retry', () async {
    final platform = _FakeBlePlatform(securityFailuresRemaining: 1);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();
    platform.notifyFailureUuid = BleProtocolConstants.scanResultsCharacteristicUuid;

    await expectLater(
      dataSource.writeCommand(
        const BleCommandRequest(
          type: BleCommandType.openPairing,
          requestId: '550e8400-e29b-41d4-a716-446655440002',
          clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
        ),
      ),
      throwsA(isA<ProvisioningException>()),
    );

    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.beginSecurityRetryCalls, 0);
    expect(platform.writeAttempts, hasLength(1));
    expect(platform.writes, isEmpty);
  });

  test('encrypted retry failure is not allowed to start a second recovery', () async {
    final platform = _FakeBlePlatform(securityFailuresRemaining: 2);
    final dataSource = PlatformBirdBoxBleDataSource(platform: platform);
    addTearDown(dataSource.dispose);
    await dataSource.connect(advertisementFromPlatform(_advertisement('device')));
    await dataSource.subscribeRequiredNotifications();

    await expectLater(
      dataSource.writeCommand(
        const BleCommandRequest(
          type: BleCommandType.openPairing,
          requestId: '550e8400-e29b-41d4-a716-446655440003',
          clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
        ),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.bleEncryptedRetryFailed,
        ),
      ),
    );

    expect(platform.awaitSecurityReadyCalls, 1);
    expect(platform.beginSecurityRetryCalls, 1);
    expect(platform.writeAttempts, hasLength(2));
    expect(platform.failSecurityWriteCalls, 1);
  });
}

Map<String, dynamic> _advertisement(String suffix, {int? companyIdentifier, Uint8List? manufacturerPayload}) => {
  'deviceId': 'handle-$suffix',
  'localName': 'BirdBox-${suffix.toUpperCase()}',
  'serviceUuids': [BleProtocolConstants.serviceUuid.toUpperCase()],
  'rssi': -50,
  'addressHash': List.filled(64, suffix.codeUnitAt(0).isEven ? 'a' : 'b').join(),
  'diagnosticName': 'BirdBox-${suffix.toUpperCase()}',
  'manufacturerDataPresent': manufacturerPayload != null,
  'manufacturerDataLength': manufacturerPayload?.length ?? 0,
  'scanRecordLength': 21,
  'scanRecordSha256': List.filled(64, 'c').join(),
  'scanRecordRedactedHex': '02010603030102',
  'scanRecordTruncated': false,
  'companyIdentifier': companyIdentifier,
  'manufacturerPayload': manufacturerPayload,
};

final class _Write {
  const _Write(this.characteristicUuid, this.value);

  final String characteristicUuid;
  final Uint8List value;
}

final class _FakeBlePlatform implements BirdBoxBlePlatform {
  _FakeBlePlatform({
    this.negotiatedMtu = 23,
    this.gattRebuiltAfterSecurity = false,
    this.securityReadyError,
    this.securityFailuresRemaining = 0,
    this.permissionGranted = true,
    this.adapterState = BleAdapterState.enabled,
    this.connectFailuresRemaining = 0,
    this.disconnectDuringMtu = false,
  });

  final int negotiatedMtu;
  final bool gattRebuiltAfterSecurity;
  final Object? securityReadyError;
  String? notifyFailureUuid;
  int securityFailuresRemaining;
  final bool permissionGranted;
  final BleAdapterState adapterState;
  int connectFailuresRemaining;
  final bool disconnectDuringMtu;
  final StreamController<Map<String, dynamic>> _scan = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _notifications = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _diagnostics = StreamController.broadcast();
  final StreamController<BleDisconnectEvent> _disconnects = StreamController.broadcast();
  final Map<String, List<Uint8List>> _reads = {};
  final Set<String> subscribed = {};
  final Map<String, int> notifyEnableCounts = {};
  final List<_Write> writeAttempts = [];
  final List<_Write> writes = [];
  String? connectedHandle;
  String? connectedTraceId;
  int? requestedMtu;
  String? startedScanSessionId;
  Duration? startedScanTimeout;
  int beginSecurityWriteCalls = 0;
  int awaitSecurityReadyCalls = 0;
  int beginSecurityRetryCalls = 0;
  int markSecurityWriteSentCalls = 0;
  int failSecurityWriteCalls = 0;
  String? activeSecurityRequestId;
  String? completedSecurityRequestId;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int _nextConnectionGeneration = 0;
  int? _nativeConnectionGeneration;
  final List<String> operations = [];

  @override
  Stream<Map<String, dynamic>> get scanResults => _scan.stream;
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  @override
  Stream<Map<String, dynamic>> get diagnostics => _diagnostics.stream;
  @override
  Stream<BleDisconnectEvent> get disconnects => _disconnects.stream;

  void emitAdvertisement(Map<String, dynamic> value) => _scan.add(value);
  void emitFiltered(String reason) => _scan.add({
    'eventType': 'advertisement',
    'scanSessionId': startedScanSessionId,
    'accepted': false,
    'decisionReason': reason,
    'addressHash': List.filled(64, 'f').join(),
    'serviceUuids': const <String>[],
    'manufacturerDataPresent': false,
    'manufacturerDataLength': 0,
  });
  void emitScanFailure(int errorCode) {
    _scan.add({
      'eventType': 'scanFailure',
      'scanSessionId': startedScanSessionId,
      'androidScanErrorCode': errorCode,
    });
    _scan.addError(
      PlatformException(
        code: 'gatt_operation_failed',
        details: {
          'androidScanErrorCode': errorCode,
          'scanSessionId': startedScanSessionId,
        },
      ),
    );
  }

  void emitScanStrategy({
    required String event,
    required int index,
    required String name,
    required int generation,
    required String reason,
    int rawResultCount = 0,
    int deviceNameResultCount = 0,
    int candidateCount = 0,
  }) => _scan.add({
    'eventType': 'scanStrategy',
    'strategyEvent': event,
    'scanSessionId': startedScanSessionId,
    'scanFlavor': 'birdScanA',
    'scanPermissionPolicy': 'never_for_location',
    'locationService': 'not_required',
    'strategyFallbackEnabled': true,
    'strategyIndex': index,
    'strategyName': name,
    'strategyGeneration': generation,
    'strategySwitchReason': reason,
    'strategyRawResultCount': rawResultCount,
    'strategyDeviceNameCount': deviceNameResultCount,
    'strategyCandidateCount': candidateCount,
  });

  void emitNotification(String characteristicUuid, Uint8List value) => _notifications.add({'characteristicUuid': characteristicUuid, 'value': value});
  void emitDisconnect() {
    final generation = _nativeConnectionGeneration;
    _nativeConnectionGeneration = null;
    _disconnects.add(
      BleDisconnectEvent(
        reason: 'link_lost',
        gattStatus: 133,
        unexpected: true,
        connectionGeneration: generation,
      ),
    );
  }

  void emitDiagnostic(Map<String, dynamic> event) => _diagnostics.add(event);
  void queueRead(String characteristicUuid, List<Uint8List> packets) => _reads[characteristicUuid] = List.of(packets);

  @override
  Future<BleScanEnvironment> readScanEnvironment() async => BleScanEnvironment(
    permission: permissionGranted ? BleScanPermissionState.granted : BleScanPermissionState.denied,
    adapter: adapterState,
    scanPermission: permissionGranted ? BleScanPermissionState.granted : BleScanPermissionState.denied,
    connectPermission: permissionGranted ? BleScanPermissionState.granted : BleScanPermissionState.denied,
    locationPermission: BleScanPermissionState.notRequired,
    locationService: BleLocationServiceState.notRequired,
    manufacturer: 'test-manufacturer',
    model: 'test-model',
    androidRelease: '16',
    sdkInt: 36,
    packageId: 'deckers.thibault.aves.bird.scan.a',
    buildFlavor: 'birdScanA',
    buildType: 'debug',
    appVersionName: '1.14.9',
    appVersionCode: '174',
    gitCommit: '0123456789abcdef0123456789abcdef01234567',
    scanPermissionPolicy: 'never_for_location',
    scanFlavor: 'birdScanA',
    scanStrategyFallbackEnabled: true,
    scanMode: 'low_latency',
  );
  @override
  Future<bool> ensurePermissions() async => permissionGranted;
  @override
  Future<void> startScan(
    Duration timeout, {
    required String scanSessionId,
  }) async {
    startedScanSessionId = scanSessionId;
    startedScanTimeout = timeout;
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<int> connect(
    String platformDeviceId, {
    required String traceId,
  }) async {
    connectCalls += 1;
    operations.add('connect:$platformDeviceId');
    final generation = ++_nextConnectionGeneration;
    _nativeConnectionGeneration = generation;
    connectedHandle = platformDeviceId;
    connectedTraceId = traceId;
    if (connectFailuresRemaining > 0) {
      connectFailuresRemaining -= 1;
      throw const ProvisioningException(
        code: ProvisioningErrorCode.networkInternalError,
        retryable: true,
        diagnosticMessage: 'simulated GATT connection failure',
      );
    }
    return generation;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    operations.add('disconnect');
    final generation = _nativeConnectionGeneration;
    _nativeConnectionGeneration = null;
    if (generation != null) {
      _disconnects.add(
        BleDisconnectEvent(
          reason: 'requested',
          gattStatus: 0,
          unexpected: false,
          connectionGeneration: generation,
        ),
      );
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    requestedMtu = mtu;
    if (disconnectDuringMtu) {
      emitDisconnect();
      await Future<void>.delayed(Duration.zero);
    }
    return negotiatedMtu;
  }

  @override
  Future<Uint8List> readCharacteristic(String characteristicUuid) async {
    final packets = _reads[characteristicUuid];
    if (packets == null || packets.isEmpty) throw StateError('No queued read for $characteristicUuid');
    return packets.removeAt(0);
  }

  @override
  Future<void> setNotify(String characteristicUuid, {required bool enabled}) async {
    if (enabled && characteristicUuid == notifyFailureUuid) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.networkInternalError,
        retryable: true,
        diagnosticMessage: 'simulated notification restore failure',
      );
    }
    if (enabled) {
      subscribed.add(characteristicUuid);
      notifyEnableCounts.update(characteristicUuid, (value) => value + 1, ifAbsent: () => 1);
    } else {
      subscribed.remove(characteristicUuid);
    }
  }

  @override
  Future<void> writeWithResponse(
    String characteristicUuid,
    Uint8List value,
  ) async {
    writeAttempts.add(_Write(characteristicUuid, Uint8List.fromList(value)));
    if (securityFailuresRemaining > 0) {
      securityFailuresRemaining -= 1;
      throw const ProvisioningException(
        code: ProvisioningErrorCode.authorizationRequired,
        retryable: true,
        diagnosticMessage: 'gattStatus=5',
      );
    }
    writes.add(_Write(characteristicUuid, Uint8List.fromList(value)));
  }

  @override
  Future<void> beginSecurityWrite(
    String requestId, {
    required String commandType,
  }) async {
    beginSecurityWriteCalls += 1;
    activeSecurityRequestId = requestId;
  }

  @override
  Future<bool> awaitSecurityReady(String requestId) async {
    awaitSecurityReadyCalls += 1;
    if (requestId != activeSecurityRequestId) throw StateError('request mismatch');
    final error = securityReadyError;
    if (error != null) throw error;
    return gattRebuiltAfterSecurity;
  }

  @override
  Future<void> beginSecurityRetry(String requestId) async {
    beginSecurityRetryCalls += 1;
    if (requestId != activeSecurityRequestId) throw StateError('request mismatch');
  }

  @override
  Future<void> markSecurityWriteSent(String requestId) async {
    markSecurityWriteSentCalls += 1;
    if (requestId != activeSecurityRequestId) throw StateError('request mismatch');
  }

  @override
  Future<void> completeSecurityWrite(
    String requestId, {
    required String responseType,
  }) async {
    if (requestId != activeSecurityRequestId) throw StateError('request mismatch');
    completedSecurityRequestId = requestId;
    activeSecurityRequestId = null;
  }

  @override
  Future<void> failSecurityWrite(
    String requestId, {
    required String errorCode,
  }) async {
    failSecurityWriteCalls += 1;
    if (requestId != activeSecurityRequestId) throw StateError('request mismatch');
    activeSecurityRequestId = null;
  }

  @override
  Future<void> dispose() async {
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

final class _RecordingDiagnosticSink implements BleScanDiagnosticSink {
  final List<BleScanDiagnosticSession> sessions = [];

  @override
  Future<void> record(BleScanDiagnosticSession session) async {
    sessions.add(session);
  }
}
