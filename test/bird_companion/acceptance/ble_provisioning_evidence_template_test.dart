import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedCaseIds = [
    'K7-01',
    'K7-02',
    'K7-03',
    'K7-04',
    'K7-05',
    'K7-06',
    'K7-07',
    'K7-08',
    'K7-09',
    'K7-10',
  ];

  test('real-device RC4 evidence template is pending and fail-closed', () {
    final file = File(
      'docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json',
    );

    expect(file.existsSync(), isTrue);
    final template = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    expect(template['schema_version'], 1);
    expect(template['final_result'], 'pending');
    expect(template['real_k7_status'], 'pending');
    expect(template['releasable'], isFalse);
    expect(template['environment'], isA<Map>());
    final environment = Map<String, dynamic>.from(template['environment'] as Map);
    expect(environment['real_hardware'], isFalse);
    expect(environment['android_devices'], isNotEmpty);
    expect(environment['routers'], isNotEmpty);

    final cases = (template['cases'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList();
    expect(cases.map((item) => item['id']), expectedCaseIds);
    expect(
      cases,
      everyElement(
        predicate<Map<String, dynamic>>((item) {
          return item['status'] == 'pending' &&
              item['summary'] is String &&
              item['device_ids'] is List &&
              (item['device_ids'] as List).isNotEmpty &&
              item['router_ids'] is List &&
              item['evidence'] is List &&
              (item['evidence'] as List).isEmpty;
        }),
      ),
    );

    final redaction = Map<String, dynamic>.from(template['redaction'] as Map);
    expect(redaction['reviewed'], isFalse);
    expect(redaction['reviewer'], startsWith('REQUIRED_'));
    expect(redaction['statement'], startsWith('REQUIRED_'));
    expect(redaction['report'], startsWith('REQUIRED_'));
    final approvals = Map<String, dynamic>.from(template['approvals'] as Map);
    expect((approvals['protocol'] as Map)['status'], 'pending');
    expect((approvals['qa_release'] as Map)['status'], 'pending');

    final serialized = jsonEncode(template).toLowerCase();
    expect(serialized, isNot(contains('"status":"passed"')));
    expect(serialized, isNot(contains('"result":"pass"')));
    for (final secret in [
      'password',
      'passphrase',
      'token',
      'pairing_code',
      'dpp:k:',
      'aa:bb:cc:dd:ee:ff',
    ]) {
      expect(serialized, isNot(contains(secret)));
    }

    final requiredPlaceholders = [
      'captured_at',
      'serial',
      'manufacturer',
      'model',
      'os_version',
      'operator',
      'location',
      'git_sha',
      'build_mode',
      'certificate_sha256',
      'apk_sha256',
      'device_id',
      'device_model',
      'hardware_serial',
      'firmware_sha',
      'evidence_summary',
      'reviewer',
      'statement',
      'report',
    ];
    for (final field in requiredPlaceholders) {
      final values = _findFieldValues(template, field).toList();
      expect(
        serialized,
        contains('required_'),
        reason: 'template must retain explicit REQUIRED_* placeholders',
      );
      expect(values, isNotEmpty, reason: '$field must be present in the template');
      expect(
        values,
        everyElement(startsWith('REQUIRED_')),
        reason: '$field must use an explicit REQUIRED_* placeholder',
      );
    }
  });
}

Iterable<String> _findFieldValues(Object? value, String fieldName) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key.toString() == fieldName && entry.value is String) {
        yield entry.value as String;
      }
      yield* _findFieldValues(entry.value, fieldName);
    }
  } else if (value is List) {
    for (final item in value) {
      yield* _findFieldValues(item, fieldName);
    }
  }
}
