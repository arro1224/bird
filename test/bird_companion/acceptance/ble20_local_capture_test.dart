import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/ble11/local_capture_validator.dart';

void main() {
  test('capture receiver reads actual bytes and rejects hash tampering or traversal', () {
    final directory = Directory.systemTemp.createTempSync('ble20-capture-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final capture = File('${directory.path}/test.pcap')..writeAsBytesSync([1, 2, 3]);
    final row = {'path': 'test.pcap', 'sha256': sha256.convert(capture.readAsBytesSync()).toString()};
    final evidence = <String, dynamic>{
      'schema_version': 2,
      'evidence_kind': 'virtual_birdbox_avd',
      'netsim': {
        'pcap_files': [row],
      },
    };
    expect(validateLocalBluetoothCaptures(evidence, directory), isEmpty);
    capture.writeAsBytesSync([1, 2, 4]);
    expect(validateLocalBluetoothCaptures(evidence, directory).single, contains('SHA-256'));
    row['path'] = '../outside.pcap';
    expect(validateLocalBluetoothCaptures(evidence, directory).single, contains('escapes'));
    row['path'] = 'missing.pcap';
    expect(validateLocalBluetoothCaptures(evidence, directory).single, contains('missing'));
  });
  test('physical phone evidence requires no netsim capture', () {
    expect(validateLocalBluetoothCaptures({'schema_version': 2, 'evidence_kind': 'virtual_birdbox_phone'}, Directory.current), isEmpty);
  });
}
