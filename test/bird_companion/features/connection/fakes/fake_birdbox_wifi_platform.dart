import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';

final class FakeBirdBoxWifiPlatform implements BirdBoxWifiPlatform {
  bool permissionGranted = true;
  final List<WifiJoinResult> _joinResults = [];
  final List<String> requestedSsids = [];
  int releaseCount = 0;
  BirdBoxWifiNetwork? _boundNetwork;
  final StreamController<WifiNetworkLoss> _networkLosses = StreamController<WifiNetworkLoss>.broadcast(sync: true);

  @override
  Stream<WifiNetworkLoss> get networkLosses => _networkLosses.stream;

  void loseNetwork({String reason = 'network_lost'}) {
    final network = _boundNetwork;
    if (network == null) return;
    _boundNetwork = null;
    _networkLosses.add(WifiNetworkLoss(handle: network.handle, ssid: network.ssid, reason: reason));
  }

  @override
  Future<bool> ensurePermissions() async => permissionGranted;

  void queueJoinResult(WifiJoinResult result) => _joinResults.add(result);

  @override
  Future<WifiJoinResult> joinDirectAp({required String ssid, required String passphrase}) async {
    requestedSsids.add(ssid);
    if (_joinResults.isEmpty) throw StateError('No fake Wi-Fi join result queued');
    return _joinResults.removeAt(0);
  }

  @override
  Future<void> bindProcessToNetwork(BirdBoxWifiNetwork network) async {
    _boundNetwork = network;
  }

  @override
  Future<void> releaseNetwork() async {
    releaseCount += 1;
    _boundNetwork = null;
  }

  @override
  BirdBoxWifiNetwork? get boundNetwork => _boundNetwork;

  @override
  Future<void> dispose() async {
    await releaseNetwork();
    await _networkLosses.close();
  }
}
