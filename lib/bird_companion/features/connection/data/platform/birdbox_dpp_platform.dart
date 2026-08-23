enum DppLaunchOutcome { systemAccepted, userCancelled, activityUnavailable, invalidUri, timedOut, failed }

final class DppCapability {
  const DppCapability({required this.apiLevelSupported, required this.easyConnectSupported, required this.activityAvailable});
  final bool apiLevelSupported;
  final bool easyConnectSupported;
  final bool activityAvailable;

  bool get supported => apiLevelSupported && easyConnectSupported && activityAvailable;
}

final class DppLaunchResult {
  const DppLaunchResult({required this.outcome, this.systemResultCode});
  final DppLaunchOutcome outcome;
  final String? systemResultCode;

  bool get systemAccepted => outcome == DppLaunchOutcome.systemAccepted;
}

abstract interface class BirdBoxDppPlatform {
  Future<DppCapability> checkCapability();
  Future<DppLaunchResult> launchEasyConnect(Uri dppUri);
  Future<void> clearTransientUri();
}
