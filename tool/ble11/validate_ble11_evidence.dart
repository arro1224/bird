import 'dart:convert';
import 'dart:io';

import 'ble11_evidence_validator.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart tool/ble11/validate_ble11_evidence.dart <evidence.json>');
    exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('BLE-11 evidence file does not exist: ${file.path}');
    exitCode = 66;
    return;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    stderr.writeln('BLE-11 evidence root must be an object.');
    exitCode = 65;
    return;
  }
  final validation = validateBle11Evidence(Map<String, dynamic>.from(decoded));
  if (!validation.passed) {
    for (final error in validation.errors) {
      stderr.writeln('FAIL: $error');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('BLE-11 simulated evidence passed fail-closed validation.');
}
