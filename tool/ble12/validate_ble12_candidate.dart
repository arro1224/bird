import 'dart:convert';
import 'dart:io';

import 'ble12_candidate_validator.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final manifestFile = File(options.manifestPath).absolute;
  if (!manifestFile.existsSync()) {
    stderr.writeln('BLE-12 manifest does not exist: ${manifestFile.path}');
    exitCode = 66;
    return;
  }
  Map<String, dynamic> manifest;
  try {
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is! Map) throw const FormatException('root must be an object');
    manifest = Map<String, dynamic>.from(decoded);
  } on FormatException catch (error) {
    stderr.writeln('BLE-12 manifest is invalid JSON: ${error.message}');
    exitCode = 65;
    return;
  }
  final result = await validateBle12Candidate(
    manifest: manifest,
    packageRoot: manifestFile.parent,
    repositoryRoot: options.repositoryPath.isEmpty ? null : Directory(options.repositoryPath).absolute,
  );
  stdout.writeln(
    const JsonEncoder.withIndent(' ').convert(
      result.toJson(manifest: manifest),
    ),
  );
  if (!result.passed) exitCode = 2;
}

final class _Options {
  const _Options({required this.manifestPath, required this.repositoryPath});

  final String manifestPath;
  final String repositoryPath;

  factory _Options.parse(List<String> arguments) {
    String value(String name, String fallback) {
      final prefix = '--$name=';
      for (final argument in arguments) {
        if (argument.startsWith(prefix)) {
          return argument.substring(prefix.length).trim();
        }
      }
      return fallback;
    }

    return _Options(
      manifestPath: value(
        'manifest',
        'outputs/RC4-HF-BLE-12/candidate-manifest.json',
      ),
      repositoryPath: value('repository', ''),
    );
  }
}
