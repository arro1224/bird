import 'dart:convert';
import 'dart:io';

const bleScanB7Scenarios = <String>{
  'cold_start_permission_granted',
  'bluetooth_enabled_after_launch',
  'denied_then_granted',
  'foreground_resume',
  'timeout_manual_retry',
  'multiple_boxes',
};

final class BleScanEvidenceValidation {
  const BleScanEvidenceValidation({
    required this.errors,
    required this.successesByScenario,
    required this.runsByScenario,
  });

  final List<String> errors;
  final Map<String, int> successesByScenario;
  final Map<String, int> runsByScenario;

  bool get passed => errors.isEmpty;
}

BleScanEvidenceValidation validateBleScanB7Evidence(
  Object? document, {
  int minimumRunsPerScenario = 10,
}) {
  final errors = <String>[];
  final runsByScenario = <String, int>{};
  final successesByScenario = <String, int>{};
  final sessionIds = <String>{};
  if (document is! Map) {
    return const BleScanEvidenceValidation(
      errors: ['Evidence root must be a JSON object.'],
      successesByScenario: {},
      runsByScenario: {},
    );
  }
  final runs = document['runs'];
  if (runs is! List) {
    return const BleScanEvidenceValidation(
      errors: ['Evidence must contain a runs array.'],
      successesByScenario: {},
      runsByScenario: {},
    );
  }

  for (var index = 0; index < runs.length; index++) {
    final run = runs[index];
    if (run is! Map) {
      errors.add('runs[$index] must be an object.');
      continue;
    }
    final scenario = run['scenario'];
    if (scenario is! String || !bleScanB7Scenarios.contains(scenario)) {
      errors.add('runs[$index] has an unknown scenario.');
      continue;
    }
    runsByScenario.update(scenario, (value) => value + 1, ifAbsent: () => 1);
    final session = run['session'];
    if (session is! Map) {
      errors.add('runs[$index].session must be an object.');
      continue;
    }
    final sessionMap = Map<String, dynamic>.from(session);
    if (sessionMap['schema_version'] != 3) {
      errors.add('runs[$index].session schema_version must be 3.');
    }
    final sessionId = sessionMap['scan_session_id'];
    if (sessionId is! String || sessionId.isEmpty) {
      errors.add('runs[$index] is missing scan_session_id.');
    } else if (!sessionIds.add(sessionId)) {
      errors.add('runs[$index] repeats scan_session_id $sessionId.');
    }
    for (final key in const [
      'started_at',
      'ended_at',
      'permission_before',
      'permission_after',
      'scan_permission_before',
      'scan_permission_after',
      'connect_permission_before',
      'connect_permission_after',
      'location_permission_before',
      'location_permission_after',
      'adapter_before',
      'adapter_after',
      'location_service_before',
      'location_service_after',
      'scan_mode',
      'raw_result_count',
      'unique_device_count',
      'accepted_count',
      'filtered_count',
      'reason_counts',
      'observations',
      'end_reason',
    ]) {
      if (!sessionMap.containsKey(key)) {
        errors.add('runs[$index].session is missing $key.');
      }
    }
    final raw = sessionMap['raw_result_count'];
    final accepted = sessionMap['accepted_count'];
    final filtered = sessionMap['filtered_count'];
    if (raw is int && accepted is int && filtered is int && raw != accepted + filtered) {
      errors.add('runs[$index] has inconsistent scan counts.');
    }
    final observations = sessionMap['observations'];
    final uniqueDeviceCount = sessionMap['unique_device_count'];
    if (observations is! List) {
      errors.add('runs[$index].session observations must be an array.');
    } else {
      final hashes = <String>{};
      for (var observationIndex = 0; observationIndex < observations.length; observationIndex++) {
        final observation = observations[observationIndex];
        if (observation is! Map) {
          errors.add(
            'runs[$index].session.observations[$observationIndex] must be an object.',
          );
          continue;
        }
        final addressHash = observation['address_hash'];
        if (addressHash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(addressHash)) {
          errors.add(
            'runs[$index].session.observations[$observationIndex] has an invalid address_hash.',
          );
        } else {
          hashes.add(addressHash);
        }
        final recordLength = observation['scan_record_length'];
        if (recordLength is int && recordLength > 0) {
          final redactedHex = observation['scan_record_redacted_hex'];
          if (redactedHex is! String || redactedHex.isEmpty || !RegExp(r'^(?:[0-9a-f]{2})+$').hasMatch(redactedHex) || redactedHex.length > 1024) {
            errors.add(
              'runs[$index].session.observations[$observationIndex] has an invalid scan_record_redacted_hex.',
            );
          }
          if (observation['scan_record_truncated'] is! bool) {
            errors.add(
              'runs[$index].session.observations[$observationIndex] is missing scan_record_truncated.',
            );
          }
        }
        for (final key in const [
          'service_uuids',
          'manufacturer_data_present',
          'manufacturer_data_length',
          'accepted',
          'reason_code',
        ]) {
          if (!observation.containsKey(key)) {
            errors.add(
              'runs[$index].session.observations[$observationIndex] is missing $key.',
            );
          }
        }
      }
      if (uniqueDeviceCount is int && ((raw is int && raw <= 500 && uniqueDeviceCount != hashes.length) || (raw is int && raw > 500 && uniqueDeviceCount < hashes.length))) {
        errors.add('runs[$index] has inconsistent unique device count.');
      }
      if (raw is int && raw <= 500 && observations.length != raw) {
        errors.add('runs[$index] is missing raw scan observations.');
      }
    }
    if (_containsPlaintextMac(sessionMap)) {
      errors.add('runs[$index] contains a plaintext Bluetooth address.');
    }
    if (_containsSecretKey(sessionMap)) {
      errors.add('runs[$index] contains a forbidden device or secret field.');
    }
    if (accepted is int && accepted > 0 && sessionMap['first_candidate_at'] is String) {
      successesByScenario.update(scenario, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  for (final scenario in bleScanB7Scenarios) {
    final count = runsByScenario[scenario] ?? 0;
    if (count < minimumRunsPerScenario) {
      errors.add('$scenario has $count/$minimumRunsPerScenario required runs.');
    }
  }
  return BleScanEvidenceValidation(
    errors: List.unmodifiable(errors),
    successesByScenario: Map.unmodifiable(successesByScenario),
    runsByScenario: Map.unmodifiable(runsByScenario),
  );
}

bool _containsPlaintextMac(Object? value) {
  if (value is List) return value.any(_containsPlaintextMac);
  if (value is Map) return value.values.any(_containsPlaintextMac);
  return value is String && RegExp(r'\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b').hasMatch(value);
}

bool _containsSecretKey(Object? value) {
  if (value is List) return value.any(_containsSecretKey);
  if (value is! Map) return false;
  for (final entry in value.entries) {
    final key = entry.key.toString().toLowerCase().replaceAll('_', '');
    if (const {
      'deviceid',
      'localname',
      'manufacturerpayload',
      'pairingcode',
      'password',
      'passphrase',
      'token',
    }.contains(key)) {
      return true;
    }
    if (_containsSecretKey(entry.value)) return true;
  }
  return false;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/acceptance/ble_scan_b7_evidence_validator.dart <evidence.json>');
    exitCode = 64;
    return;
  }
  final document = jsonDecode(await File(arguments.single).readAsString());
  final validation = validateBleScanB7Evidence(document);
  for (final scenario in bleScanB7Scenarios) {
    final runs = validation.runsByScenario[scenario] ?? 0;
    final successes = validation.successesByScenario[scenario] ?? 0;
    stdout.writeln('$scenario: $successes/$runs discovered a BirdBox candidate');
  }
  if (!validation.passed) {
    for (final error in validation.errors) {
      stderr.writeln('ERROR: $error');
    }
    exitCode = 1;
  }
}
