import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:aves/bird_companion/features/connection/data/ble/ble_protocol_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('B0 keeps the Project 4 review endpoints on frozen birdbox v1', () {
    expect(ApiEndpoints.contractVersion, 'birdbox-v1@1.0.0');
    expect(ApiEndpoints.photoDetail, '/api/v1/files/{fileId}');
    expect(
      ApiEndpoints.photoDecision,
      '/api/v1/files/{fileId}/decision',
    );
    expect(ApiEndpoints.photoHistory, '/api/v1/files/{fileId}/history');

    final openApi =
        jsonDecode(
              File(
                'docs/contracts/birdbox-v1.openapi.yaml',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final paths = openApi['paths'] as Map<String, dynamic>;
    final operation = (paths['/files/{fileId}/decision'] as Map<String, dynamic>)['post'] as Map<String, dynamic>;
    final responses = operation['responses'] as Map<String, dynamic>;

    expect(
      operation['requestBody'],
      isA<Map>().having(
        (value) => (value['content'] as Map)['application/json'],
        'application/json request',
        isA<Map>().having(
          (value) => (value['schema'] as Map)['\$ref'],
          'schema ref',
          './schemas/user-decision-patch.schema.json',
        ),
      ),
    );
    expect(
      (responses['200'] as Map)['\$ref'],
      '#/components/responses/PhotoResponse',
    );
    expect(responses.keys, containsAll(<String>['200', '409', '422']));
  });

  test('B0 keeps decision version semantics and rc4 BLE identity frozen', () {
    final patchSchema =
        jsonDecode(
              File(
                'docs/contracts/schemas/user-decision-patch.schema.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(patchSchema['required'], contains('version'));
    expect(
      ((patchSchema['properties'] as Map)['version'] as Map)['minimum'],
      0,
    );
    expect(patchSchema['additionalProperties'], isFalse);

    expect(BleProtocolConstants.protocolVersion, '1.0-rc4');
    expect(
      BleProtocolConstants.serviceUuid,
      '6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000',
    );
    expect(BleProtocolConstants.fragmentMagic, <int>[0x42, 0x42]);
    expect(BleProtocolConstants.fragmentProtocolVersion, 1);
  });
}
