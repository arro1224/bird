import 'dart:convert';

const bondFirstScenarios = <String>{
  'bond_first',
  'already_bonded',
  'auth_once',
  'auth_persistent',
  'att_timeout_first',
  'att_timeout_middle',
  'att_timeout_last',
  'notification_failure',
  'disconnect_once',
  'response_delay',
  'response_wrong',
  'response_duplicate',
  'business_timeout',
};

List<String> validateBondFirstEvidence(Map<String, dynamic> value) {
  final errors = <String>[];
  void check(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  Map<String, dynamic> map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : {};
  List<Map<String, dynamic>> rows(Object? value) => value is List ? value.whereType<Map>().map(Map<String, dynamic>.from).toList() : [];
  bool sha(Object? value) => value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  check(value['schema_version'] == 2, 'bond-first schema_version must be 2.');
  check(value['security_flow'] == 'bond_first' && value['endpoint_kind'] == 'virtual_birdbox', 'bond-first virtual endpoint identity is required.');
  check(value['hardware_status'] == 'pending', 'real BirdBox hardware_status must remain pending.');
  final kind = value['evidence_kind'];
  check(kind == 'virtual_birdbox_avd' || kind == 'virtual_birdbox_phone', 'only distinct AVD/phone virtual endpoint evidence is accepted.');
  final scenario = value['scenario'];
  check(bondFirstScenarios.contains(scenario), 'unsupported bond-first scenario.');
  check(value['test_exit_code'] == 0, 'integration test did not pass.');
  if (kind == 'virtual_birdbox_avd') {
    final emulator = map(value['emulator']);
    final version = RegExp(r'^(\d+)\.(\d+)').firstMatch('${emulator['version']}');
    check(version != null && (int.parse(version[1]!) > 36 || (int.parse(version[1]!) == 36 && int.parse(version[2]!) >= 5)), 'AVD evidence requires Emulator 36.5+.');
    check(emulator['app_avd'] is String && emulator['box_avd'] is String && emulator['app_avd'] != emulator['box_avd'], 'two distinct AVD identities are required.');
    final netsim = map(value['netsim']);
    final pcaps = rows(netsim['pcap_files']);
    check(netsim['pcap_requested'] == true && pcaps.isNotEmpty && pcaps.every((file) => file['path'] is String && file['transport'] == 'bluetooth' && sha(file['sha256'])), 'AVD evidence requires Bluetooth PCAP artifacts and hashes.');
  } else if (kind == 'virtual_birdbox_phone') {
    final phones = map(value['phones']);
    for (final role in ['app', 'box']) {
      final device = map(phones[role]);
      check(device['model'] is String && device['manufacturer'] is String && device['sdk_int'] is int && sha(device['device_alias']), '$role phone identity is incomplete.');
    }
    check(map(phones['app'])['device_alias'] != map(phones['box'])['device_alias'], 'phone roles must use two distinct devices.');
    check(value['netsim'] == null && value['emulator'] == null, 'phone evidence must not claim AVD netsim/PCAP.');
  }
  final builds = map(value['builds']);
  check(sha(map(builds['app'])['apk_sha256']) && sha(map(builds['box'])['apk_sha256']), 'both actual APK hashes are required.');
  final app = map(value['app_evidence']);
  if (app.containsKey('capture_status')) {
    check(app['capture_status'] == 'completed' && app['command_attempted'] == true && app['failure_stage'] == null, 'early scan/connect/notification failures cannot count as scenario acceptance.');
  }
  if (value.containsKey('run_status')) check(value['run_status'] == 'passed', 'phone runner did not complete all required checks.');
  check(app['schema_version'] == 2 && app['security_flow'] == 'bond_first' && app['scenario'] == scenario, 'app evidence does not match this bond-first run.');
  check(app['hardware_status'] == 'pending', 'app evidence must remain hardware pending.');
  final appBuild = map(app['build']);
  check(appBuild['apk_sha256'] == map(builds['app'])['apk_sha256'] && sha(appBuild['source_fingerprint']), 'App evidence must identify the exact APK and source build.');
  final requestId = app['request_id'];
  final messageHash = app['message_sha256'];
  check(requestId is String && sha(messageHash), 'request identity and original reassembled message hash are required.');
  final allEvents = rows(app['events']);
  final events = allEvents.where((e) => e['request_id'] == requestId).toList();
  final box = rows(value['box_events']);
  List<Map<String, dynamic>> of(String type) => events.where((e) => e['event_type'] == type).toList();
  List<Map<String, dynamic>> boxOf(String type) => box.where((e) => e['event_type'] == type).map((e) => map(e['fields'])).toList();
  check(boxOf('advertising_started').isNotEmpty && boxOf('service_added').any((e) => e['characteristic_count'] == 5), 'five-characteristic server and advertising callbacks are required.');
  check(boxOf('server_starting').any((e) => e['encrypted_write_permissions'] == true), 'open-write success cannot prove protected writes.');
  check(of('command_started').length == 1, 'one parent command is required.');
  check(events.every((e) => e['event_type'] != 'conditional_bond_fallback_started'), 'bond-first must not use legacy write-triggered fallback.');
  final creates = of('create_bond_invoked');
  final initialBond = app['initial_bond_state'];
  // Historical records retain their original first-bond expectations. New
  // fault tests may start bonded, with the baseline proved by a native event.
  if (app.containsKey('initial_bond_state')) {
    check(initialBond == 'bonded' || initialBond == 'not_bonded', 'initial bond baseline is missing.');
    final starts = of('user_start_pairing');
    check(starts.length == 1 && starts.single['source'] == 'android' && starts.single['bond_state'] == initialBond, 'initial bond baseline must match the actual native start event.');
    if (scenario == 'bond_first') check(initialBond == 'not_bonded', 'first-bond scenario must start unbonded.');
    if (scenario == 'already_bonded') check(initialBond == 'bonded', 'already-bonded scenario must start bonded.');
  }
  final expectedCreates = app.containsKey('initial_bond_state') ? (initialBond == 'bonded' ? 0 : 1) : (scenario == 'already_bonded' ? 0 : 1);
  check(creates.length == expectedCreates, 'createBond invocation count does not match first/already bound branch.');
  if (expectedCreates == 1) check(of('create_bond_returned').any((e) => e['create_bond_returned'] == true), 'actual createBond return must be recorded.');
  final terminals = of('security_write_fact_finalized');
  check(terminals.length == 1, 'one finalized parent attempt is required.');
  final facts = terminals.isEmpty ? <String, dynamic>{} : terminals.first;
  check(facts['create_bond_call_count'] == expectedCreates, 'actual createBond side-effect count is inconsistent.');
  check(facts['attempt_id'] is String && facts['connection_generation'] is int && facts['gatt_generation'] is int, 'attempt and generation ownership are required.');
  final retries = of('security_write_retrying');
  final recovery = scenario == 'auth_once' || scenario == 'auth_persistent' || '$scenario'.startsWith('att_timeout_');
  check(retries.length == (recovery ? 1 : 0) && retries.every((e) => e['retry_count'] == 1), 'abnormal recovery is limited to one retry; normal success requires none.');
  check(
    of('gatt_rebuild_completed').length ==
        (scenario == 'notification_failure'
            ? 0
            : recovery
            ? 2
            : 1),
    'secured GATT must rebuild and restore both notifications before writing.',
  );
  final invocations = of('security_write_api_invoked');
  check(facts['att_write_call_count'] == invocations.length, 'ATT call count differs from actual API invocation events.');
  check(
    facts['command_attempt_count'] ==
        (scenario == 'notification_failure'
            ? 0
            : recovery
            ? 2
            : 1),
    'command attempts and ATT fragments must be distinguished.',
  );
  for (final invocation in invocations) {
    final position = events.indexOf(invocation);
    check(events.take(position).any((e) => e['event_type'] == 'gatt_rebuild_completed' && e['gatt_generation'] == invocation['gatt_generation']), 'protected write preceded secured GATT notification restoration.');
  }
  final fragments = boxOf('write_fragment_received');
  check(
    fragments.every((e) => e['bonded'] == true && e['frame_bytes'] is int && e['maximum_fragment_bytes'] is int && (e['maximum_fragment_bytes'] as int) <= 512 && (e['frame_bytes'] as int) <= (e['maximum_fragment_bytes'] as int)),
    'each actual fragment must be bonded and fit its current MTU.',
  );
  final received = boxOf('command_received');
  check(received.every((e) => e['request_id'] == requestId && e['payload_sha256'] == messageHash), 'reassembled retry must preserve request_id and full command; MTU may change fragments.');
  final success = const {'bond_first', 'already_bonded', 'auth_once', 'att_timeout_first', 'att_timeout_middle', 'att_timeout_last', 'response_delay', 'response_duplicate'}.contains(scenario);
  check(of(success ? 'command_succeeded' : 'command_failed').length == 1 && of(success ? 'command_failed' : 'command_succeeded').isEmpty, 'command terminal outcome does not match the scenario.');
  if (success) {
    check(app['response_type'] == 'pairing_opened' && received.isNotEmpty, 'matching pairing_opened and reassembled command are required.');
  }
  final operations = boxOf('business_operation_executed');
  check(operations.length == (const {'notification_failure', 'auth_persistent', 'disconnect_once'}.contains(scenario) ? 0 : 1), 'retries must execute the business operation at most once.');
  final settings = boxOf('server_starting');
  final fault = settings.isEmpty ? <String, dynamic>{} : settings.first;
  check(settings.length == 1, 'one explicit virtual endpoint fault configuration is required.');
  for (final injected in [...boxOf('security_failure_injected'), ...boxOf('att_response_omitted'), ...boxOf('disconnect_injected')]) {
    final count = injected['fragment_count'];
    final target = switch (fault['fault_position']) {
      'first' => 1,
      'middle' => count is int ? (count + 1) ~/ 2 : null,
      'last' => count,
      'index' => fault['fault_fragment_index'],
      _ => null,
    };
    check(
      count is int && count > 0 && target is int && target > 0 && target <= count && injected['fragment_index'] == target && injected['characteristic'] == fault['fault_characteristic'] && injected['status'] == fault['fault_status'],
      'injected fault must match the declared characteristic, status and fragment target.',
    );
  }
  if (scenario == 'auth_once' || scenario == 'auth_persistent') {
    final failures = boxOf('security_failure_injected');
    check(
      failures.isNotEmpty && failures.map((e) => e['fault_round']).toSet().length == (scenario == 'auth_once' ? 1 : 2) && failures.every((e) => e['fault_round'] is int && e['bonded'] == true && (e['status'] == 5 || e['status'] == 15)),
      'authentication fault must occur after bond in one/two GATT rounds on the specified fragment.',
    );
  }
  if ('$scenario'.startsWith('att_timeout_')) {
    final failures = boxOf('att_response_omitted');
    check(failures.length == 1, 'one omitted ATT response is required.');
    if (failures.isNotEmpty) {
      final failure = failures.single;
      final count = failure['fragment_count'];
      check(count is int && count >= 3, 'first/middle/last fault coverage requires at least three actual fragments.');
      final target = scenario == 'att_timeout_first'
          ? 1
          : scenario == 'att_timeout_last'
          ? count
          : count is int
          ? (count + 1) ~/ 2
          : null;
      check(failure['fragment_index'] == target, 'ATT omission must target the declared first/middle/last fragment.');
    }
    check(of('security_write_callback_timeout').isNotEmpty, 'ATT omission must produce write callback timeout.');
  }
  if (scenario == 'notification_failure') check(boxOf('notification_failure_injected').length == 1 && fragments.isEmpty, 'subscription failure must prevent all protected writes.');
  if (scenario == 'disconnect_once') check(boxOf('disconnect_injected').length == 1 && allEvents.any((e) => e['event_type'] == 'disconnected'), 'injected disconnect must be observed by the App.');
  if (scenario == 'response_duplicate') check(boxOf('duplicate_business_response_injected').length == 1, 'duplicate business response evidence is required.');
  if (scenario == 'response_delay') check(boxOf('server_starting').any((e) => e['business_response_delay_ms'] is int && (e['business_response_delay_ms'] as int) >= 1000), 'business response delay must be explicit.');
  if (scenario == 'business_timeout' || scenario == 'response_wrong') {
    check(
      boxOf(scenario == 'business_timeout' ? 'business_response_omitted' : 'wrong_business_response_injected').length == 1 &&
          of('security_write_callback_timeout').isEmpty &&
          of('command_failed').any((e) => e['error_code'] == 'PAIRING_OPEN_TIMEOUT'),
      'business timeout must remain distinct from missing ATT acknowledgment.',
    );
  }
  final encoded = jsonEncode(value);
  check(!RegExp(r'\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b', caseSensitive: false).hasMatch(encoded), 'evidence contains a complete MAC address.');
  check(!RegExp(r'"(?:password|passphrase|token|secret|pairing_code)"\s*:\s*"(?!\[REDACTED\])[^\"]+"', caseSensitive: false).hasMatch(encoded), 'evidence contains credential-like material.');
  return errors;
}
