/// Always collect actual events, including failures before the first command.
/// A file-export failure must not replace the original transport failure.
Future<T> capturePhoneFlow<T>({
  required Future<T> Function() operation,
  required Future<void> Function(Object? failure) collect,
}) async {
  T value;
  try {
    value = await operation();
  } catch (error, stack) {
    try {
      await collect(error);
    } catch (exportError) {
      // Diagnostic metadata is persisted by the collector before rethrowing.
      // ignore: avoid_print
      print('BLE22_CAPTURE_FAILED ${exportError.runtimeType}');
    }
    Error.throwWithStackTrace(error, stack);
  }
  await collect(null);
  return value;
}
