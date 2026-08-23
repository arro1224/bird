import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

import '../../tool/contracts/contract_validator.dart';

void main() {
  test('birdbox v1 OpenAPI, refs, schemas and fixtures stay aligned', () async {
    final result = await validateBirdBoxContracts(
      repositoryRoot: Directory.current,
    );

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
  });

  test('B0 freeze rejects any change to an existing v1 artifact', () {
    final temporaryRoot = Directory.systemTemp.createTempSync(
      'birdbox-v1-freeze-',
    );
    addTearDown(() => temporaryRoot.deleteSync(recursive: true));

    final freeze =
        jsonDecode(
              File(
                'docs/contracts/birdbox-v1-freeze.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final artifacts = Map<String, dynamic>.from(
      freeze['artifacts'] as Map,
    );
    for (final relativePath in artifacts.keys) {
      final source = File(relativePath);
      final target = File(
        '${temporaryRoot.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      target.parent.createSync(recursive: true);
      source.copySync(target.path);
    }
    final freezeTarget = File(
      '${temporaryRoot.path}${Platform.pathSeparator}docs${Platform.pathSeparator}contracts${Platform.pathSeparator}birdbox-v1-freeze.json',
    );
    freezeTarget.parent.createSync(recursive: true);
    File('docs/contracts/birdbox-v1-freeze.json').copySync(freezeTarget.path);

    final copiedOpenApi = File(
      '${temporaryRoot.path}${Platform.pathSeparator}docs${Platform.pathSeparator}contracts${Platform.pathSeparator}birdbox-v1.openapi.yaml',
    );
    copiedOpenApi.writeAsStringSync(
      '${copiedOpenApi.readAsStringSync()}\n',
    );

    final result = validateBirdBoxContractFreeze(
      repositoryRoot: temporaryRoot,
    );

    expect(
      result.errors,
      contains(
        'frozen contract drift: docs/contracts/birdbox-v1.openapi.yaml changed; do not modify birdbox-v1@1.0.0. Create an independent versioned interface proposal.',
      ),
    );
  });

  test('App v1 endpoints remain centralized and match frozen OpenAPI paths', () {
    final openApi =
        jsonDecode(
              File('docs/contracts/birdbox-v1.openapi.yaml').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final openApiPaths = (openApi['paths'] as Map<String, dynamic>).keys.map((path) => path.replaceAll(RegExp(r'\{[^}]+\}'), '{}')).toSet();

    final endpointsSource = File(
      'lib/bird_companion/core/network/api_endpoints.dart',
    ).readAsStringSync();
    final endpointPaths = RegExp(r"'(/api/v1/[^']+)'?").allMatches(endpointsSource).map((match) => match.group(1)!.substring('/api/v1'.length)).map((path) => path.replaceAll(RegExp(r'\{[^}]+\}'), '{}')).toSet();
    expect(endpointPaths, openApiPaths);

    final strayDeclarations = Directory('lib/bird_companion')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => !file.path.endsWith(
            '${Platform.pathSeparator}core${Platform.pathSeparator}network${Platform.pathSeparator}api_endpoints.dart',
          ),
        )
        .where((file) => file.readAsStringSync().contains('/api/v1/'))
        .map((file) => file.path)
        .toList();
    expect(
      strayDeclarations,
      isEmpty,
      reason: 'v1 paths must only be declared in ApiEndpoints',
    );
  });

  test('strict B0 baseline remains closed while real-box inputs are missing', () async {
    final result = await validateBirdBoxContracts(
      repositoryRoot: Directory.current,
      strictBaseline: true,
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors,
      contains('strict baseline: missing box.firmware_sha'),
    );
    expect(
      result.errors,
      contains('strict baseline: missing owners.protocol.contact'),
    );
  });

  test('rc4 fixtures are accepted by the App strict models', () {
    final deviceInfo = Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map);
    final networkStatus = Map<String, dynamic>.from(jsonDecode(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync()) as Map);

    expect(ProvisioningDeviceInfo.fromJson(deviceInfo).protocolVersion, '1.0-rc4');
    expect(ProvisioningEvent.fromJson(networkStatus).type, ProvisioningEventType.networkStatus);
  });
}
