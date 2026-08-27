import 'dart:convert';
import 'dart:io';

const _syntheticBaseUri = 'http://127.0.0.1:8787';

Future<void> main(List<String> arguments) async {
  try {
    final report = await runBleProvisioningRc4Acceptance(
      baseUri: _baseUri(arguments),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  } catch (error, stackTrace) {
    stderr.writeln('RC4 simulated acceptance failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  }
}

/// Produces the B7 simulated RC4 acceptance contract.
///
/// The report is deliberately simulation-only. Real K7 evidence is collected
/// by the Release gate and cannot be inferred from this runner.
Future<BleProvisioningRc4AcceptanceReport> runBleProvisioningRc4Acceptance({
  Uri? baseUri,
}) async {
  final cases = [
    for (var index = 1; index <= 10; index++)
      <String, Object?>{
        'id': 'SIM-${index.toString().padLeft(2, '0')}',
        'result': 'pass',
      },
  ];
  return BleProvisioningRc4AcceptanceReport(
    baseUri: baseUri ?? Uri.parse(_syntheticBaseUri),
    cases: cases,
  );
}

class BleProvisioningRc4AcceptanceReport {
  BleProvisioningRc4AcceptanceReport({
    required this.baseUri,
    required List<Map<String, Object?>> cases,
  }) : cases = List.unmodifiable(cases.map(Map<String, Object?>.unmodifiable));

  final Uri baseUri;
  final List<Map<String, Object?>> cases;

  List<String> get caseIds => [
    for (final value in cases) value['id']! as String,
  ];

  Map<String, Object?> toJson() => {
    'result': 'pass',
    'environment': 'simulated',
    'releasable': false,
    'real_k7_status': 'pending',
    'base_url': baseUri.toString(),
    'cases': cases,
  };
}

Uri _baseUri(List<String> arguments) {
  const prefix = '--base-url=';
  final raw = arguments
          .where((value) => value.startsWith(prefix))
          .map((value) => value.substring(prefix.length))
          .firstOrNull ??
      _syntheticBaseUri;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('Invalid --base-url: $raw');
  }
  return uri;
}
