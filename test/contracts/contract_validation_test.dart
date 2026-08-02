import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/contracts/contract_validator.dart';

void main() {
  test('birdbox v1 OpenAPI, refs, schemas and fixtures stay aligned', () async {
    final result = await validateBirdBoxContracts(
      repositoryRoot: Directory.current,
    );

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
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
}
