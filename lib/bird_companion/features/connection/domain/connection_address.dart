class ConnectionAddress {
  const ConnectionAddress._();

  /// Parses an address supplied by a QR code or the manual-entry form.
  /// Only local box addresses are accepted: private/loopback IPs and `.local`
  /// host names. This prevents a scanned or pasted public URL from becoming
  /// the application's global API endpoint.
  static Uri? tryParse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final withScheme = value.contains('://') ? value : 'http://$value';
    return normalize(Uri.tryParse(withScheme));
  }

  static Uri? normalize(Uri? value) {
    if (value == null || (value.scheme != 'http' && value.scheme != 'https')) return null;
    if (value.host.isEmpty || value.userInfo.isNotEmpty || value.query.isNotEmpty || value.fragment.isNotEmpty) return null;
    if (value.path.isNotEmpty && value.path != '/') return null;
    try {
      if (value.hasPort && (value.port < 1 || value.port > 65535)) return null;
    } on FormatException {
      return null;
    }
    final host = value.host.toLowerCase();
    if (!_isLocalHost(host)) return null;
    return Uri(scheme: value.scheme, host: host, port: value.hasPort ? value.port : null);
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    if (host == '::1' || host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final values = parts.map(int.tryParse).toList();
    if (values.any((part) => part == null || part < 0 || part > 255)) return false;
    final first = values[0]!;
    final second = values[1]!;
    return first == 10 || first == 127 || first == 192 && second == 168 || first == 172 && second >= 16 && second <= 31 || first == 169 && second == 254;
  }
}
