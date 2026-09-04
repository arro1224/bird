import 'dart:convert';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';

/// Parses the standard `WIFI:` QR payload without retaining the raw value.
WifiQrCredentials parseWifiQrCredentials(String raw) {
  final value = raw.trim();
  if (!value.startsWith('WIFI:') || !value.endsWith(';;')) {
    throw const FormatException('Not a standard Wi-Fi QR payload.');
  }

  final fields = <String, String>{};
  final body = value.substring(5, value.length - 2);
  for (final token in _splitEscaped(body, ';')) {
    if (token.isEmpty) continue;
    final separator = _firstUnescaped(token, ':');
    if (separator <= 0) {
      throw const FormatException('Malformed Wi-Fi QR field.');
    }
    final key = token.substring(0, separator).toUpperCase();
    if (!const {'T', 'S', 'P', 'H', 'B'}.contains(key) || fields.containsKey(key)) {
      throw const FormatException('Unsupported or duplicate Wi-Fi QR field.');
    }
    fields[key] = _unescape(token.substring(separator + 1));
  }

  final ssid = fields['S'];
  if (ssid == null || ssid.isEmpty || utf8.encode(ssid).length > 32 || _hasControlCharacter(ssid)) {
    throw const FormatException('Invalid Wi-Fi SSID.');
  }

  final security = _parseSecurity(fields['T']);
  final password = fields['P'];
  if (security == WifiSecurity.open) {
    if (password != null && password.isNotEmpty) {
      throw const FormatException('Open Wi-Fi must not contain a password.');
    }
  } else if (!_validPersonalPassword(password)) {
    throw const FormatException('Invalid personal Wi-Fi password.');
  }

  final hidden = switch (fields['H']?.toLowerCase()) {
    null || '' || 'false' => false,
    'true' => true,
    _ => throw const FormatException('Invalid hidden-network flag.'),
  };
  final rawBssid = fields['B']?.trim();
  final bssid = rawBssid == null || rawBssid.isEmpty ? null : rawBssid.toUpperCase();
  if (bssid != null && !RegExp(r'^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(bssid)) {
    throw const FormatException('Invalid Wi-Fi BSSID.');
  }

  return WifiQrCredentials(
    ssid: ssid,
    security: security,
    password: security == WifiSecurity.open ? null : password,
    bssid: bssid,
    hidden: hidden,
  );
}

WifiQrCredentials? tryParseWifiQrCredentials(String? raw) {
  if (raw == null) return null;
  try {
    return parseWifiQrCredentials(raw);
  } on FormatException {
    return null;
  }
}

WifiSecurity _parseSecurity(String? raw) => switch (raw?.trim().toUpperCase()) {
  null || '' || 'NOPASS' => WifiSecurity.open,
  'WPA' || 'WPA2' => WifiSecurity.wpa2Personal,
  'WPA3' || 'SAE' => WifiSecurity.wpa3Personal,
  'WPA2/WPA3' || 'WPA2-WPA3' => WifiSecurity.wpa2Wpa3Transition,
  _ => throw const FormatException('Unsupported Wi-Fi security type.'),
};

bool _validPersonalPassword(String? password) {
  if (password == null || _hasControlCharacter(password)) return false;
  if (RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(password)) return true;
  final length = password.runes.length;
  return length >= 8 && length <= 63;
}

bool _hasControlCharacter(String value) => value.runes.any(
  (rune) => rune < 0x20 || rune == 0x7f,
);

List<String> _splitEscaped(String value, String separator) {
  final result = <String>[];
  final current = StringBuffer();
  var escaped = false;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (escaped) {
      current
        ..write('\\')
        ..write(character);
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == separator) {
      result.add(current.toString());
      current.clear();
    } else {
      current.write(character);
    }
  }
  if (escaped) throw const FormatException('Dangling Wi-Fi QR escape.');
  result.add(current.toString());
  return result;
}

int _firstUnescaped(String value, String separator) {
  var escaped = false;
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if (escaped) {
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else if (character == separator) {
      return index;
    }
  }
  return -1;
}

String _unescape(String value) {
  final result = StringBuffer();
  var escaped = false;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (escaped) {
      if (!const {'\\', ';', ',', ':', '"'}.contains(character)) {
        throw const FormatException('Unsupported Wi-Fi QR escape.');
      }
      result.write(character);
      escaped = false;
    } else if (character == '\\') {
      escaped = true;
    } else {
      result.write(character);
    }
  }
  if (escaped) throw const FormatException('Dangling Wi-Fi QR escape.');
  return result.toString();
}
