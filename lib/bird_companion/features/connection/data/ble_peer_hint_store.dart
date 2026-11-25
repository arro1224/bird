import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';

/// A verified public identity with a replaceable transport hint. No AP or auth.
final class BlePeerHint {
  const BlePeerHint({required this.deviceId, required this.platformId, required this.name, required this.verifiedAt});
  final String deviceId;
  final String? platformId, name;
  final DateTime verifiedAt;

  Map<String, dynamic> toJson() => {'version': 1, 'device_id': deviceId, 'platform_id': platformId, 'name': name, 'verified_at': verifiedAt.toUtc().toIso8601String()};

  static BlePeerHint? parse(Map<String, dynamic> raw, String deviceId) {
    final time = DateTime.tryParse(raw['verified_at']?.toString() ?? '');
    if (raw['version'] != 1 || raw['device_id'] != deviceId || !RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId) || time == null) return null;
    final platform = raw['platform_id'], name = raw['name'];
    if (platform != null && (platform is! String || platform.isEmpty || platform.length > 256) || name != null && (name is! String || name.length > 256)) return null;
    return BlePeerHint(deviceId: deviceId, platformId: platform as String?, name: name as String?, verifiedAt: time);
  }

  @override
  String toString() => 'BlePeerHint(verified peer, transport: <redacted>)';
}

/// Production uses its own Keystore namespace, independent of AP credentials.
final class BlePeerHintStore {
  BlePeerHintStore(this.storage);
  final DirectApAuthorizationStore storage;
  Future<void> _tail = Future<void>.value();
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<BlePeerHint?> load(String id) => _serialized(() async {
    final raw = await storage.load(id);
    return raw == null ? null : BlePeerHint.parse(raw, id);
  });
  Future<void> save(BlePeerHint hint) => _serialized(() => storage.write(hint.deviceId, hint.toJson()));
}
