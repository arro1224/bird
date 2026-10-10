abstract interface class DiagnosticStorage {
  T? read<T>(String key);
  Future<void> write(String key, Object? value);
  Future<void> remove(String key);
}
