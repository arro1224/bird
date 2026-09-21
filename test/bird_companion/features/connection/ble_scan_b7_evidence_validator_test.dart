import '../../../../tool/acceptance/ble_scan_b7_evidence_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B7 real-device evidence requires every scenario and rejects secrets', () {
    final runs = <Map<String, Object?>>[];
    for (final scenario in bleScanB7Scenarios) {
      for (var index = 0; index < 10; index++) {
        runs.add({
          'scenario': scenario,
          'session': _session('$scenario-$index'),
        });
      }
    }

    expect(validateBleScanB7Evidence({'runs': runs}).passed, isTrue);

    final incomplete = validateBleScanB7Evidence({
      'runs': [
        {
          'scenario': 'cold_start_permission_granted',
          'session': {..._session('leaky'), 'device_id': 'must-not-be-exported'},
        },
      ],
    });
    expect(incomplete.passed, isFalse);
    expect(incomplete.errors, contains(contains('forbidden')));
    expect(incomplete.errors, contains(contains('multiple_boxes has 0/10')));
  });
}

Map<String, Object?> _session(String id) => {
  'schema_version': 3,
  'trace_id': id,
  'scan_session_id': id,
  'started_at': '2026-09-08T01:00:00.000Z',
  'native_started_at': '2026-09-08T01:00:00.100Z',
  'first_raw_result_at': '2026-09-08T01:00:00.200Z',
  'first_candidate_at': '2026-09-08T01:00:00.300Z',
  'ended_at': '2026-09-08T01:00:10.000Z',
  'permission_before': 'granted',
  'permission_after': 'granted',
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
  'scan_mode': 'low_latency',
  'raw_result_count': 2,
  'unique_device_count': 2,
  'accepted_count': 1,
  'filtered_count': 1,
  'reason_counts': {'birdbox_service': 1, 'non_birdbox': 1},
  'observations': [
    {
      'address_hash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'service_uuids': const ['6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000'],
      'manufacturer_data_present': false,
      'manufacturer_data_length': 0,
      'scan_record_length': 7,
      'scan_record_redacted_hex': '02010603030102',
      'scan_record_truncated': false,
      'accepted': true,
      'reason_code': 'birdbox_service',
    },
    {
      'address_hash': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      'service_uuids': const <String>[],
      'manufacturer_data_present': false,
      'manufacturer_data_length': 0,
      'accepted': false,
      'reason_code': 'non_birdbox',
    },
  ],
  'end_reason': 'timeout',
  'android_scan_error_code': null,
};
