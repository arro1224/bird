import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';

void main() {
  final now = DateTime.utc(2026, 11, 19);
  final info = ProvisioningDeviceInfo.fromJson(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map<String, dynamic>);
  const clientId = '10000000-0000-4000-8000-000000000001';
  late MemorySecureSessionStore credentials;
  late MemoryDirectApAuthorizationStore pending;
  late ProvisioningRepositoryImpl repository;
  late ApiClient api;
  setUp(() {
    credentials = MemorySecureSessionStore();
    pending = MemoryDirectApAuthorizationStore();
    api = ApiClient();
    final status = ProvisioningEvent.fromJson(jsonDecode(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync()) as Map<String, dynamic>).payload as ProvisioningNetworkStatus;
    repository = ProvisioningRepositoryImpl(
      ble: FakeBirdBoxBleDataSource(deviceInfo: info, networkStatus: status),
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: clientId),
      credentialStore: credentials,
      directApAuthorizationStore: pending,
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
      clock: () => now,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await api.dispose();
  });

  Map<String, dynamic> authorization() => {'device_id': info.deviceId, 'client_id': clientId, 'pairing_session_id': 'test-session', 'expires_at': now.add(const Duration(minutes: 5)).toIso8601String()};

  test('no authorization requires pairing; readiness checks preserve a fresh one-use session', () async {
    expect(await repository.hasHttpAuthorization(info.deviceId), false);
    final record = authorization();
    await pending.write(info.deviceId, record);
    expect(await repository.hasHttpAuthorization(info.deviceId), true);
    expect(await repository.hasHttpAuthorization(info.deviceId), true);
    expect(await pending.load(info.deviceId), record);
    await pending.remove(info.deviceId);
    expect(await repository.hasHttpAuthorization(info.deviceId), false);
  });

  test('expired, malformed and other-device pending authorizations never enable the shortcut', () async {
    for (final patch in [
      {'expires_at': now.subtract(const Duration(seconds: 1)).toIso8601String()},
      {'client_id': 'not-a-client-uuid'},
      {'pairing_session_id': ''},
      {'device_id': 'bbx-ffffffffffffffffffffffffffffffff'},
      {'expires_at': 'invalid'},
    ]) {
      await pending.write(info.deviceId, {...authorization(), ...patch});
      expect(await repository.hasHttpAuthorization(info.deviceId), false);
    }
  });

  test('a valid saved credential allows reconnect; an expired credential does not', () async {
    Future<void> save(DateTime expires) =>
        credentials.write(SessionCredential(deviceId: info.deviceId, baseUri: Uri.parse('http://192.0.2.2:8787'), accessToken: 'synthetic-test-token', expiresAt: expires, apiVersion: 'v1', clientId: clientId));
    await save(now.add(const Duration(days: 1)));
    expect(await repository.hasHttpAuthorization(info.deviceId), true);
    await save(now.subtract(const Duration(seconds: 1)));
    expect(await repository.hasHttpAuthorization(info.deviceId), false);
  });

  test('missing, expired, consumed and invalid authorizations have distinct actionable messages', () {
    String message(ProvisioningErrorCode code) => directApErrorMessage(ProvisioningException(code: code, retryable: false));
    expect(message(ProvisioningErrorCode.authorizationRequired), contains('尚未取得'));
    expect(message(ProvisioningErrorCode.authorizationRequired), isNot(contains('已经使用')));
    expect(message(ProvisioningErrorCode.pairingSessionExpired), contains('过期'));
    expect(message(ProvisioningErrorCode.pairingSessionUsed), contains('已经使用'));
    expect(message(ProvisioningErrorCode.pairingSessionInvalid), contains('不匹配'));
  });
}
