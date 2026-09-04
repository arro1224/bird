import 'dart:async';

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

final class WifiNetworkLoss {
  const WifiNetworkLoss({required this.handle, required this.ssid, required this.reason});

  final String handle;
  final String ssid;
  final String reason;

  @override
  String toString() => 'WifiNetworkLoss(handle: <opaque>, ssid: <redacted>, reason: $reason)';
}

abstract interface class BirdBoxWifiPlatform {
  Stream<WifiNetworkLoss> get networkLosses;
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
    Stream<Object?>? networkEvents,
  }) {
    final platform = MethodChannelBirdBoxWifiPlatform._(channel);
    platform._networkEventSubscription = (networkEvents ?? const EventChannel('bird_companion/birdbox_wifi/network_events').receiveBroadcastStream()).listen(
      platform._handleNetworkEvent,
      onError: platform._networkLosses.addError,
    );
    return platform;
  }

  MethodChannelBirdBoxWifiPlatform._(this._channel);

  final MethodChannel _channel;
  final StreamController<WifiNetworkLoss> _networkLosses = StreamController<WifiNetworkLoss>.broadcast(sync: true);
  late final StreamSubscription<Object?> _networkEventSubscription;
  BirdBoxWifiNetwork? _boundNetwork;
  bool _disposed = false;

  @override
  Stream<WifiNetworkLoss> get networkLosses => _networkLosses.stream;

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
    final errorCode = raw['errorCode'];
    if (errorCode != null && errorCode is! String) {
      throw const ProvisioningProtocolException('wifi_join.errorCode', 'must be a string or null');
    }
    final network = outcome == WifiJoinOutcome.joined && handle is String && handle.isNotEmpty && returnedSsid is String ? BirdBoxWifiNetwork(handle: handle, ssid: returnedSsid) : null;
    if (outcome == WifiJoinOutcome.joined && network == null) {
      throw const ProvisioningProtocolException('wifi_join', 'joined outcome requires an opaque handle and SSID');
    }
    return WifiJoinResult(
      outcome: outcome,
      network: network,
      errorCode: errorCode as String?,
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
    if (_disposed) return;
    _disposed = true;
    try {
      await _invoke<void>('dispose');
    } finally {
      _boundNetwork = null;
      await _networkEventSubscription.cancel();
      await _networkLosses.close();
    }
  }

  void _handleNetworkEvent(Object? raw) {
    try {
      if (raw is! Map) {
        throw const ProvisioningProtocolException('wifi_network_event', 'must be a map');
      }
      final event = Map<Object?, Object?>.from(raw);
      if (event['type'] != 'lost') {
        throw const ProvisioningProtocolException('wifi_network_event.type', 'must be lost');
      }
      final handle = event['handle'];
      final ssid = event['ssid'];
      final reason = event['reason'];
      if (handle is! String || handle.isEmpty || ssid is! String || reason is! String || reason.isEmpty) {
        throw const ProvisioningProtocolException('wifi_network_event', 'contains invalid fields');
      }
      if (_boundNetwork?.handle == handle) _boundNetwork = null;
      _networkLosses.add(WifiNetworkLoss(handle: handle, ssid: ssid, reason: reason == 'network_lost' ? reason : 'unknown'));
    } catch (error, stackTrace) {
      _networkLosses.addError(error, stackTrace);
    }
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
          'wifi_bind_failed' => ProvisioningErrorCode.networkSwitchFailed,
          'invalid_request' => ProvisioningErrorCode.invalidRequest,
          _ => ProvisioningErrorCode.networkInternalError,
        },
        retryable: error.code == 'wifi_join_failed' || error.code == 'wifi_bind_failed' || error.code == 'invalid_state',
        diagnosticMessage: 'Android Wi-Fi platform error: ${error.code}',
      );
    }
  }
}
