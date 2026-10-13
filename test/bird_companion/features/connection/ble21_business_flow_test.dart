import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../tool/mock_box_server/mock_box_server.dart';

const deviceId = 'bbx-b1e11001b1e11001b1e11001b1e11001';
const clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';

void main() {
  test('Mock session is client bound, expiring and consumed once; renewed grant invalidates old grant', () async {
    var now = DateTime.utc(2026, 10, 11);
    final server = MockBoxServer(deviceId: deviceId, logRequests: false, clock: () => now);
    final uri = await server.start();
    final client = ApiClient();
    addTearDown(() async {
      await client.dispose();
      await server.close();
    });
    final pairing = PairingApi(client);
    Future<void> exchange(String session, {String clientIdentity = clientId}) async {
      await pairing.exchangeSession(uri, deviceId: deviceId, clientId: clientIdentity, pairingSessionId: session, clock: () => now);
    }

    Matcher failure(String code) => throwsA(isA<ApiException>().having((e) => e.code, 'code', code));
    server.registerPairingSession('ps_ble21_first', clientId: clientId, lifetime: const Duration(seconds: 5));
    await expectLater(exchange('ps_ble21_first', clientIdentity: 'a870bcb1-d423-4d66-96f7-f809ce786544'), failure('PAIRING_SESSION_INVALID'));
    now = now.add(const Duration(seconds: 5));
    await expectLater(exchange('ps_ble21_first'), failure('PAIRING_SESSION_EXPIRED'));
    server.registerPairingSession('ps_ble21_second', clientId: clientId, lifetime: const Duration(minutes: 2));
    await expectLater(exchange('ps_ble21_first'), failure('PAIRING_SESSION_INVALID'));
    await exchange('ps_ble21_second');
    await expectLater(exchange('ps_ble21_second'), failure('PAIRING_SESSION_USED'));
    expect(server.lastRc4PairingIncludedCode, isFalse);
  });

  test('stateful debug BLE authorization and real HTTP share full device identity', () async {
    var now = DateTime.utc(2026, 10, 11);
    final server = MockBoxServer(deviceId: deviceId, logRequests: false, clock: () => now);
    final uri = await server.start();
    final client = ApiClient();
    final repository = B7SimulatedProvisioningRepository(baseUri: uri, deviceId: deviceId, clock: () => now);
    addTearDown(() async {
      await repository.dispose();
      await client.dispose();
      await server.close();
    });
    final device = await repository.discoverDevices().first;
    final info = await repository.connect(device);
    await expectLater(repository.startDirectAp(), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.authorizationRequired)));
    await repository.openPairing();
    await expectLater(repository.authorizePairing('000000'), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingCodeInvalid)));
    expect((await repository.openPairing()).attemptsRemaining, 2);
    final grant = await repository.authorizePairing('123456');
    server.registerPairingSession(grant.pairingSessionId, clientId: clientId, lifetime: grant.expiresIn);
    await expectLater(repository.authorizePairing('123456'), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingNotOpen)));
    final ready = repository.events.first;
    final first = await repository.startDirectAp();
    expect((await repository.getNetworkStatus()).busy, isTrue);
    await ready;
    final health = await HealthApi(client).waitForDevice(uri, expectedDeviceId: info.deviceId);
    expect(health.deviceId, deviceId);
    final token = await PairingApi(client).exchangeSession(uri, deviceId: info.deviceId, clientId: clientId, pairingSessionId: grant.pairingSessionId, clock: () => now);
    expect(token.deviceId, info.deviceId);
    final nextReady = repository.events.first;
    final second = await repository.startDirectAp();
    expect(second.operationId, isNot(first.operationId));
    await nextReady;
    now = now.add(const Duration(minutes: 2));
    await expectLater(repository.startDirectAp(), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingSessionExpired)));
    await repository.disconnect();
    await expectLater(repository.startDirectAp(), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.authorizationRequired)));
  });

  test('debug pairing window expiry and rate limit use frozen application errors', () async {
    var now = DateTime.utc(2026, 10, 11);
    final repository = B7SimulatedProvisioningRepository(clock: () => now);
    addTearDown(repository.dispose);
    await repository.connect(await repository.discoverDevices().first);
    await repository.openPairing();
    for (var i = 0; i < 3; i++) {
      await expectLater(repository.authorizePairing('000000'), throwsA(isA<ProvisioningException>()));
    }
    await expectLater(repository.openPairing(), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingRateLimited)));
    now = now.add(const Duration(minutes: 2));
    await expectLater(repository.authorizePairing('123456'), throwsA(isA<ProvisioningException>().having((e) => e.code, 'code', ProvisioningErrorCode.pairingCodeExpired)));
    await repository.openPairing();
    await repository.authorizePairing('123456');
  });
}
