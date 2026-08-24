import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter/services.dart';

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
  Future<bool> ensurePermissions();
  Future<WifiJoinResult> joinDirectAp({required String ssid, required String passphrase});
  Future<void> bindProcessToNetwork(BirdBoxWifiNetwork network);
  Future<void> releaseNetwork();
  BirdBoxWifiNetwork? get boundNetwork;
  Future<void> dispose();
}

final class MethodChannelBirdBoxWifiPlatform implements BirdBoxWifiPlatform {
  factory MethodChannelBirdBoxWifiPlatform({
    MethodChannel channel = const MethodChannel(
      'bird_companion/birdbox_wifi/methods',
    ),
  }) => MethodChannelBirdBoxWifiPlatform._(channel);

  MethodChannelBirdBoxWifiPlatform._(this._channel);

  final MethodChannel _channel;
  BirdBoxWifiNetwork? _boundNetwork;

  @override
  BirdBoxWifiNetwork? get boundNetwork => _boundNetwork;

  @override
  Future<bool> ensurePermissions() async => (await _invoke<bool>('ensurePermissions')) ?? false;

  @override
  Future<WifiJoinResult> joinDirectAp({
    required String ssid,
    required String passphrase,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('joinDirectAp', {
      'ssid': ssid,
      'passphrase': passphrase,
    });
    if (raw == null) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.systemWifiJoinDenied,
        retryable: true,
      );
    }
    final outcome = switch (raw['outcome']) {
      'joined' => WifiJoinOutcome.joined,
      'user_cancelled' => WifiJoinOutcome.userCancelled,
      'denied_no_internet' => WifiJoinOutcome.deniedNoInternet,
      'system_denied' => WifiJoinOutcome.systemDenied,
      _ => WifiJoinOutcome.failed,
    };
    final handle = raw['handle'];
    final returnedSsid = raw['ssid'];
    final network = outcome == WifiJoinOutcome.joined && handle is String && handle.isNotEmpty && returnedSsid is String ? BirdBoxWifiNetwork(handle: handle, ssid: returnedSsid) : null;
    return WifiJoinResult(
      outcome: outcome,
      network: network,
      errorCode: raw['errorCode'] as String?,
    );
  }

  @override
  Future<void> bindProcessToNetwork(BirdBoxWifiNetwork network) async {
    await _invoke<void>('bindProcessToNetwork', {'handle': network.handle});
    _boundNetwork = network;
  }

  @override
  Future<void> releaseNetwork() async {
    await _invoke<void>('releaseNetwork');
    _boundNetwork = null;
  }

  @override
  Future<void> dispose() async {
    await _invoke<void>('dispose');
    _boundNetwork = null;
  }

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ProvisioningException(
        code: switch (error.code) {
          'wifi_permission_denied' => ProvisioningErrorCode.localNetworkPermissionDenied,
          'wifi_unsupported' => ProvisioningErrorCode.capabilityUnsupported,
          'wifi_join_denied' => ProvisioningErrorCode.systemWifiJoinDenied,
          _ => ProvisioningErrorCode.networkInternalError,
        },
        retryable: error.code == 'wifi_join_failed',
        diagnosticMessage: 'Android Wi-Fi platform error: ${error.code}',
      );
    }
  }
}
