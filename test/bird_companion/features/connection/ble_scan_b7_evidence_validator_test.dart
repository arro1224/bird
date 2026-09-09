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
  'scan_session_id': id,
  'started_at': '2026-09-08T01:00:00.000Z',
  'native_started_at': '2026-09-08T01:00:00.100Z',
  'first_raw_result_at': '2026-09-08T01:00:00.200Z',
  'first_candidate_at': '2026-09-08T01:00:00.300Z',
  'ended_at': '2026-09-08T01:00:10.000Z',
  'permission_before': 'granted',
  'permission_after': 'granted',
  'adapter_before': 'enabled',
  'adapter_after': 'enabled',
  'raw_result_count': 2,
  'accepted_count': 1,
  'filtered_count': 1,
  'reason_counts': {'birdbox_service': 1, 'non_birdbox': 1},
  'end_reason': 'timeout',
  'android_scan_error_code': null,
};
