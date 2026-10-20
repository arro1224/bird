import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/features/connection/data/connection_api.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_ble_data_source.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';
import 'fakes/fake_birdbox_dpp_platform.dart';
import 'direct_ap_handoff_test.dart' show MemoryHandoffStorage;

void main() {
  final endpoint = Platform.environment['BIRDBOX_DIRECT_AP_BASE'];
  test('real Python status, RC4 redemption and authenticated HTTP handoff after transient network failure', () async {
    final baseUri = Uri.parse(endpoint!);
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final response = await (await http.getUrl(baseUri.resolve('/local-direct-ap-fixture'))).close();
    final fixture = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    final deviceId = fixture['device_id'] as String;
    final clientId = fixture['client_id'] as String;
    final pendingAuth = MemoryDirectApAuthorizationStore();
    await pendingAuth.write(deviceId, {'device_id': deviceId, 'client_id': clientId, 'pairing_session_id': fixture['pairing_session_id'], 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()});
    final client = ApiClient();
    final credentials = MemorySecureSessionStore();
    final events = EventClient();
    final session = SessionCoordinator(client, events, credentials);
    final pairing = PairingApi(client);
    final api = ConnectionApi(client, pairing, session);
    final deviceInfo = ProvisioningDeviceInfo.fromJson(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map<String, dynamic>);
    final networkStatus = ProvisioningEvent.fromJson(jsonDecode(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync()) as Map<String, dynamic>).payload as ProvisioningNetworkStatus;
    final ble = FakeBirdBoxBleDataSource(deviceInfo: deviceInfo, networkStatus: networkStatus);
    final repository = ProvisioningRepositoryImpl(
      ble: ble,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: clientId),
      credentialStore: credentials,
      healthApi: HealthApi(client),
      pairingApi: pairing,
      directApAuthorizationStore: pendingAuth,
    );
    var calls = 0;
    final cubit = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      retryUnit: const Duration(milliseconds: 5),
      verify: (pending, token) async {
        if (++calls == 1) throw const SocketException('simulated old WLAN');
        await api.verifyDirectApIdentity(baseUri, deviceId, token);
        await repository.prepareDirectApHttp(pending.completion, token);
        final status = await api.handshake(baseUri, NetworkMode.directAp, cancelToken: token, expectedDeviceId: deviceId);
        expect(status.connection.id, deviceId);
      },
    );
    try {
      await cubit.begin(PendingDirectAp(deviceId: deviceId, baseUri: baseUri, operationId: 'python-direct-ap'));
      final terminal = await cubit.stream.firstWhere((state) => {DirectApHandoffPhase.directApConnected, DirectApHandoffPhase.failure}.contains(state.phase)).timeout(const Duration(seconds: 15));
      expect(terminal.phase, DirectApHandoffPhase.directApConnected, reason: terminal.message);
      expect(calls, 2);
      expect((await credentials.read(deviceId))?.clientId, clientId);
      expect(await pendingAuth.load(deviceId), isNull);
      expect(ble.requests, isEmpty, reason: 'Handoff must not issue another BLE command');
    } finally {
      await cubit.close();
      await repository.dispose();
      await session.dispose();
      await events.dispose();
      await client.dispose();
    }
  }, skip: endpoint == null ? 'Set BIRDBOX_DIRECT_AP_BASE and run tool/direct_ap_python_fixture.py; real HTTP not configured.' : false);
}
