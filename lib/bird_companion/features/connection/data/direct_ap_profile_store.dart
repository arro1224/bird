import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';

/// Long-lived AP configuration, independent from single-use pairing sessions.
/// Only the encrypted profile store may serialize its secrets.
final class DirectApProfile {
  const DirectApProfile({required this.deviceId, required this.operationId, required this.ssid, required this.passphrase, required this.security, required this.baseUri, this.automaticRestore = true, this.blePlatformId, this.bleName});
  final String deviceId, operationId, ssid, passphrase;
  final WifiSecurity security;
  final Uri baseUri;
  final bool automaticRestore;
  final String? blePlatformId, bleName;

  DirectApProfile withAutomaticRestore(bool enabled) =>
      DirectApProfile(deviceId: deviceId, operationId: operationId, ssid: ssid, passphrase: passphrase, security: security, baseUri: baseUri, automaticRestore: enabled, blePlatformId: blePlatformId, bleName: bleName);

  Map<String, dynamic> toEncryptedJson() => {
    'version': 1,
    'device_id': deviceId,
    'operation_id': operationId,
    'ssid': ssid,
    'passphrase': passphrase,
    'security': security.wireValue,
    'base_uri': baseUri.toString(),
    'automatic_restore': automaticRestore,
    'ble_platform_id': blePlatformId,
    'ble_name': bleName,
  };

  factory DirectApProfile.fromEncryptedJson(Map<String, dynamic> json, String expectedDeviceId) {
    final uri = Uri.tryParse(json['base_uri'] as String? ?? '');
    if (json['version'] != 1 ||
        json['device_id'] != expectedDeviceId ||
        !RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(expectedDeviceId) ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        json['ssid'] is! String ||
        (json['ssid'] as String).isEmpty ||
        json['passphrase'] is! String ||
        json['operation_id'] is! String ||
        json['automatic_restore'] is! bool) {
      throw const FormatException('Invalid encrypted AP profile');
    }
    return DirectApProfile(
      deviceId: expectedDeviceId,
      operationId: json['operation_id'] as String,
      ssid: json['ssid'] as String,
      passphrase: json['passphrase'] as String,
      security: WifiSecurityWireValue.parse(json['security'] as String),
      baseUri: uri,
      automaticRestore: json['automatic_restore'] as bool,
      blePlatformId: json['ble_platform_id'] as String?,
      bleName: json['ble_name'] as String?,
    );
  }

  @override
  String toString() => 'DirectApProfile(configuration: <redacted>, automaticRestore: $automaticRestore)';
}

/// Serializes read-modify-write, so a cancelled attempt cannot resurrect an
/// automatic restore flag via a delayed write. No Hive/pending-file storage.
final class DirectApProfileStore {
  DirectApProfileStore(this.storage);
  final DirectApAuthorizationStore storage;
  Future<void> _writes = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<DirectApProfile?> load(String deviceId) => _serialized(() async {
    final raw = await storage.load(deviceId);
    return raw == null ? null : DirectApProfile.fromEncryptedJson(raw, deviceId);
  });
  Future<void> save(DirectApProfile profile) => _serialized(() => storage.write(profile.deviceId, profile.toEncryptedJson()));
  Future<void> setEnabled(String deviceId, bool enabled) => _serialized(() async {
    final raw = await storage.load(deviceId);
    if (raw == null) return;
    final profile = DirectApProfile.fromEncryptedJson(raw, deviceId);
    await storage.write(deviceId, profile.withAutomaticRestore(enabled).toEncryptedJson());
  });
}
