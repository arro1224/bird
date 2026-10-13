import 'dart:io';
import 'package:crypto/crypto.dart';

List<String> validateLocalBluetoothCaptures(Map<String, dynamic> evidence, Directory directory) {
  if (evidence['schema_version'] != 2 || evidence['evidence_kind'] != 'virtual_birdbox_avd') return [];
  final errors = <String>[];
  String normalized(String path) => Platform.isWindows ? path.replaceAll('\\', '/').toLowerCase() : path;
  final root = Directory(directory.absolute.resolveSymbolicLinksSync());
  final base = normalized(root.path);
  final netsim = evidence['netsim'];
  final captures = netsim is Map ? netsim['pcap_files'] : null;
  if (captures is! List || captures.isEmpty) return ['Actual local Bluetooth PCAP is required.'];
  for (final entry in captures) {
    final relative = entry is Map ? entry['path'] : null;
    if (relative is! String || relative.startsWith('/') || relative.startsWith('\\') || Uri.parse(relative).hasScheme) {
      errors.add('PCAP must use a path within this evidence directory.');
      continue;
    }
    final parts = relative.replaceAll('\\', '/').split('/');
    if (parts.contains('..')) {
      errors.add('PCAP path escapes the evidence directory.');
      continue;
    }
    final capture = File.fromUri(root.uri.resolve(parts.join('/')));
    if (!capture.existsSync() || !normalized(capture.resolveSymbolicLinksSync()).startsWith('$base/')) {
      errors.add('PCAP is missing or resolves outside the evidence directory.');
    } else if (capture.lengthSync() == 0 || sha256.convert(capture.readAsBytesSync()).toString() != entry['sha256']) {
      errors.add('Actual PCAP SHA-256 differs from the recorded capture.');
    }
  }
  return errors;
}
