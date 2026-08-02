class ProtocolCompatibilityException implements Exception {
  const ProtocolCompatibilityException(this.field, this.reason);

  final String field;
  final String reason;

  @override
  String toString() => '盒子协议不兼容：$field $reason';
}

abstract final class ProtocolValidation {
  static String requiredId(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw ProtocolCompatibilityException(key, '必须是非空字符串');
    }
    return raw.trim();
  }

  static int nonNegativeInt(
    Map<String, dynamic> json,
    String key, {
    int fallback = 0,
  }) {
    final raw = json[key];
    if (raw == null) return fallback;
    if (raw is! num || !raw.isFinite || raw < 0 || raw.toDouble() != raw.toInt()) {
      throw ProtocolCompatibilityException(key, '必须是非负整数');
    }
    return raw.toInt();
  }

  static int? optionalNonNegativeInt(
    Map<String, dynamic> json,
    String key,
  ) {
    if (json[key] == null) return null;
    return nonNegativeInt(json, key);
  }

  static double unitInterval(
    Map<String, dynamic> json,
    String key, {
    double fallback = 0,
  }) {
    final raw = json[key];
    if (raw == null) return fallback;
    if (raw is! num || !raw.isFinite || raw < 0 || raw > 1) {
      throw ProtocolCompatibilityException(key, '必须位于 0–1 范围');
    }
    return raw.toDouble();
  }

  static double? optionalNonNegativeDouble(
    Map<String, dynamic> json,
    String key,
  ) {
    final raw = json[key];
    if (raw == null) return null;
    if (raw is! num || !raw.isFinite || raw < 0) {
      throw ProtocolCompatibilityException(key, '必须是非负数');
    }
    return raw.toDouble();
  }

  static DateTime? optionalDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    final raw = json[key];
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) {
      throw ProtocolCompatibilityException(key, '必须是 ISO-8601 时间');
    }
    return parsed;
  }
}
