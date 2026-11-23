import 'dart:convert';

import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_profile_store.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
final _profile = DirectApProfile(deviceId: _id, operationId: 'op_profile', ssid: 'test-ap', passphrase: 'test-only-password', security: WifiSecurity.wpa3Personal, baseUri: Uri.parse('http://192.0.2.1:8080'), blePlatformId: 'opaque-hint');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted AP profile survives single-use authorization deletion', () async {
    const channel = MethodChannel('bird_companion/secure_session');
    final encryptedBoundary = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['deviceId'] as String;
      switch (call.method) {
        case 'read':
          return encryptedBoundary[key];
        case 'write':
          encryptedBoundary[key] = args['payload'] as String;
          return null;
        case 'delete':
          encryptedBoundary.remove(key);
          return null;
      }
      throw StateError('Unexpected method');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    const authorization = EncryptedDirectApAuthorizationStore();
    final profiles = DirectApProfileStore(const EncryptedDirectApAuthorizationStore(namespace: 'direct-ap-profile:v1'));
    await profiles.save(_profile);
    await authorization.write(_id, {'pairing_session_id': 'test-only-one-use'});
    await authorization.remove(_id);
    final restored = await profiles.load(_id);
    expect(restored?.security, WifiSecurity.wpa3Personal);
    expect(restored?.passphrase, _profile.passphrase);
    expect(encryptedBoundary.keys, ['direct-ap-profile:v1:$_id']);
    expect(jsonDecode(encryptedBoundary.values.single), isNot(contains('pairing_session_id')));
    expect(restored.toString(), isNot(contains(_profile.passphrase)));
    expect(restored.toString(), isNot(contains(_profile.ssid)));
  });

  test('serialized cancellation persists across a new store instance', () async {
    final storage = MemoryDirectApAuthorizationStore();
    final store = DirectApProfileStore(storage);
    final save = store.save(_profile);
    final cancel = store.setEnabled(_id, false);
    await Future.wait([save, cancel]);
    expect((await DirectApProfileStore(storage).load(_id))?.automaticRestore, false);
  });

  test('rejects swapped identity and unknown version without poisoning later reads', () async {
    final storage = MemoryDirectApAuthorizationStore();
    final store = DirectApProfileStore(storage);
    await storage.write(_id, {..._profile.toEncryptedJson(), 'device_id': 'bbx-11111111111111111111111111111111'});
    await expectLater(store.load(_id), throwsFormatException);
    await storage.write(_id, {..._profile.toEncryptedJson(), 'version': 2});
    await expectLater(store.load(_id), throwsFormatException);
    await store.save(_profile);
    expect((await store.load(_id))?.blePlatformId, 'opaque-hint');
  });
}
