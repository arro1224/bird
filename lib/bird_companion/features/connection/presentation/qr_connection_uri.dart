enum QrConnectionResultType { connect, manual }

class QrConnectionResult {
  const QrConnectionResult.connect(this.uri) : type = QrConnectionResultType.connect;

  const QrConnectionResult.manual() : type = QrConnectionResultType.manual, uri = null;

  final QrConnectionResultType type;
  final Uri? uri;
}

Uri? parseBirdBoxConnectionUri(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = Uri.tryParse(value);
  if (parsed == null) return null;

  if (parsed.scheme == 'birdbox') {
    final host = parsed.queryParameters['host']?.trim();
    if (host == null || host.isEmpty) return null;
    final port = int.tryParse(parsed.queryParameters['port'] ?? '');
    if (port != null && (port < 1 || port > 65535)) return null;
    return Uri(
      scheme: parsed.queryParameters['https'] == 'true' ? 'https' : 'http',
      host: host,
      port: port ?? 8080,
    );
  }

  if ((parsed.scheme == 'http' || parsed.scheme == 'https') && parsed.host.isNotEmpty && parsed.userInfo.isEmpty) {
    try {
      if (parsed.hasPort && (parsed.port < 1 || parsed.port > 65535)) return null;
      return parsed;
    } on FormatException {
      return null;
    }
  }
  return null;
}
