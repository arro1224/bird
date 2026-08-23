enum WifiJoinOutcome { joined, userCancelled, deniedNoInternet, systemDenied, failed }

final class BirdBoxWifiNetwork {
  const BirdBoxWifiNetwork({required this.handle, required this.ssid});
  final String handle;
  final String ssid;

  @override
  String toString() => 'BirdBoxWifiNetwork(handle: <opaque>, ssid: $ssid)';
}

final class WifiJoinResult {
  const WifiJoinResult({required this.outcome, this.network, this.errorCode});
  final WifiJoinOutcome outcome;
  final BirdBoxWifiNetwork? network;
  final String? errorCode;

  bool get joined => outcome == WifiJoinOutcome.joined && network != null;
}

abstract interface class BirdBoxWifiPlatform {
  Future<WifiJoinResult> joinDirectAp({required String ssid, required String passphrase});
  Future<void> bindProcessToNetwork(BirdBoxWifiNetwork network);
  Future<void> releaseNetwork();
  BirdBoxWifiNetwork? get boundNetwork;
}
