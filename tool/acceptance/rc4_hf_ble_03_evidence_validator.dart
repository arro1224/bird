import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const rc4HfBleServiceUuid = '6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000';
const rc4HfBleNetworkStatusUuid = '6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000';
const rc4HfBleProvisioningCommandUuid = '6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000';
const rc4HfBleScanResultsUuid = '6f7d0006-7a66-4c45-a1b9-5f4d2e3c1000';

const rc4HfBleScanScenarios = <String>{
  'baseline',
  'bluetooth_toggled',
  'permission_regranted',
  'foreground_resumed',
};

final class Rc4HfBle03EvidenceValidation {
  const Rc4HfBle03EvidenceValidation({
    required this.errors,
    required this.scanRunsByKey,
    required this.pairingRunCount,
  });

  final List<String> errors;
  final Map<String, int> scanRunsByKey;
  final int pairingRunCount;

  bool get passed => errors.isEmpty;

  Map<String, Object?> toJson() => {
    'gate': 'RC4-HF-BLE-03',
    'status': passed ? 'passed' : 'blocked',
    'hardware_status': passed ? 'verified' : 'pending',
    'scan_runs': scanRunsByKey,
    'pairing_runs': pairingRunCount,
    'failure_count': errors.length,
    'failures': errors,
  };
}

Rc4HfBle03EvidenceValidation validateRc4HfBle03Evidence(
  Object? document, {
  required Directory evidenceRoot,
  int minimumScanRuns = 10,
  int minimumPairingRuns = 5,
}) {
  final errors = <String>[];
  final scanRunsByKey = <String, int>{};
  final traceIds = <String>{};
  void require(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  if (document is! Map) {
    return const Rc4HfBle03EvidenceValidation(
      errors: ['Evidence root must be a JSON object.'],
      scanRunsByKey: {},
      pairingRunCount: 0,
    );
  }
  final root = Map<String, dynamic>.from(document);
  require(root['schema_version'] == 1, 'schema_version must be 1.');
  require(
    root['acceptance_suite'] == 'rc4-hf-ble-03',
    'acceptance_suite must be rc4-hf-ble-03.',
  );
  require(root['final_result'] == 'passed', 'final_result must be passed.');
  require(
    root['hardware_status'] == 'verified',
    'hardware_status must be verified.',
  );
  require(
    DateTime.tryParse(_text(root['captured_at'])) != null,
    'captured_at must be an ISO-8601 timestamp.',
  );
  for (final path in _findPlaceholders(root, r'$')) {
    errors.add('Evidence contains an unresolved placeholder: $path.');
  }

  final selectedVariant = _text(root['selected_scan_variant']);
  require(
    const {'A', 'B'}.contains(selectedVariant),
    'selected_scan_variant must be A or B.',
  );

  final devices = _map(root['devices']);
  _validatePhone(
    _map(devices['oppo']),
    role: 'oppo',
    expectedManufacturer: 'oppo',
    minimumSdk: 36,
    require: require,
  );
  _validatePhone(
    _map(devices['huawei']),
    role: 'huawei',
    expectedManufacturer: 'huawei',
    minimumSdk: 23,
    require: require,
  );
  final box = _map(devices['birdbox']);
  require(box['physical'] == true, 'devices.birdbox must be physical.');
  require(
    _text(box['model']).toLowerCase().contains('k7'),
    'devices.birdbox.model must identify a K7.',
  );
  require(
    _isSha40(box['firmware_git_commit']) || _isSha256(box['firmware_sha256']),
    'devices.birdbox must include a full firmware Git or artifact SHA.',
  );

  final builds = _map(root['builds']);
  final buildHashes = <String, String>{};
  for (final variant in const ['A', 'B']) {
    final build = _map(builds[variant]);
    final expectedPolicy = variant == 'A' ? 'never_for_location' : 'full_scan';
    final expectedApplicationId = variant == 'A' ? 'deckers.thibault.aves.bird.scan.a' : 'deckers.thibault.aves.bird.scan.b';
    final apkSha = _text(build['apk_sha256']).toLowerCase();
    require(
      build['scan_permission_policy'] == expectedPolicy,
      'builds.$variant.scan_permission_policy must be $expectedPolicy.',
    );
    require(
      build['application_id'] == expectedApplicationId,
      'builds.$variant.application_id must be $expectedApplicationId.',
    );
    require(
      _usableText(build['app_version_name']),
      'builds.$variant.app_version_name is required.',
    );
    require(
      _usableText(build['app_version_code']),
      'builds.$variant.app_version_code is required.',
    );
    require(
      build['scan_strategy_fallback_enabled'] == true,
      'builds.$variant.scan_strategy_fallback_enabled must be true.',
    );
    require(_isSha256(apkSha), 'builds.$variant.apk_sha256 must be SHA-256.');
    require(
      _isSha40(build['git_commit']),
      'builds.$variant.git_commit must be a full Git SHA.',
    );
    final apk = _resolveFile(evidenceRoot, _text(build['apk_file']));
    require(apk.existsSync(), 'builds.$variant APK does not exist.');
    if (apk.existsSync() && _isSha256(apkSha)) {
      final actual = sha256.convert(apk.readAsBytesSync()).toString();
      require(actual == apkSha, 'builds.$variant APK SHA-256 does not match.');
    }
    buildHashes[variant] = apkSha;
  }

  final scanRuns = _maps(root['scan_runs']);
  for (var index = 0; index < scanRuns.length; index++) {
    final run = scanRuns[index];
    final role = _text(run['device_role']).toLowerCase();
    final variant = _text(run['variant']);
    final scenario = _text(run['scenario']);
    final key = '$role/$variant/$scenario';
    require(
      const {'huawei', 'oppo'}.contains(role),
      'scan_runs[$index].device_role must be huawei or oppo.',
    );
    require(
      const {'A', 'B'}.contains(variant),
      'scan_runs[$index].variant must be A or B.',
    );
    require(
      rc4HfBleScanScenarios.contains(scenario),
      'scan_runs[$index].scenario is invalid.',
    );
    scanRunsByKey.update(key, (value) => value + 1, ifAbsent: () => 1);
    _validateScanSession(
      _map(run['session']),
      label: 'scan_runs[$index].session',
      expectedRole: role,
      expectedVariant: variant,
      expectedPolicy: variant == 'A' ? 'never_for_location' : 'full_scan',
      expectedApkSha: buildHashes[variant] ?? '',
      traceIds: traceIds,
      require: require,
    );
  }

  void requireScanSeries(String role, String variant, String scenario) {
    final key = '$role/$variant/$scenario';
    final count = scanRunsByKey[key] ?? 0;
    require(
      count >= minimumScanRuns,
      '$key has $count/$minimumScanRuns required successful runs.',
    );
  }

  requireScanSeries('huawei', 'A', 'baseline');
  requireScanSeries('huawei', 'B', 'baseline');
  if (const {'A', 'B'}.contains(selectedVariant)) {
    for (final scenario in rc4HfBleScanScenarios) {
      requireScanSeries('huawei', selectedVariant, scenario);
    }
    requireScanSeries('oppo', selectedVariant, 'baseline');
  }

  final pairingRuns = _maps(root['pairing_runs']);
  require(
    pairingRuns.length >= minimumPairingRuns,
    'pairing_runs has ${pairingRuns.length}/$minimumPairingRuns required runs.',
  );
  for (var index = 0; index < pairingRuns.length; index++) {
    _validatePairingRun(
      pairingRuns[index],
      index: index,
      evidenceRoot: evidenceRoot,
      expectedApkSha: buildHashes[selectedVariant] ?? '',
      traceIds: traceIds,
      require: require,
      errors: errors,
    );
  }

  _validateReconnectCheck(
    _map(root['reconnect_check']),
    evidenceRoot: evidenceRoot,
    require: require,
    errors: errors,
  );
  _validateApprovals(
    _map(root['approvals']),
    evidenceRoot: evidenceRoot,
    require: require,
    errors: errors,
  );

  return Rc4HfBle03EvidenceValidation(
    errors: List.unmodifiable(errors),
    scanRunsByKey: Map.unmodifiable(scanRunsByKey),
    pairingRunCount: pairingRuns.length,
  );
}

void _validatePhone(
  Map<String, dynamic> phone, {
  required String role,
  required String expectedManufacturer,
  required int minimumSdk,
  required void Function(bool, String) require,
}) {
  require(phone['physical'] == true, 'devices.$role must be physical.');
  require(
    _text(phone['manufacturer']).toLowerCase().contains(expectedManufacturer),
    'devices.$role.manufacturer must identify $expectedManufacturer.',
  );
  require(_usableText(phone['model']), 'devices.$role.model is required.');
  require(
    phone['sdk_int'] is int && (phone['sdk_int'] as int) >= minimumSdk,
    'devices.$role.sdk_int must be at least $minimumSdk.',
  );
  require(
    _usableText(phone['redacted_serial_hash']),
    'devices.$role.redacted_serial_hash is required.',
  );
}

void _validateScanSession(
  Map<String, dynamic> session, {
  required String label,
  required String expectedRole,
  required String expectedVariant,
  required String expectedPolicy,
  required String expectedApkSha,
  required Set<String> traceIds,
  required void Function(bool, String) require,
}) {
  require(session['schema_version'] == 3, '$label schema_version must be 3.');
  final traceId = _text(session['trace_id']);
  require(traceId.isNotEmpty, '$label.trace_id is required.');
  if (traceId.isNotEmpty) {
    require(traceIds.add(traceId), '$label repeats trace_id $traceId.');
  }
  require(
    session['scan_session_id'] == traceId,
    '$label.scan_session_id must match trace_id.',
  );
  final startedAt = DateTime.tryParse(_text(session['started_at']));
  final endedAt = DateTime.tryParse(_text(session['ended_at']));
  final firstCandidateAt = DateTime.tryParse(
    _text(session['first_candidate_at']),
  );
  require(startedAt != null, '$label.started_at must be ISO-8601.');
  require(endedAt != null, '$label.ended_at must be ISO-8601.');
  require(
    firstCandidateAt != null,
    '$label.first_candidate_at is required.',
  );
  if (startedAt != null && endedAt != null) {
    require(!endedAt.isBefore(startedAt), '$label has an invalid time range.');
  }
  if (startedAt != null && endedAt != null && firstCandidateAt != null) {
    require(
      !firstCandidateAt.isBefore(startedAt) && !firstCandidateAt.isAfter(endedAt),
      '$label.first_candidate_at is outside the scan window.',
    );
  }
  final manufacturer = _text(session['manufacturer']).toLowerCase();
  require(
    manufacturer.contains(expectedRole),
    '$label manufacturer does not match $expectedRole.',
  );
  require(
    session['scan_permission_policy'] == expectedPolicy,
    '$label scan_permission_policy does not match its APK variant.',
  );
  final expectedFlavor = expectedVariant == 'A' ? 'birdScanA' : 'birdScanB';
  require(
    session['scan_flavor'] == expectedFlavor,
    '$label scan_flavor must be $expectedFlavor.',
  );
  require(
    session['scan_strategy_fallback_enabled'] == true,
    '$label must enable the serial scan strategy fallback.',
  );
  require(
    _text(session['apk_sha256']).toLowerCase() == expectedApkSha,
    '$label apk_sha256 does not match its APK variant.',
  );
  require(_isSha40(session['git_commit']), '$label.git_commit must be SHA-1.');
  require(
    _usableText(session['app_version_name']),
    '$label.app_version_name is required.',
  );
  require(
    _usableText(session['app_version_code']),
    '$label.app_version_code is required.',
  );
  require(
    _usableText(session['android_release']),
    '$label.android_release is required.',
  );
  require(session['sdk_int'] is int, '$label.sdk_int is required.');
  require(session['scan_mode'] == 'low_latency', '$label must use low_latency.');
  require(
    session['scan_permission_before'] == 'granted' && session['scan_permission_after'] == 'granted' && session['connect_permission_before'] == 'granted' && session['connect_permission_after'] == 'granted',
    '$label must record granted SCAN and CONNECT permissions.',
  );
  require(
    session['adapter_before'] == 'enabled' && session['adapter_after'] == 'enabled',
    '$label must record an enabled Bluetooth adapter.',
  );
  final sdkInt = session['sdk_int'];
  if (sdkInt is int && sdkInt >= 31 && sdkInt <= 32 && expectedVariant == 'B') {
    require(
      session['location_permission_before'] == 'granted' && session['location_permission_after'] == 'granted',
      '$label Scan B must record granted location permission on Android 12/12L.',
    );
    require(
      session['location_service_before'] == 'enabled' && session['location_service_after'] == 'enabled',
      '$label Scan B requires enabled location services on Android 12/12L.',
    );
  } else if (sdkInt is int && sdkInt >= 31) {
    require(
      session['location_permission_before'] == 'notRequired' && session['location_permission_after'] == 'notRequired',
      '$label must not request location permission for this SDK/variant.',
    );
  }
  for (final field in const [
    'location_permission_before',
    'location_permission_after',
    'location_service_before',
    'location_service_after',
    'reason_counts',
    'end_reason',
  ]) {
    require(session.containsKey(field), '$label.$field is required.');
  }
  final raw = session['raw_result_count'];
  final accepted = session['accepted_count'];
  final filtered = session['filtered_count'];
  require(raw is int && raw > 0, '$label must contain raw scan callbacks.');
  require(accepted is int && accepted > 0, '$label did not discover BirdBox.');
  require(
    raw is int && accepted is int && filtered is int && raw == accepted + filtered,
    '$label has inconsistent scan counts.',
  );
  final observations = _maps(session['observations']);
  require(observations.isNotEmpty, '$label.observations must not be empty.');
  if (raw is int && raw <= 500) {
    require(
      observations.length == raw,
      '$label is missing raw scan observations.',
    );
  }
  final addressHashes = <String>{};
  for (var index = 0; index < observations.length; index++) {
    final observation = observations[index];
    final addressHash = _text(observation['address_hash']);
    require(
      RegExp(r'^[0-9a-f]{64}$').hasMatch(addressHash),
      '$label.observations[$index].address_hash must be SHA-256.',
    );
    if (addressHash.isNotEmpty) addressHashes.add(addressHash);
    for (final field in const [
      'service_uuids',
      'manufacturer_data_present',
      'manufacturer_data_length',
      'accepted',
      'reason_code',
      'device_name_present',
    ]) {
      require(
        observation.containsKey(field),
        '$label.observations[$index].$field is required.',
      );
    }
    final recordLength = observation['scan_record_length'];
    if (recordLength is int && recordLength > 0) {
      final redactedHex = _text(observation['scan_record_redacted_hex']);
      require(
        redactedHex.isNotEmpty && RegExp(r'^(?:[0-9a-f]{2})+$').hasMatch(redactedHex) && redactedHex.length <= 1024,
        '$label.observations[$index].scan_record_redacted_hex is invalid.',
      );
      require(
        observation['scan_record_truncated'] is bool,
        '$label.observations[$index].scan_record_truncated is required.',
      );
    }
  }
  require(
    session['unique_device_count'] is int && session['unique_device_count'] == addressHashes.length,
    '$label has an inconsistent unique_device_count.',
  );
  require(
    observations.any((item) {
      if (item['accepted'] != true) return false;
      final uuids = _strings(item['service_uuids']).map((value) => value.toLowerCase());
      return uuids.contains(rc4HfBleServiceUuid) || _text(item['name']).startsWith('BirdBox-');
    }),
    '$label has no accepted BirdBox observation.',
  );
  _validateScanStrategies(session, label: label, require: require);
  _validateSecretSafe(session, label, require);
}

void _validateScanStrategies(
  Map<String, dynamic> session, {
  required String label,
  required void Function(bool, String) require,
}) {
  final events = _maps(session['strategy_events']);
  require(events.isNotEmpty, '$label.strategy_events must not be empty.');
  if (events.isEmpty) return;
  final started = events.where((event) => event['event'] == 'strategy_started').toList();
  require(started.isNotEmpty, '$label must record a strategy_started event.');
  if (started.isNotEmpty) {
    require(
      started.first['index'] == 0 && started.first['name'] == 'NULL_FILTER_LOW_LATENCY',
      '$label must start with NULL_FILTER_LOW_LATENCY.',
    );
  }
  const expectedNames = [
    'NULL_FILTER_LOW_LATENCY',
    'EMPTY_FILTER_LIST_LOW_LATENCY',
    'EMPTY_FILTER_LIST_DEFAULT_SETTINGS',
  ];
  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    final strategyIndex = event['index'];
    require(
      strategyIndex is int && strategyIndex >= 0 && strategyIndex < expectedNames.length,
      '$label.strategy_events[$index].index is invalid.',
    );
    if (strategyIndex is int && strategyIndex >= 0 && strategyIndex < expectedNames.length) {
      require(
        event['name'] == expectedNames[strategyIndex],
        '$label.strategy_events[$index].name does not match its index.',
      );
    }
    for (final field in const [
      'occurred_at',
      'generation',
      'switch_reason',
      'raw_result_count',
      'device_name_result_count',
      'candidate_count',
      'location_service',
    ]) {
      require(
        event.containsKey(field),
        '$label.strategy_events[$index].$field is required.',
      );
    }
    require(
      event['raw_result_count'] is int &&
          (event['raw_result_count'] as int) >= 0 &&
          event['device_name_result_count'] is int &&
          (event['device_name_result_count'] as int) >= 0 &&
          event['candidate_count'] is int &&
          (event['candidate_count'] as int) >= 0,
      '$label.strategy_events[$index] has invalid counters.',
    );
  }
  for (var strategyIndex = 1; strategyIndex < started.length; strategyIndex++) {
    final current = started[strategyIndex];
    final previousIndex = current['index'] is int ? (current['index'] as int) - 1 : -1;
    final switchEvidence = events.where(
      (event) => event['event'] == 'strategy_window_elapsed' && event['index'] == previousIndex && event['switch_reason'] == 'raw_zero_after_4000ms',
    );
    require(
      switchEvidence.any((event) => event['raw_result_count'] == 0),
      '$label strategy $previousIndex switched without a raw-zero window.',
    );
  }
  require(
    !events.any(
      (event) => event['switch_reason'] == 'raw_zero_after_4000ms' && event['raw_result_count'] is int && (event['raw_result_count'] as int) > 0,
    ),
    '$label switched strategy after raw callbacks were observed.',
  );
}

void _validatePairingRun(
  Map<String, dynamic> run, {
  required int index,
  required Directory evidenceRoot,
  required String expectedApkSha,
  required Set<String> traceIds,
  required void Function(bool, String) require,
  required List<String> errors,
}) {
  final label = 'pairing_runs[$index]';
  require(run['status'] == 'passed', '$label.status must be passed.');
  require(
    run['pairing_session_received'] == true,
    '$label must confirm pairing_session_id was received without recording it.',
  );
  require(
    run['health_device_id_match'] == true,
    '$label must confirm /health and BLE device_id equality.',
  );
  final diagnostic = _map(run['diagnostic']);
  require(
    diagnostic['schema_version'] == 2,
    '$label.diagnostic schema_version must be 2.',
  );
  require(
    DateTime.tryParse(_text(diagnostic['generated_at'])) != null,
    '$label.diagnostic.generated_at must be ISO-8601.',
  );
  final traceId = _text(diagnostic['trace_id']);
  require(traceId.isNotEmpty, '$label.diagnostic.trace_id is required.');
  if (traceId.isNotEmpty) {
    require(traceIds.add(traceId), '$label repeats trace_id $traceId.');
  }
  final events = _maps(diagnostic['connection_events']);
  require(events.isNotEmpty, '$label.connection_events must not be empty.');
  for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
    final event = events[eventIndex];
    require(
      event['schema_version'] == 2,
      '$label.connection_events[$eventIndex] schema_version must be 2.',
    );
    require(
      event['trace_id'] == traceId,
      '$label.connection_events[$eventIndex] trace_id does not match.',
    );
  }
  _validateSecretSafe(diagnostic, '$label.diagnostic', require);

  final nativeEvents = events.where((event) => event['source'] == 'android');
  require(
    nativeEvents.any(
      (event) =>
          _text(event['manufacturer']).toLowerCase().contains('oppo') &&
          event['sdk_int'] is int &&
          (event['sdk_int'] as int) >= 36 &&
          _text(event['apk_sha256']).toLowerCase() == expectedApkSha &&
          _isSha40(event['git_commit']) &&
          _usableText(event['app_version_name']) &&
          _usableText(event['app_version_code']) &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(_text(event['device_address_hash'])),
    ),
    '$label does not contain OPPO API 36 diagnostics for the selected APK.',
  );

  final openStarts = events
      .where(
        (event) => event['event_type'] == 'command_started' && event['command_type'] == 'open_pairing',
      )
      .toList();
  require(openStarts.length == 1, '$label must start open_pairing exactly once.');
  final requestId = openStarts.isEmpty ? '' : _text(openStarts.single['request_id']);
  require(requestId.isNotEmpty, '$label open_pairing request_id is required.');

  bool sameOpenRequest(Map<String, dynamic> event) => event['command_type'] == 'open_pairing' && event['request_id'] == requestId;
  final writes = events.where(
    (event) =>
        sameOpenRequest(event) &&
        event['event_type'] == 'gatt_characteristic_write' &&
        event['operation_name'] == 'write_open_pairing' &&
        _text(event['characteristic_uuid']).toLowerCase() == rc4HfBleProvisioningCommandUuid &&
        event['write_type'] == 'with_response',
  );
  require(
    writes.isNotEmpty,
    '$label has no Write With Response to Provisioning Command.',
  );
  require(
    events.any(
      (event) => sameOpenRequest(event) && event['security_trigger'] == 'encrypted_characteristic_write',
    ),
    '$label does not prove encrypted-characteristic security triggering.',
  );

  final bondEvents = events.where((event) => event['event_type'] == 'bond_state_changed').toList();
  require(
    bondEvents.any((event) => event['bond_state'] == 'bonding'),
    '$label has no BOND_BONDING event.',
  );
  require(
    bondEvents.any((event) => event['bond_state'] == 'bonded'),
    '$label has no BOND_BONDED event.',
  );
  require(
    bondEvents.any((event) => event['system_pairing_interaction'] == true),
    '$label does not prove a system pairing interaction.',
  );

  final retryCounts = events.map((event) => event['retry_count']).whereType<int>();
  require(
    retryCounts.every((count) => count >= 0 && count <= 1),
    '$label contains more than one encrypted retry.',
  );
  final securityFailure = writes.any(
    (event) => const {5, 8, 12, 15}.contains(event['gatt_status']),
  );
  final retryEvents = events
      .where(
        (event) => sameOpenRequest(event) && event['event_type'] == 'security_write_retrying' && event['retry_count'] == 1,
      )
      .toList();
  if (securityFailure) {
    require(
      retryEvents.length == 1,
      '$label security failure must produce exactly one encrypted retry.',
    );
    final restoredUuids = events
        .where(
          (event) => event['event_type'] == 'gatt_notification_descriptor_write' && event['notification_state'] == 'enabled' && event['retry_count'] == 0,
        )
        .map((event) => _text(event['characteristic_uuid']).toLowerCase())
        .toSet();
    require(
      restoredUuids.contains(rc4HfBleNetworkStatusUuid) && restoredUuids.contains(rc4HfBleScanResultsUuid),
      '$label does not prove both notifications were restored.',
    );
  }

  require(
    events.any(
      (event) => sameOpenRequest(event) && event['event_type'] == 'security_write_completed' && event['response_type'] == 'pairing_opened',
    ),
    '$label has no matching pairing_opened completion.',
  );
  require(
    events.any(
      (event) => sameOpenRequest(event) && event['event_type'] == 'command_succeeded' && event['response_type'] == 'pairing_opened',
    ),
    '$label open_pairing command did not succeed.',
  );
  require(
    events.any(
      (event) => event['event_type'] == 'command_succeeded' && event['command_type'] == 'authorize_pairing' && event['response_type'] == 'pairing_authorized',
    ),
    '$label authorize_pairing command did not succeed.',
  );
  require(
    events.every((event) => event['result_code'] != 'ble_bond_timeout'),
    '$label still contains ble_bond_timeout.',
  );
  require(
    events.every(
      (event) => event['operation_name'] != 'bond' && event['operation_name'] != 'create_bond',
    ),
    '$label still uses a generic createBond operation.',
  );

  if (events.any((event) => event['gatt_rebuilt'] == true)) {
    final generations = events.map((event) => event['gatt_instance_id']).whereType<int>().toSet();
    require(
      generations.length >= 2,
      '$label reports a rebuilt GATT without a new GATT generation.',
    );
    require(
      events.any(
        (event) => event['gatt_rebuilt'] == true && event['event_type'] == 'gatt_services_discovered' && event['service_discovery_result'] == 'success',
      ),
      '$label rebuilt GATT has no successful service discovery.',
    );
    require(
      events.any(
        (event) => event['gatt_rebuilt'] == true && event['event_type'] == 'gatt_mtu_changed' && event['result_code'] == 'success',
      ),
      '$label rebuilt GATT has no successful MTU negotiation.',
    );
  }

  final k7 = _map(run['k7']);
  require(k7['pairing_agent_callback'] == true, '$label K7 PairingAgent callback is not confirmed.');
  require(k7['open_pairing_received'] == true, '$label K7 open_pairing is not confirmed.');
  require(k7['authorize_pairing_received'] == true, '$label K7 authorize_pairing is not confirmed.');
  require(k7['request_id'] == requestId, '$label K7 request_id does not match the App trace.');
  _validateEvidenceFile(
    evidenceRoot,
    _text(k7['log_file']),
    '$label K7 log',
    require,
    errors,
  );
}

void _validateReconnectCheck(
  Map<String, dynamic> check, {
  required Directory evidenceRoot,
  required void Function(bool, String) require,
  required List<String> errors,
}) {
  require(check['status'] == 'passed', 'reconnect_check.status must be passed.');
  require(check['existing_token_reused'] == true, 'reconnect_check must reuse the existing token.');
  require(check['pairing_code_prompted'] == false, 'reconnect_check must not prompt for a pairing code.');
  require(
    check['accepted_task_continued_after_ble_disconnect'] == true,
    'reconnect_check must confirm accepted box work continued after BLE disconnect.',
  );
  final files = _strings(check['evidence_files']);
  require(files.isNotEmpty, 'reconnect_check.evidence_files is required.');
  for (final file in files) {
    _validateEvidenceFile(evidenceRoot, file, 'reconnect_check evidence', require, errors);
  }
}

void _validateApprovals(
  Map<String, dynamic> approvals, {
  required Directory evidenceRoot,
  required void Function(bool, String) require,
  required List<String> errors,
}) {
  for (final role in const ['app', 'board', 'qa']) {
    final approval = _map(approvals[role]);
    require(approval['status'] == 'approved', 'approvals.$role must be approved.');
    require(_usableText(approval['reviewer']), 'approvals.$role.reviewer is required.');
    _validateEvidenceFile(
      evidenceRoot,
      _text(approval['evidence_file']),
      'approvals.$role evidence',
      require,
      errors,
    );
  }
}

void _validateEvidenceFile(
  Directory root,
  String path,
  String label,
  void Function(bool, String) require,
  List<String> errors,
) {
  require(path.isNotEmpty, '$label path is required.');
  if (path.isEmpty) return;
  final file = _resolveFile(root, path);
  require(file.existsSync(), '$label file does not exist: $path.');
  if (!file.existsSync()) return;
  require(file.lengthSync() > 0, '$label file is empty: $path.');
  if (_isTextEvidence(file)) {
    try {
      final content = file.readAsStringSync();
      if (_containsPlaintextMac(content)) {
        errors.add('$label contains a plaintext Bluetooth address.');
      }
      if (_containsCredentialText(content)) {
        errors.add('$label contains credential-like material.');
      }
    } on FileSystemException {
      errors.add('$label cannot be read safely.');
    }
  }
}

void _validateSecretSafe(
  Object? value,
  String label,
  void Function(bool, String) require,
) {
  require(!_containsPlaintextMac(value), '$label contains a plaintext Bluetooth address.');
  require(!_containsForbiddenKey(value), '$label contains a forbidden secret field.');
}

bool _containsPlaintextMac(Object? value) {
  if (value is Map) return value.values.any(_containsPlaintextMac);
  if (value is List) return value.any(_containsPlaintextMac);
  return value is String && RegExp(r'\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b').hasMatch(value);
}

bool _containsForbiddenKey(Object? value) {
  if (value is List) return value.any(_containsForbiddenKey);
  if (value is! Map) return false;
  for (final entry in value.entries) {
    final key = entry.key.toString().toLowerCase();
    if (RegExp(
      r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)',
    ).hasMatch(key)) {
      return true;
    }
    if (_containsForbiddenKey(entry.value)) return true;
  }
  return false;
}

bool _containsCredentialText(String content) => RegExp(
  r'(password|passphrase|pairing[_-]?code|pairing[_-]?session[_-]?id|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s,;}]+',
  caseSensitive: false,
).hasMatch(content);

Iterable<String> _findPlaceholders(Object? value, String path) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _findPlaceholders(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (final entry in value.indexed) {
      yield* _findPlaceholders(entry.$2, '$path[${entry.$1}]');
    }
  } else if (value is String &&
      RegExp(
        r'(^|[^a-z])(REQUIRED_|TODO(?:_|$)|PLACEHOLDER(?:_|$))',
        caseSensitive: false,
      ).hasMatch(value)) {
    yield path;
  }
}

bool _isTextEvidence(File file) =>
    const {
      'json',
      'log',
      'txt',
      'md',
      'csv',
      'yaml',
      'yml',
    }.contains(file.path.toLowerCase().split('.').last) &&
    file.lengthSync() <= 10 * 1024 * 1024;

File _resolveFile(Directory root, String path) {
  final file = File(path);
  return file.isAbsolute ? file : File('${root.path}${Platform.pathSeparator}$path');
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? value) => (value as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList(growable: false);
List<String> _strings(Object? value) => (value as List? ?? const []).map(_text).where((value) => value.isNotEmpty).toList(growable: false);
String _text(Object? value) => value?.toString().trim() ?? '';
bool _usableText(Object? value) =>
    _text(value).isNotEmpty &&
    !RegExp(
      r'(^|[^a-z])(REQUIRED_|TODO(?:_|$)|PLACEHOLDER(?:_|$))',
      caseSensitive: false,
    ).hasMatch(_text(value));
bool _isSha40(Object? value) => RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(_text(value));
bool _isSha256(Object? value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(_text(value));

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/acceptance/rc4_hf_ble_03_evidence_validator.dart <evidence.json>',
    );
    exitCode = 64;
    return;
  }
  final evidenceFile = File(arguments.single).absolute;
  if (!evidenceFile.existsSync()) {
    stderr.writeln('Evidence file does not exist: ${evidenceFile.path}');
    exitCode = 66;
    return;
  }
  final document = jsonDecode(await evidenceFile.readAsString());
  final validation = validateRc4HfBle03Evidence(
    document,
    evidenceRoot: evidenceFile.parent,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(validation.toJson()));
  if (!validation.passed) exitCode = 2;
}
