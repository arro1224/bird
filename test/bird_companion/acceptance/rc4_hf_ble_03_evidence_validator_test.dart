import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/acceptance/rc4_hf_ble_03_evidence_validator.dart';

void main() {
  late Directory evidenceRoot;
  late Map<String, dynamic> evidence;

  setUp(() {
    evidenceRoot = Directory.systemTemp.createTempSync('rc4-hf-ble-03-');
    evidence = _validEvidence(evidenceRoot);
  });

  tearDown(() => evidenceRoot.deleteSync(recursive: true));

  test('accepts complete OPPO pairing, Huawei A/B, and K7 evidence', () {
    final result = validateRc4HfBle03Evidence(
      evidence,
      evidenceRoot: evidenceRoot,
    );

    expect(result.passed, isTrue, reason: result.errors.join('\n'));
    expect(result.pairingRunCount, 5);
    expect(result.scanRunsByKey['huawei/A/baseline'], 10);
    expect(result.scanRunsByKey['huawei/B/foreground_resumed'], 10);
    expect(result.scanRunsByKey['oppo/B/baseline'], 10);
    expect(result.toJson()['hardware_status'], 'verified');
  });

  test('fails closed on pending template and missing hardware', () {
    final template = jsonDecode(
      File(
        'docs/acceptance/rc4-hf-ble-03-evidence.template.json',
      ).readAsStringSync(),
    );

    final result = validateRc4HfBle03Evidence(
      template,
      evidenceRoot: evidenceRoot,
    );

    expect(result.passed, isFalse);
    expect(result.errors, contains(contains('final_result must be passed')));
    expect(result.errors, contains(contains('pairing_runs has 0/5')));
    expect(result.toJson()['hardware_status'], 'pending');
  });

  test('rejects repeated retry, missing notification recovery, and K7 mismatch', () {
    final broken = _clone(evidence);
    final run = (broken['pairing_runs'] as List).first as Map<String, dynamic>;
    final diagnostic = run['diagnostic'] as Map<String, dynamic>;
    final events = diagnostic['connection_events'] as List;
    (events.first as Map<String, dynamic>)['retry_count'] = 2;
    events.add({
      ...(events.first as Map<String, dynamic>),
      'event_type': 'operation_started',
      'operation_name': 'bond',
    });
    events.removeWhere(
      (event) => event is Map && event['event_type'] == 'gatt_notification_descriptor_write' && event['characteristic_uuid'] == rc4HfBleScanResultsUuid,
    );
    (run['k7'] as Map<String, dynamic>)['request_id'] = 'wrong-request';

    final result = validateRc4HfBle03Evidence(
      broken,
      evidenceRoot: evidenceRoot,
    );

    expect(result.passed, isFalse);
    expect(result.errors, contains(contains('more than one encrypted retry')));
    expect(result.errors, contains(contains('generic createBond operation')));
    expect(result.errors, contains(contains('both notifications were restored')));
    expect(result.errors, contains(contains('K7 request_id does not match')));
  });

  test('rejects diagnostics and logs containing credentials or plaintext MAC', () {
    final broken = _clone(evidence);
    final run = (broken['pairing_runs'] as List).first as Map<String, dynamic>;
    final diagnostic = run['diagnostic'] as Map<String, dynamic>;
    diagnostic['pairing_code'] = '123456';
    File('${evidenceRoot.path}${Platform.pathSeparator}k7-0.log').writeAsStringSync('device=AA:BB:CC:DD:EE:FF pairing_code=123456');

    final result = validateRc4HfBle03Evidence(
      broken,
      evidenceRoot: evidenceRoot,
    );

    expect(result.passed, isFalse);
    expect(result.errors, contains(contains('forbidden secret field')));
    expect(result.errors, contains(contains('plaintext Bluetooth address')));
    expect(result.errors, contains(contains('credential-like material')));
  });

  test('rejects a scan strategy switch after raw callbacks were observed', () {
    final broken = _clone(evidence);
    final scanRun = (broken['scan_runs'] as List).first as Map<String, dynamic>;
    final session = scanRun['session'] as Map<String, dynamic>;
    final strategyEvents = session['strategy_events'] as List;
    (strategyEvents.first as Map<String, dynamic>)['switch_reason'] = 'raw_zero_after_4000ms';
    (strategyEvents.first as Map<String, dynamic>)['raw_result_count'] = 1;

    final result = validateRc4HfBle03Evidence(
      broken,
      evidenceRoot: evidenceRoot,
    );

    expect(result.passed, isFalse);
    expect(
      result.errors,
      contains(contains('switched strategy after raw callbacks')),
    );
  });
}

Map<String, dynamic> _validEvidence(Directory root) {
  final buildHashes = <String, String>{};
  for (final variant in const ['A', 'B']) {
    final file = File('${root.path}${Platform.pathSeparator}scan-$variant.apk')..writeAsBytesSync(utf8.encode('apk-$variant'));
    buildHashes[variant] = sha256.convert(file.readAsBytesSync()).toString();
  }
  for (var index = 0; index < 5; index++) {
    File('${root.path}${Platform.pathSeparator}k7-$index.log').writeAsStringSync('PairingAgent callback; open_pairing and authorize_pairing accepted.');
  }
  for (final name in const [
    'reconnect.log',
    'app-approval.txt',
    'board-approval.txt',
    'qa-approval.txt',
  ]) {
    File('${root.path}${Platform.pathSeparator}$name').writeAsStringSync('Reviewed redacted evidence: $name');
  }

  final scanRuns = <Map<String, Object?>>[];
  void addSeries(String role, String variant, String scenario) {
    for (var index = 0; index < 10; index++) {
      scanRuns.add({
        'device_role': role,
        'variant': variant,
        'scenario': scenario,
        'session': _scanSession(
          '$role-$variant-$scenario-$index',
          role: role,
          variant: variant,
          apkSha: buildHashes[variant]!,
        ),
      });
    }
  }

  addSeries('huawei', 'A', 'baseline');
  for (final scenario in rc4HfBleScanScenarios) {
    addSeries('huawei', 'B', scenario);
  }
  addSeries('oppo', 'B', 'baseline');

  return {
    'schema_version': 1,
    'acceptance_suite': 'rc4-hf-ble-03',
    'captured_at': '2026-09-20T08:00:00Z',
    'final_result': 'passed',
    'hardware_status': 'verified',
    'selected_scan_variant': 'B',
    'devices': {
      'oppo': {
        'physical': true,
        'manufacturer': 'OPPO',
        'model': 'PKC110',
        'sdk_int': 36,
        'redacted_serial_hash': 'oppo-hash',
      },
      'huawei': {
        'physical': true,
        'manufacturer': 'HUAWEI',
        'model': 'HUAWEI physical test phone',
        'sdk_int': 34,
        'redacted_serial_hash': 'huawei-hash',
      },
      'birdbox': {
        'physical': true,
        'model': 'BirdBox K7',
        'firmware_git_commit': 'b' * 40,
      },
    },
    'builds': {
      'A': {
        'apk_file': 'scan-A.apk',
        'apk_sha256': buildHashes['A'],
        'git_commit': 'a' * 40,
        'application_id': 'deckers.thibault.aves.bird.scan.a',
        'app_version_name': '1.14.8',
        'app_version_code': '172',
        'scan_permission_policy': 'never_for_location',
        'scan_strategy_fallback_enabled': true,
      },
      'B': {
        'apk_file': 'scan-B.apk',
        'apk_sha256': buildHashes['B'],
        'git_commit': 'a' * 40,
        'application_id': 'deckers.thibault.aves.bird.scan.b',
        'app_version_name': '1.14.8',
        'app_version_code': '172',
        'scan_permission_policy': 'full_scan',
        'scan_strategy_fallback_enabled': true,
      },
    },
    'scan_runs': scanRuns,
    'pairing_runs': [
      for (var index = 0; index < 5; index++)
        {
          'run_id': 'oppo-pairing-${index + 1}',
          'status': 'passed',
          'pairing_session_received': true,
          'health_device_id_match': true,
          'diagnostic': _pairingDiagnostic(
            'oppo-pairing-trace-$index',
            'open-request-$index',
            buildHashes['B']!,
          ),
          'k7': {
            'log_file': 'k7-$index.log',
            'pairing_agent_callback': true,
            'open_pairing_received': true,
            'authorize_pairing_received': true,
            'request_id': 'open-request-$index',
          },
        },
    ],
    'reconnect_check': {
      'status': 'passed',
      'existing_token_reused': true,
      'pairing_code_prompted': false,
      'accepted_task_continued_after_ble_disconnect': true,
      'evidence_files': ['reconnect.log'],
    },
    'approvals': {
      'app': {
        'status': 'approved',
        'reviewer': 'App reviewer',
        'evidence_file': 'app-approval.txt',
      },
      'board': {
        'status': 'approved',
        'reviewer': 'Board reviewer',
        'evidence_file': 'board-approval.txt',
      },
      'qa': {
        'status': 'approved',
        'reviewer': 'QA reviewer',
        'evidence_file': 'qa-approval.txt',
      },
    },
  };
}

Map<String, Object?> _scanSession(
  String traceId, {
  required String role,
  required String variant,
  required String apkSha,
}) => {
  'schema_version': 3,
  'trace_id': traceId,
  'scan_session_id': traceId,
  'started_at': '2026-09-20T08:00:00Z',
  'first_candidate_at': '2026-09-20T08:00:01Z',
  'ended_at': '2026-09-20T08:00:10Z',
  'manufacturer': role == 'oppo' ? 'OPPO' : 'HUAWEI',
  'model': '$role-phone',
  'android_release': role == 'oppo' ? '16' : '14',
  'sdk_int': role == 'oppo' ? 36 : 34,
  'app_version_name': '1.14.8',
  'app_version_code': '172',
  'git_commit': 'a' * 40,
  'apk_sha256': apkSha,
  'scan_permission_policy': variant == 'A' ? 'never_for_location' : 'full_scan',
  'scan_flavor': variant == 'A' ? 'birdScanA' : 'birdScanB',
  'scan_strategy_fallback_enabled': true,
  'scan_mode': 'low_latency',
  'scan_permission_before': 'granted',
  'scan_permission_after': 'granted',
  'connect_permission_before': 'granted',
  'connect_permission_after': 'granted',
  'location_permission_before': 'notRequired',
  'location_permission_after': 'notRequired',
  'adapter_before': 'enabled',
  'adapter_after': 'enabled',
  'location_service_before': 'notRequired',
  'location_service_after': 'notRequired',
  'raw_result_count': 2,
  'unique_device_count': 2,
  'accepted_count': 1,
  'filtered_count': 1,
  'reason_counts': const {'birdbox_service': 1, 'non_birdbox': 1},
  'observations': [
    {
      'address_hash': 'c' * 64,
      'name': 'BirdBox-REDACTED',
      'service_uuids': const [rc4HfBleServiceUuid],
      'manufacturer_data_present': false,
      'manufacturer_data_length': 0,
      'scan_record_length': 7,
      'scan_record_redacted_hex': '02010603030102',
      'scan_record_truncated': false,
      'accepted': true,
      'reason_code': 'birdbox_service',
      'device_name_present': true,
    },
    {
      'address_hash': 'd' * 64,
      'service_uuids': const <String>[],
      'manufacturer_data_present': false,
      'manufacturer_data_length': 0,
      'accepted': false,
      'reason_code': 'non_birdbox',
      'device_name_present': false,
    },
  ],
  'strategy_events': [
    {
      'occurred_at': '2026-09-20T08:00:00Z',
      'event': 'strategy_started',
      'index': 0,
      'name': 'NULL_FILTER_LOW_LATENCY',
      'generation': 1,
      'switch_reason': 'session_started',
      'raw_result_count': 0,
      'device_name_result_count': 0,
      'candidate_count': 0,
      'location_service': 'notRequired',
    },
    {
      'occurred_at': '2026-09-20T08:00:04Z',
      'event': 'strategy_window_elapsed',
      'index': 0,
      'name': 'NULL_FILTER_LOW_LATENCY',
      'generation': 1,
      'switch_reason': 'raw_results_observed',
      'raw_result_count': 2,
      'device_name_result_count': 1,
      'candidate_count': 1,
      'location_service': 'notRequired',
    },
  ],
  'end_reason': 'timeout',
};

Map<String, Object?> _pairingDiagnostic(
  String traceId,
  String requestId,
  String apkSha,
) {
  Map<String, Object?> event(
    String type, {
    String source = 'android',
    String? commandType = 'open_pairing',
    String? operationName,
    String? characteristicUuid,
    String? responseType,
    String? resultCode,
    String? bondState,
    String? securityTrigger,
    int retryCount = 0,
    int? gattStatus,
    String? notificationState,
    String? request = '',
  }) {
    final value = <String, Object?>{
      'schema_version': 2,
      'trace_id': traceId,
      'occurred_at': '2026-09-20T09:00:00Z',
      'event_type': type,
      'source': source,
      'manufacturer': 'OPPO',
      'model': 'PKC110',
      'android_release': '16',
      'sdk_int': 36,
      'app_version_name': '1.14.8',
      'app_version_code': '172',
      'git_commit': 'a' * 40,
      'apk_sha256': apkSha,
      'device_address_hash': 'e' * 64,
      'request_id': request == '' ? requestId : request,
      'system_pairing_interaction': type == 'bond_state_changed' && bondState != 'not_bonded',
      'retry_count': retryCount,
    };
    if (commandType != null) value['command_type'] = commandType;
    if (operationName != null) value['operation_name'] = operationName;
    if (characteristicUuid != null) {
      value['characteristic_uuid'] = characteristicUuid;
    }
    if (responseType != null) value['response_type'] = responseType;
    if (resultCode != null) value['result_code'] = resultCode;
    if (bondState != null) value['bond_state'] = bondState;
    if (securityTrigger != null) value['security_trigger'] = securityTrigger;
    if (gattStatus != null) value['gatt_status'] = gattStatus;
    if (notificationState != null) {
      value['notification_state'] = notificationState;
    }
    return value;
  }

  return {
    'schema_version': 2,
    'generated_at': '2026-09-20T09:01:00Z',
    'trace_id': traceId,
    'scan_sessions': const [],
    'connection_events': [
      event(
        'command_started',
        source: 'dart',
        operationName: 'write_command',
      ),
      event(
        'security_phase_changed',
        operationName: 'security_write',
        securityTrigger: 'encrypted_characteristic_write',
      ),
      {
        ...event(
          'gatt_characteristic_write',
          operationName: 'write_open_pairing',
          characteristicUuid: rc4HfBleProvisioningCommandUuid,
          securityTrigger: 'encrypted_characteristic_write',
          gattStatus: 5,
        ),
        'write_type': 'with_response',
        'write_callback_status': 5,
      },
      event(
        'bond_state_changed',
        operationName: 'security_write',
        bondState: 'bonding',
        resultCode: 'not_bonded_to_bonding',
      ),
      event(
        'bond_state_changed',
        operationName: 'security_write',
        bondState: 'bonded',
        resultCode: 'bonding_to_bonded',
      ),
      event(
        'gatt_notification_descriptor_write',
        operationName: 'descriptor',
        characteristicUuid: rc4HfBleNetworkStatusUuid,
        notificationState: 'enabled',
      ),
      event(
        'gatt_notification_descriptor_write',
        operationName: 'descriptor',
        characteristicUuid: rc4HfBleScanResultsUuid,
        notificationState: 'enabled',
      ),
      event(
        'security_write_retrying',
        source: 'dart',
        operationName: 'write_command',
        characteristicUuid: rc4HfBleProvisioningCommandUuid,
        securityTrigger: 'encrypted_characteristic_write',
        retryCount: 1,
      ),
      {
        ...event(
          'gatt_characteristic_write',
          operationName: 'write_open_pairing',
          characteristicUuid: rc4HfBleProvisioningCommandUuid,
          retryCount: 1,
          gattStatus: 0,
        ),
        'write_type': 'with_response',
        'write_callback_status': 0,
      },
      event(
        'security_write_completed',
        operationName: 'write_command',
        responseType: 'pairing_opened',
        retryCount: 1,
      ),
      event(
        'command_succeeded',
        source: 'dart',
        operationName: 'write_command',
        responseType: 'pairing_opened',
        resultCode: 'success',
        retryCount: 1,
      ),
      event(
        'command_succeeded',
        source: 'dart',
        commandType: 'authorize_pairing',
        operationName: 'write_command',
        responseType: 'pairing_authorized',
        resultCode: 'success',
        request: 'authorize-$requestId',
      ),
    ],
  };
}

Map<String, dynamic> _clone(Map<String, dynamic> value) => jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
