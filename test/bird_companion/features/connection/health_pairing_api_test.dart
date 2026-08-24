import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/mock_box_server/mock_box_server.dart';

const _deviceId = 'bbx-82f41c9e7a3d4b68a1501e21e536c649';
const _clientId = 'a870bcb1-d423-4d66-96f7-f809ce786543';
const _pairingSessionId = 'ps_rc4_test_session';

void main() {
  late MockBoxServer server;
  late ApiClient client;
  late Uri baseUri;

  setUp(() async {
    server = MockBoxServer(
      logRequests: false,
      deviceId: _deviceId,
      pairingSessionId: _pairingSessionId,
    );
    baseUri = await server.start();
    client = ApiClient();
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test('health validates the full BLE device id', () async {
    final health = await HealthApi(client).waitForDevice(
      baseUri,
      expectedDeviceId: _deviceId,
      retryWindow: const Duration(milliseconds: 50),
    );

    expect(health.deviceId, _deviceId);
    expect(health.apiVersion, 'v1');

    await expectLater(
      HealthApi(client).waitForDevice(
        baseUri,
        expectedDeviceId: 'bbx-11111111111111111111111111111111',
        retryWindow: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.deviceIdMismatch,
        ),
      ),
    );
  });

  test('pairing session is exchanged without sending the pairing code', () async {
    final now = DateTime.utc(2026, 8, 24, 12);
    final credential = await PairingApi(client).exchangeSession(
      baseUri,
      deviceId: _deviceId,
      clientId: _clientId,
      pairingSessionId: _pairingSessionId,
      clock: () => now,
    );

    expect(credential.deviceId, _deviceId);
    expect(credential.clientId, _clientId);
    expect(credential.expiresAt, now.add(const Duration(days: 30)));
    expect(server.lastRc4PairingClientId, _clientId);
    expect(server.lastRc4PairingIncludedCode, isFalse);
  });
}
