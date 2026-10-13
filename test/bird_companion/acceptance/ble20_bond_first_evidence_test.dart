import 'package:flutter_test/flutter_test.dart';
import '../../../tool/ble11/ble11_evidence_validator.dart';
import '../../../tool/ble11/bond_first_evidence_validator.dart';

const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const otherHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
Map<String, dynamic> fixture(String scenario, {bool phone = false}) {
  final recovery = scenario == 'auth_once' || scenario == 'auth_persistent' || scenario.startsWith('att_timeout_');
  final notification = scenario == 'notification_failure';
  final failure = const {'notification_failure', 'auth_persistent', 'disconnect_once', 'response_wrong', 'business_timeout'}.contains(scenario);
  final creates = scenario == 'already_bonded' ? 0 : 1;
  final app = <Map<String, dynamic>>[];
  void event(String type, [Map<String, dynamic> fields = const {}]) => app.add({
    'event_type': type,
    'request_id': 'request',
    'attempt_id': 'attempt',
    'connection_generation': 1,
    'gatt_generation': 2,
    ...fields,
  });
  event('command_started');
  if (creates == 1) {
    event('create_bond_invoked');
    event('create_bond_returned', {'create_bond_returned': true});
  }
  if (!notification) {
    event('gatt_rebuild_completed');
    event('security_write_api_invoked');
  }
  if (recovery) {
    event('security_write_callback_timeout');
    event('gatt_rebuild_completed');
    event('security_write_retrying', {'retry_count': 1});
    event('security_write_api_invoked');
  }
  if (scenario == 'disconnect_once') event('disconnected');
  event('security_write_fact_finalized', {
    'create_bond_call_count': creates,
    'command_attempt_count': notification
        ? 0
        : recovery
        ? 2
        : 1,
    'att_write_call_count': notification
        ? 0
        : recovery
        ? 2
        : 1,
  });
  event(failure ? 'command_failed' : 'command_succeeded', {
    if (scenario == 'business_timeout' || scenario == 'response_wrong') 'error_code': 'PAIRING_OPEN_TIMEOUT',
  });
  final box = <Map<String, dynamic>>[];
  void boxEvent(String type, [Map<String, dynamic> fields = const {}]) => box.add({
    'schema_version': 2,
    'event_type': type,
    'fields': {'characteristic': '6f7d0005', 'fragment_index': 1, 'fragment_count': 7, 'status': 5, ...fields},
  });
  boxEvent('server_starting', {
    'encrypted_write_permissions': true,
    'business_response_delay_ms': 1000,
    'fault_characteristic': '6f7d0005',
    'fault_status': 5,
    'fault_position': scenario == 'att_timeout_middle'
        ? 'middle'
        : scenario == 'att_timeout_last'
        ? 'last'
        : 'first',
    'fault_fragment_index': 1,
  });
  boxEvent('service_added', {'characteristic_count': 5});
  boxEvent('advertising_started');
  if (!notification) boxEvent('write_fragment_received', {'bonded': true, 'frame_bytes': 20, 'maximum_fragment_bytes': 20});
  if (!const {'notification_failure', 'auth_persistent', 'disconnect_once'}.contains(scenario)) {
    boxEvent('command_received', {'request_id': 'request', 'payload_sha256': hash});
    boxEvent('business_operation_executed', {'request_id': 'request', 'payload_sha256': hash});
  }
  if (scenario == 'auth_once' || scenario == 'auth_persistent') {
    boxEvent('security_failure_injected', {'bonded': true, 'status': 5, 'fault_round': 1});
    if (scenario == 'auth_persistent') boxEvent('security_failure_injected', {'bonded': true, 'status': 5, 'fault_round': 2});
  }
  if (scenario.startsWith('att_timeout_')) {
    boxEvent('att_response_omitted', {
      'fragment_count': 7,
      'fragment_index': scenario == 'att_timeout_first'
          ? 1
          : scenario == 'att_timeout_last'
          ? 7
          : 4,
    });
  }
  if (scenario == 'notification_failure') boxEvent('notification_failure_injected');
  if (scenario == 'disconnect_once') boxEvent('disconnect_injected');
  if (scenario == 'response_duplicate') boxEvent('duplicate_business_response_injected');
  if (scenario == 'response_wrong') boxEvent('wrong_business_response_injected');
  if (scenario == 'business_timeout') boxEvent('business_response_omitted');
  return {
    'schema_version': 2,
    'security_flow': 'bond_first',
    'endpoint_kind': 'virtual_birdbox',
    'hardware_status': 'pending',
    'evidence_kind': phone ? 'virtual_birdbox_phone' : 'virtual_birdbox_avd',
    'scenario': scenario,
    'test_exit_code': 0,
    'builds': {
      'app': {'apk_sha256': hash},
      'box': {'apk_sha256': otherHash},
    },
    if (phone)
      'phones': {
        'app': {'manufacturer': 'Huawei', 'model': 'test', 'sdk_int': 31, 'device_alias': hash},
        'box': {'manufacturer': 'vivo', 'model': 'test', 'sdk_int': 27, 'device_alias': otherHash},
      }
    else ...{
      'emulator': {'version': '37.2.12', 'app_avd': 'app', 'box_avd': 'box'},
      'netsim': {
        'pcap_requested': true,
        'pcap_files': [
          {'path': 'netsimd/pcap/test.pcap', 'transport': 'bluetooth', 'sha256': hash},
        ],
      },
    },
    'app_evidence': {
      'schema_version': 2,
      'security_flow': 'bond_first',
      'hardware_status': 'pending',
      'scenario': scenario,
      'request_id': 'request',
      'message_sha256': hash,
      'response_type': failure ? null : 'pairing_opened',
      'build': {'apk_sha256': hash, 'source_fingerprint': otherHash},
      'events': app,
    },
    'box_events': box,
  };
}

void main() {
  test('bonded fault baseline is accepted only with matching native start facts', () {
    final evidence = fixture('auth_once', phone: true);
    final app = evidence['app_evidence'] as Map;
    app['initial_bond_state'] = 'bonded';
    final events = app['events'] as List;
    events.removeWhere((e) => e['event_type'] == 'create_bond_invoked' || e['event_type'] == 'create_bond_returned');
    events.add({'event_type': 'user_start_pairing', 'source': 'android', 'request_id': 'request', 'bond_state': 'bonded'});
    events.firstWhere((e) => e['event_type'] == 'security_write_fact_finalized')['create_bond_call_count'] = 0;
    expect(validateBle11Evidence(evidence).errors, isEmpty);
    events.last['bond_state'] = 'not_bonded';
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('actual native start event'));
  });
  test('new baseline cannot convert an already-bonded run into first-bond acceptance', () {
    final evidence = fixture('bond_first', phone: true);
    (evidence['app_evidence'] as Map)['initial_bond_state'] = 'bonded';
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('must start unbonded'));
  });
  for (final scenario in bondFirstScenarios) {
    test('validates $scenario with both AVD and phone evidence types', () {
      for (final phone in [false, true]) {
        final result = validateBle11Evidence(fixture(scenario, phone: phone));
        expect(result.errors, isEmpty, reason: '$scenario phone=$phone');
      }
    });
  }
  test('normal first bond cannot require fallback or command retry', () {
    final evidence = fixture('bond_first');
    ((evidence['app_evidence'] as Map)['events'] as List).add({'event_type': 'conditional_bond_fallback_started', 'request_id': 'request'});
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('legacy write-triggered fallback'));
  });
  test('open writes and mismatched APK are rejected', () {
    final evidence = fixture('bond_first');
    ((evidence['box_events'] as List).first['fields'] as Map)['encrypted_write_permissions'] = false;
    ((evidence['app_evidence'] as Map)['build'] as Map)['apk_sha256'] = otherHash;
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('open-write success'));
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('exact APK'));
  });
  test('changed reassembled retry and oversized new MTU fragments are rejected', () {
    final evidence = fixture('auth_once');
    final events = evidence['box_events'] as List;
    (events.firstWhere((e) => e['event_type'] == 'command_received')['fields'] as Map)['payload_sha256'] = otherHash;
    (events.firstWhere((e) => e['event_type'] == 'write_fragment_received')['fields'] as Map)['frame_bytes'] = 98;
    final errors = validateBle11Evidence(evidence).errors.join('\n');
    expect(errors, contains('full command'));
    expect(errors, contains('current MTU'));
  });
  test('duplicate business effect and inconsistent ATT counters are rejected', () {
    final evidence = fixture('auth_once');
    (evidence['box_events'] as List).add({'event_type': 'business_operation_executed', 'fields': {}});
    final events = (evidence['app_evidence'] as Map)['events'] as List;
    events.firstWhere((e) => e['event_type'] == 'security_write_fact_finalized')['att_write_call_count'] = 1;
    final errors = validateBle11Evidence(evidence).errors.join('\n');
    expect(errors, contains('at most once'));
    expect(errors, contains('actual API invocation'));
  });
  test('phone evidence needs two identities but no netsim', () {
    final evidence = fixture('bond_first', phone: true);
    evidence['netsim'] = {};
    ((evidence['phones'] as Map)['box'] as Map)['device_alias'] = hash;
    final errors = validateBle11Evidence(evidence).errors.join('\n');
    expect(errors, contains('distinct devices'));
    expect(errors, contains('must not claim AVD'));
  });
  test('wrong target and endless recovery are rejected', () {
    final evidence = fixture('att_timeout_middle');
    final box = evidence['box_events'] as List;
    (box.firstWhere((e) => e['event_type'] == 'att_response_omitted')['fields'] as Map)['fragment_index'] = 7;
    final app = (evidence['app_evidence'] as Map)['events'] as List;
    app.add({'event_type': 'security_write_retrying', 'request_id': 'request', 'retry_count': 2});
    final errors = validateBle11Evidence(evidence).errors.join('\n');
    expect(errors, contains('first/middle/last'));
    expect(errors, contains('limited to one retry'));
  });
  test('authentication faults must hit the declared characteristic and status', () {
    final evidence = fixture('auth_once');
    final box = evidence['box_events'] as List;
    (box.firstWhere((e) => e['event_type'] == 'security_failure_injected')['fields'] as Map)['characteristic'] = '6f7d0004';
    expect(validateBle11Evidence(evidence).errors.join('\n'), contains('declared characteristic'));
  });
}
