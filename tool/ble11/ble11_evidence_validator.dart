import 'dart:convert';

final class Ble11EvidenceValidation {
  const Ble11EvidenceValidation(this.errors);

  final List<String> errors;
  bool get passed => errors.isEmpty;
}

Ble11EvidenceValidation validateBle11Evidence(Map<String, dynamic> value) {
  final errors = <String>[];

  void require(bool condition, String message) {
    if (!condition) errors.add(message);
  }

  require(value['schema_version'] == 1, 'schema_version must be 1.');
  require(
    value['evidence_kind'] == 'simulated',
    'evidence_kind must remain simulated.',
  );
  require(
    value['hardware_status'] == 'pending',
    'hardware_status must remain pending for AVD evidence.',
  );
  final scenario = value['scenario'];
  const scenarios = {
    'success',
    'auto_bond',
    'fallback_once',
    'disconnect_once',
  };
  require(scenarios.contains(scenario), 'scenario is unsupported.');
  require(value['test_exit_code'] == 0, 'integration test did not pass.');

  final emulator = _map(value['emulator']);
  final version = emulator?['version'];
  require(
    version is String && _atLeast365(version),
    'Android Emulator 36.5+ is required.',
  );
  require(
    emulator?['app_avd'] is String && emulator?['box_avd'] is String,
    'both AVD identities are required.',
  );
  require(
    emulator?['app_avd'] != emulator?['box_avd'],
    'app_avd and box_avd must be distinct.',
  );
  final netsim = _map(value['netsim']);
  require(
    netsim?['pcap_requested'] == true,
    'netsim PCAP capture must be requested.',
  );
  require(
    netsim?['ble_rssi_dbm'] is int,
    'netsim BLE RSSI must be recorded.',
  );
  final pcapFiles = _maps(netsim?['pcap_files']);
  require(pcapFiles.isNotEmpty, 'netsim did not produce a PCAP artifact.');
  require(
    pcapFiles.every(
      (file) => file['path'] is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(file['sha256']?.toString() ?? ''),
    ),
    'every PCAP artifact must include its relative path and SHA-256.',
  );

  final appEvidence = _map(value['app_evidence']);
  require(appEvidence != null, 'app_evidence is missing.');
  require(
    appEvidence?['evidence_kind'] == 'simulated',
    'app evidence must remain simulated.',
  );
  require(
    appEvidence?['hardware_status'] == 'pending',
    'app evidence hardware_status must remain pending.',
  );
  require(
    appEvidence?['scenario'] == scenario,
    'app evidence scenario does not match the host run.',
  );
  require(
    appEvidence?['response_type'] == 'pairing_opened',
    'matching pairing_opened response is required.',
  );

  final appEvents = _maps(appEvidence?['events']);
  final appTypes = appEvents.map((event) => event['event_type']).whereType<String>().toList(growable: false);
  require(
    appTypes.contains('notifications_ready'),
    'both required notification subscriptions were not restored.',
  );
  require(
    appTypes.contains('command_succeeded'),
    'the production command did not complete.',
  );

  final boxEvents = _maps(value['box_events']);
  final boxTypes = boxEvents.map((event) => event['event_type']).whereType<String>().toList(growable: false);
  require(
    boxTypes.contains('advertising_started'),
    'virtual BirdBox advertising evidence is missing.',
  );
  final serviceAdded = boxEvents.where(
    (event) => event['event_type'] == 'service_added' && _map(event['fields'])?['characteristic_count'] == 5,
  );
  require(
    serviceAdded.isNotEmpty,
    'virtual BirdBox must expose exactly five characteristics.',
  );
  require(
    boxTypes.contains('command_received'),
    'virtual BirdBox did not receive a complete RC4 command.',
  );

  if (scenario == 'auto_bond') {
    require(
      appTypes.contains('security_recovery_completed'),
      'auto_bond did not restore secured GATT.',
    );
    require(
      !appTypes.contains('conditional_bond_fallback_started'),
      'auto_bond must not use the conditional fallback.',
    );
    _requireOneRetry(appEvents, require);
  } else if (scenario == 'fallback_once') {
    require(
      appTypes.contains('conditional_bond_fallback_started'),
      'fallback_once did not start the audited fallback.',
    );
    require(
      appTypes.contains('security_recovery_completed'),
      'fallback_once did not restore secured GATT.',
    );
    _requireOneRetry(appEvents, require);
    final injected = boxEvents.where(
      (event) => event['event_type'] == 'security_failure_injected',
    );
    require(
      injected.length == 1,
      'fallback_once must inject exactly one security failure.',
    );
    final retries = boxEvents.where((event) {
      if (event['event_type'] != 'encrypted_retry_observed') return false;
      final fields = _map(event['fields']);
      return fields?['matches_original'] == true && fields?['bonded'] == true;
    });
    require(
      retries.length == 1,
      'virtual BirdBox must observe one byte-identical retry after Bond.',
    );
  } else if (scenario == 'disconnect_once') {
    require(
      boxTypes.where((type) => type == 'disconnect_injected').length == 1,
      'disconnect_once must inject exactly one disconnect.',
    );
    require(
      appTypes.contains('disconnected'),
      'production transport did not observe the injected disconnect.',
    );
    require(
      boxTypes.where((type) => type == 'stale_notification_injected').length == 1,
      'disconnect recovery must inject one stale response before the replacement response.',
    );
    final generations = _ints(appEvidence?['connection_generations']).toSet();
    require(
      generations.length >= 2,
      'disconnect recovery requires at least two connection generations.',
    );
  }

  final encoded = jsonEncode(value);
  require(
    !RegExp(
      r'\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b',
      caseSensitive: false,
    ).hasMatch(encoded),
    'evidence contains a complete MAC address.',
  );
  require(
    !RegExp(
      r'"(?:password|passphrase|token|secret|pairing_code)"\s*:\s*"(?!\[REDACTED\])[^\"]+"',
      caseSensitive: false,
    ).hasMatch(encoded),
    'evidence contains credential-like material.',
  );

  return Ble11EvidenceValidation(List.unmodifiable(errors));
}

void _requireOneRetry(
  List<Map<String, dynamic>> appEvents,
  void Function(bool, String) require,
) {
  final retries = appEvents.where(
    (event) => event['event_type'] == 'security_write_retrying' && event['retry_count'] == 1,
  );
  require(
    retries.length == 1,
    'security recovery must retry the exact command once.',
  );
  require(
    appEvents.any(
      (event) => event['gatt_rebuilt'] == true && event['gatt_instance_id'] is int && event['connection_generation'] is int,
    ),
    'Bond recovery must report a rebuilt GATT instance.',
  );
}

bool _atLeast365(String value) {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(value);
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 36 || (major == 36 && minor >= 5);
}

Map<String, dynamic>? _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _maps(Object? value) => value is List ? value.map(_map).whereType<Map<String, dynamic>>().toList(growable: false) : const [];

List<int> _ints(Object? value) => value is List ? value.whereType<int>().toList(growable: false) : const [];
