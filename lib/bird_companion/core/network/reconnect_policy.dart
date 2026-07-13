class ReconnectPolicy {
  const ReconnectPolicy({this.maxAttempts = 5, this.initialDelay = const Duration(seconds: 1), this.maxDelay = const Duration(seconds: 20)});

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  Duration delayFor(int attempt) {
    final factor = 1 << attempt.clamp(0, 5);
    final delay = Duration(milliseconds: initialDelay.inMilliseconds * factor);
    return delay > maxDelay ? maxDelay : delay;
  }
}
