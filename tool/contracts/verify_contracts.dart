import 'dart:io';

import 'contract_validator.dart';

Future<void> main(List<String> arguments) async {
  final unknown = arguments.where((argument) => argument != '--strict-baseline').toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown arguments: ${unknown.join(' ')}');
    stderr.writeln(
      'Usage: dart run tool/contracts/verify_contracts.dart [--strict-baseline]',
    );
    exitCode = 64;
    return;
  }

  final result = await validateBirdBoxContracts(
    repositoryRoot: Directory.current,
    strictBaseline: arguments.contains('--strict-baseline'),
  );
  if (result.isValid) {
    stdout.writeln(
      'PASS $contractVersion: OpenAPI, refs, schemas and fixtures are valid.',
    );
    return;
  }

  stderr.writeln('FAIL $contractVersion (${result.errors.length} errors)');
  for (final error in result.errors) {
    stderr.writeln('- $error');
  }
  exitCode = 1;
}
