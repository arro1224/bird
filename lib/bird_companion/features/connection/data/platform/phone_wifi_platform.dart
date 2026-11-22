import 'package:flutter/services.dart';

/// Why the phone's own Wi-Fi name could not be read. Only used to explain a missing prefill,
/// so the provisioning form never silently pretends the field was filled.
enum PhoneWifiReadFailure { permissionDenied, approximateLocation, locationDisabled, unavailable, unsupported }

/// Hint for the provisioning form: the phone's current Wi-Fi name, or the reason it is unusable.
///
/// The value is a UI hint only. It is not persisted, not forwarded to diagnostics and never
/// treated as the target network — the user still confirms the name and types the password.
final class PhoneWifiSsid {
  const PhoneWifiSsid({this.ssid, this.failure});

  const PhoneWifiSsid.readable(String value) : ssid = value, failure = null;
  const PhoneWifiSsid.unreadable(PhoneWifiReadFailure reason) : ssid = null, failure = reason;

  final String? ssid;
  final PhoneWifiReadFailure? failure;

  bool get isReadable => ssid != null && ssid!.isNotEmpty;

  /// Copy shown under the entry card; intentionally says nothing about passwords.
  String get hint => switch (failure) {
    null => '已填入当前 Wi-Fi 名称，请输入密码',
    PhoneWifiReadFailure.permissionDenied => '未授予定位权限，读不到当前 Wi-Fi 名称，可手动填写',
    PhoneWifiReadFailure.approximateLocation => '定位权限只有大致位置，读不到 Wi-Fi 名称；可在系统设置改为精确位置，或手动填写',
    PhoneWifiReadFailure.locationDisabled => '系统定位已关闭，读不到当前 Wi-Fi 名称，可手动填写',
    PhoneWifiReadFailure.unsupported => '此设备不支持读取当前 Wi-Fi 名称，请手动填写',
    PhoneWifiReadFailure.unavailable => '读不到当前 Wi-Fi 名称，可手动填写或选择网络',
  };

  @override
  String toString() => 'PhoneWifiSsid(ssid: ${isReadable ? '<read>' : 'absent'}, failure: ${failure?.name})';
}

/// Why a gallery import could not produce an image.
enum PhoneWifiPickFailure { unavailable, unreadable }

final class PhoneWifiPickException implements Exception {
  const PhoneWifiPickException(this.failure);

  final PhoneWifiPickFailure failure;

  @override
  String toString() => 'PhoneWifiPickException(${failure.name})';
}

/// Narrow platform surface for the two task-2 additions:
/// reading the phone's Wi-Fi name for prefill, and importing a QR photo through the system picker.
///
/// Kept separate from [BirdBoxWifiPlatform] on purpose: the direct-AP join contract must not grow
/// UI-only capabilities that every existing fake would then have to implement.
abstract interface class PhoneWifiPlatform {
  Future<PhoneWifiSsid> currentSsid();

  /// Absolute path of a private cache copy of the picked image, or `null` when the user cancelled.
  Future<String?> pickQrImage();
}

final class MethodChannelPhoneWifiPlatform implements PhoneWifiPlatform {
  const MethodChannelPhoneWifiPlatform({
    this.channel = const MethodChannel(channelName),
  });

  static const channelName = 'bird_companion/birdbox_wifi/methods';

  final MethodChannel channel;

  @override
  Future<PhoneWifiSsid> currentSsid() async {
    try {
      final raw = await channel.invokeMapMethod<String, Object?>('currentSsid');
      if (raw == null) return const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.unavailable);
      final ssid = raw['ssid'];
      if (ssid is String && ssid.trim().isNotEmpty) {
        return PhoneWifiSsid.readable(ssid.trim());
      }
      return PhoneWifiSsid.unreadable(switch (raw['reason']) {
        'permission_denied' => PhoneWifiReadFailure.permissionDenied,
        'permission_approximate' => PhoneWifiReadFailure.approximateLocation,
        'location_disabled' => PhoneWifiReadFailure.locationDisabled,
        _ => PhoneWifiReadFailure.unavailable,
      });
    } on PlatformException {
      return const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.unsupported);
    } on MissingPluginException {
      return const PhoneWifiSsid.unreadable(PhoneWifiReadFailure.unsupported);
    }
  }

  @override
  Future<String?> pickQrImage() async {
    try {
      return await channel.invokeMethod<String>('pickWifiQrImage');
    } on PlatformException catch (error) {
      throw PhoneWifiPickException(switch (error.code) {
        'picker_read_failed' => PhoneWifiPickFailure.unreadable,
        _ => PhoneWifiPickFailure.unavailable,
      });
    } on MissingPluginException {
      throw const PhoneWifiPickException(PhoneWifiPickFailure.unavailable);
    }
  }
}
