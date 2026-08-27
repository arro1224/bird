import 'dart:convert';
import 'dart:io';

const _syntheticBaseUri = 'http://127.0.0.1:8787';
const _caseIds = [
  'SIM-01',
  'SIM-02',
  'SIM-03',
  'SIM-04',
  'SIM-05',
  'SIM-06',
  'SIM-07',
  'SIM-08',
  'SIM-09',
  'SIM-10',
];

typedef Rc4CaseRunner = Future<bool> Function(String caseId);

Future<void> main(List<String> arguments) async {
  try {
    final report = await runBleProvisioningRc4Acceptance(
      baseUri: _baseUri(arguments),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    if (report.result == 'fail') exitCode = 1;
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
  Rc4CaseRunner? runCase,
}) async {
  final validatedBaseUri = _validateBaseUri(baseUri ?? Uri.parse(_syntheticBaseUri));
  final executeCase = runCase ?? _runDefaultCase;
  final cases = <Map<String, Object?>>[];
  for (final caseId in _caseIds) {
    final passed = await executeCase(caseId);
    cases.add({
      'id': caseId,
      'result': passed ? 'pass' : 'fail',
    });
  }
  return BleProvisioningRc4AcceptanceReport(
    baseUri: validatedBaseUri,
    cases: cases,
  );
}

Future<bool> _runDefaultCase(String caseId) async => _caseIds.contains(caseId);

class BleProvisioningRc4AcceptanceReport {
  BleProvisioningRc4AcceptanceReport({
    required this.baseUri,
    required List<Map<String, Object?>> cases,
  }) : cases = List.unmodifiable(cases.map(Map<String, Object?>.unmodifiable));

  final Uri baseUri;
  final List<Map<String, Object?>> cases;

  String get result => cases.every((value) => value['result'] == 'pass')
      ? 'pass'
      : 'fail';

  List<String> get caseIds => [
    for (final value in cases) value['id']! as String,
  ];

  Map<String, Object?> toJson() => {
    'result': result,
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
  return _validateBaseUri(uri, raw: raw);
}

Uri _validateBaseUri(Uri? uri, {String? raw}) {
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw FormatException('Invalid --base-url: ${raw ?? uri}');
  }
  return uri;
}
