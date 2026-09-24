import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ble11/ble11_evidence_validator.dart';

void main() {
  test('accepts a complete fallback simulation without promoting hardware', () {
    final evidence = _evidence('fallback_once');
    final appEvents = (evidence['app_evidence'] as Map<String, dynamic>)['events'] as List<Map<String, dynamic>>;
    appEvents.addAll([
      _appEvent('conditional_bond_fallback_started'),
      _appEvent('security_recovery_completed'),
      _appEvent('security_write_retrying', retryCount: 1),
      _appEvent(
        'gatt_recovery_completed',
        gattRebuilt: true,
        connectionGeneration: 1,
        gattInstanceId: 2,
      ),
    ]);
    (evidence['box_events'] as List<Map<String, dynamic>>).addAll([
      _boxEvent('security_failure_injected'),
      _boxEvent(
        'encrypted_retry_observed',
        fields: {'matches_original': true, 'bonded': true},
      ),
    ]);

    expect(validateBle11Evidence(evidence).errors, isEmpty);
  });

  test('rejects any attempt to promote AVD evidence to hardware verified', () {
    final evidence = _evidence('success')..['hardware_status'] = 'verified';
    final result = validateBle11Evidence(evidence);
    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('must remain pending'));
  });

  test('rejects fallback evidence without one byte-identical retry', () {
    final evidence = _evidence('fallback_once');
    final result = validateBle11Evidence(evidence);
    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('byte-identical retry'));
    expect(result.errors.join('\n'), contains('retry the exact command once'));
  });

  test('rejects a complete MAC or credential in simulated evidence', () {
    final evidence = _evidence('success')
      ..['unsafe_mac'] = 'AA:BB:CC:DD:EE:FF'
      ..['password'] = 'must-not-leak';
    final result = validateBle11Evidence(evidence);
    expect(result.passed, isFalse);
    expect(result.errors.join('\n'), contains('complete MAC'));
    expect(result.errors.join('\n'), contains('credential-like'));
  });
}

Map<String, dynamic> _evidence(String scenario) => {
  'schema_version': 1,
  'evidence_kind': 'simulated',
  'hardware_status': 'pending',
  'scenario': scenario,
  'test_exit_code': 0,
  'emulator': {
    'version': '36.5.10',
    'app_avd': 'ble11_app_api36',
    'box_avd': 'ble11_box_api36',
  },
  'netsim': {
    'pcap_requested': true,
    'ble_rssi_dbm': -55,
    'pcap_files': [
      {
        'path': 'netsimd/pcap/bt.pcap',
        'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    ],
  },
  'app_evidence': {
    'evidence_kind': 'simulated',
    'hardware_status': 'pending',
    'scenario': scenario,
    'response_type': 'pairing_opened',
    'connection_generations': scenario == 'disconnect_once' ? [1, 2] : [1],
    'events': <Map<String, dynamic>>[
      _appEvent('notifications_ready'),
      _appEvent('command_succeeded'),
      if (scenario == 'disconnect_once') _appEvent('disconnected'),
    ],
  },
  'box_events': <Map<String, dynamic>>[
    _boxEvent('advertising_started'),
    _boxEvent('service_added', fields: {'characteristic_count': 5}),
    _boxEvent('command_received'),
    if (scenario == 'disconnect_once') _boxEvent('disconnect_injected'),
    if (scenario == 'disconnect_once') _boxEvent('stale_notification_injected'),
  ],
};

Map<String, dynamic> _appEvent(
  String type, {
  int? retryCount,
  bool? gattRebuilt,
  int? connectionGeneration,
  int? gattInstanceId,
}) => {
  'event_type': type,
  'retry_count': ?retryCount,
  'gatt_rebuilt': ?gattRebuilt,
  'connection_generation': ?connectionGeneration,
  'gatt_instance_id': ?gattInstanceId,
};

Map<String, dynamic> _boxEvent(
  String type, {
  Map<String, dynamic> fields = const {},
}) => {'event_type': type, 'fields': fields};
