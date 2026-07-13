extension JsonValueReader on Map<String, dynamic> {
  String? stringOrNull(String key) => this[key]?.toString();

  int? intOrNull(String key) {
    final value = this[key];
    return switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value),
      _ => null,
    };
  }

  double? doubleOrNull(String key) {
    final value = this[key];
    return switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
  }

  bool? boolOrNull(String key) {
    final value = this[key];
    return switch (value) {
      bool() => value,
      num() => value != 0,
      String() => value == 'true' || value == '1',
      _ => null,
    };
  }

  Map<String, dynamic>? mapOrNull(String key) {
    final value = this[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<dynamic> listOrEmpty(String key) => this[key] is List ? List<dynamic>.from(this[key] as List) : const [];
}
