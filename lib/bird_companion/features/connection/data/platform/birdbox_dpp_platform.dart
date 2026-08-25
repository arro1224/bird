import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter/services.dart';

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

final class MethodChannelBirdBoxDppPlatform implements BirdBoxDppPlatform {
  factory MethodChannelBirdBoxDppPlatform({
    MethodChannel channel = const MethodChannel(
      'bird_companion/birdbox_dpp/methods',
    ),
  }) => MethodChannelBirdBoxDppPlatform._(channel);

  MethodChannelBirdBoxDppPlatform._(this._channel);

  final MethodChannel _channel;

  @override
  Future<DppCapability> checkCapability() async {
    final raw = await _invoke<Map<Object?, Object?>>('checkCapability');
    return DppCapability(
      apiLevelSupported: raw?['apiLevelSupported'] == true,
      easyConnectSupported: raw?['easyConnectSupported'] == true,
      activityAvailable: raw?['activityAvailable'] == true,
    );
  }

  @override
  Future<DppLaunchResult> launchEasyConnect(Uri dppUri) async {
    final rawUri = dppUri.toString();
    if (dppUri.scheme.toLowerCase() != 'dpp' || !rawUri.endsWith(';;')) {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.systemDppInvalidUri,
        retryable: false,
      );
    }
    // Dart canonicalizes URI schemes to lowercase. Android's Easy Connect
    // activity and the frozen wire contract use the standard uppercase form.
    final platformUri = 'DPP:${rawUri.substring(rawUri.indexOf(':') + 1)}';
    final raw = await _invoke<Map<Object?, Object?>>('launchEasyConnect', {
      'uri': platformUri,
    });
    return DppLaunchResult(
      outcome: switch (raw?['outcome']) {
        'system_accepted' => DppLaunchOutcome.systemAccepted,
        'user_cancelled' => DppLaunchOutcome.userCancelled,
        'activity_unavailable' => DppLaunchOutcome.activityUnavailable,
        'invalid_uri' => DppLaunchOutcome.invalidUri,
        'timed_out' => DppLaunchOutcome.timedOut,
        _ => DppLaunchOutcome.failed,
      },
      systemResultCode: raw?['systemResultCode'] as String?,
    );
  }

  @override
  Future<void> clearTransientUri() => _invoke<void>('clearTransientUri');

  Future<T?> _invoke<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const ProvisioningException(
        code: ProvisioningErrorCode.phoneDppNotSupported,
        retryable: false,
        diagnosticMessage: 'Android Easy Connect channel is unavailable.',
      );
    } on PlatformException catch (error) {
      throw ProvisioningException(
        code: switch (error.code) {
          'dpp_activity_unavailable' => ProvisioningErrorCode.systemDppActivityUnavailable,
          'dpp_invalid_uri' => ProvisioningErrorCode.systemDppInvalidUri,
          'dpp_unsupported' => ProvisioningErrorCode.phoneDppNotSupported,
          _ => ProvisioningErrorCode.systemDppFailed,
        },
        retryable: error.code == 'dpp_launch_failed',
        diagnosticMessage: 'Android Easy Connect platform error: ${error.code}',
      );
    }
  }
}
