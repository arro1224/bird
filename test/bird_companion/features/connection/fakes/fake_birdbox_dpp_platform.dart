import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';

final class FakeBirdBoxDppPlatform implements BirdBoxDppPlatform {
  FakeBirdBoxDppPlatform({this.capability = const DppCapability(apiLevelSupported: false, easyConnectSupported: false, activityAvailable: false)});

  DppCapability capability;
  final List<DppLaunchResult> _launchResults = [];
  int clearCount = 0;
  int launchCount = 0;

  void queueLaunchResult(DppLaunchResult result) => _launchResults.add(result);

  @override
  Future<DppCapability> checkCapability() async => capability;

  @override
  Future<DppLaunchResult> launchEasyConnect(Uri dppUri) async {
    if (!capability.supported) throw StateError('DPP capability is unavailable');
    if (dppUri.scheme.toLowerCase() != 'dpp') throw ArgumentError.value('<redacted>', 'dppUri', 'must use DPP scheme');
    launchCount += 1;
    if (_launchResults.isEmpty) throw StateError('No fake DPP launch result queued');
    return _launchResults.removeAt(0);
  }

  @override
  Future<void> clearTransientUri() async {
    clearCount += 1;
  }
}
