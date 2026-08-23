import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/features/connection/data/ble/ble_message_codec.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = BleMessageCodec();

  Uint8List fixture(String name) => Uint8List.fromList(File('test/contracts/fixtures/$name').readAsBytesSync());

  test('encodes the frozen request envelope without logging payloads', () {
    const request = BleCommandRequest(
      type: BleCommandType.authorizePairing,
      requestId: '550e8400-e29b-41d4-a716-446655440000',
      clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
      payload: {'pairing_code': '123456'},
    );
    final json = Map<String, dynamic>.from(jsonDecode(utf8.decode(codec.encodeRequest(request))) as Map);

    expect(json.keys, ['protocol_version', 'type', 'request_id', 'client_id', 'payload']);
    expect(json['type'], 'authorize_pairing');
    expect(request.toString(), isNot(contains('123456')));
  });

  test('strictly decodes Device Info and Network Status fixtures', () {
    final info = codec.decodeDeviceInfo(fixture('ble-device-info.rc4.json'));
    final status = codec.decodeNetworkStatus(fixture('ble-network-status.rc4.json'));

    expect(info.deviceId, 'bbx-82f41c9e7a3d4b68a1501e21e536c649');
    expect(status.activeMode, ProvisioningNetworkMode.directAp);
  });

  test('decodes a strict error envelope into a local typed error', () {
    final response = codec.decodeResponse(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'protocol_version': '1.0-rc4',
            'type': 'error',
            'request_id': '550e8400-e29b-41d4-a716-446655440000',
            'device_id': 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
            'ok': false,
            'error': {'code': 'AUTHORIZATION_FAILED', 'message': 'secret backend detail', 'retryable': false, 'retry_after_ms': 0},
          }),
        ),
      ),
    );

    expect(response, isA<BleFailureResponse>());
    final error = (response as BleFailureResponse).error;
    expect(error.code, ProvisioningErrorCode.authorizationFailed);
    expect(error.toString(), isNot(contains('secret backend detail')));
  });

  test('rejects unknown envelope fields, malformed UTF-8 and invalid identifiers', () {
    final valid = jsonDecode(utf8.decode(fixture('ble-network-status.rc4.json'))) as Map<String, dynamic>;
    final unknown = Map<String, dynamic>.from(valid)..['extra'] = true;
    const invalidRequest = BleCommandRequest(type: BleCommandType.getNetworkStatus, requestId: 'not-a-uuid', clientId: 'also-not-a-uuid');

    expect(() => codec.decodeResponse(Uint8List.fromList(utf8.encode(jsonEncode(unknown)))), throwsA(isA<ProvisioningProtocolException>()));
    expect(() => codec.decodeResponse(Uint8List.fromList([0xC3, 0x28])), throwsA(isA<ProvisioningProtocolException>()));
    expect(() => codec.encodeRequest(invalidRequest), throwsA(isA<ProvisioningProtocolException>()));
  });
}
