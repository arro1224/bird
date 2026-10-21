import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/ble/platform_birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/data/ble/birdbox_ble_data_source.dart';
import 'package:aves/bird_companion/features/connection/domain/ble_attempt_failure.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/data/direct_ap_pending_store.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/data/provisioning_repository_impl.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_dpp_platform.dart';
import 'fakes/fake_birdbox_wifi_platform.dart';
import 'fakes/preflight_ble_platform.dart';

void main() {
  final device = ProvisioningDevice(scanId: 'test', advertisement: PreflightBlePlatform.advertisement);
  test('repository, page and disposal cleanup never close a replacement public GATT', () async {
    final platform = PreflightBlePlatform();
    platform.beforePublicWrite = () {
      platform.beforePublicWrite = null;
      platform.instance = 2;
    };
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    final api = ApiClient();
    final repository = ProvisioningRepositoryImpl(
      ble: source,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: PreflightBlePlatform.client),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
    );
    final cubit = ProvisioningCubit(repository);
    await cubit.selectDevice(device);
    expect((cubit.state.error as ProvisioningException).code, ProvisioningErrorCode.bleGattOwnerMismatch);
    await cubit.close();
    await repository.dispose();
    await api.dispose();
    expect(platform.connected, isTrue);
    expect(platform.publicReleaseOwners, isEmpty);
    expect(platform.bondsInitiated, 0);
  });
  test('repository cleanup is secondary and Cubit receives the source rejection with complete evidence', () async {
    final source = _FailingConnection();
    final api = ApiClient();
    final repository = ProvisioningRepositoryImpl(
      ble: source,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: PreflightBlePlatform.client),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
    );
    final cubit = ProvisioningCubit(repository);
    await cubit.selectDevice(device);
    final error = cubit.state.error as ProvisioningException;
    expect(error.code, ProvisioningErrorCode.blePairingRejected);
    final secondary = (error.failureDetails!['secondary_errors'] as List).single as Map;
    expect(secondary['runtime_type'], 'StateError');
    expect(secondary['trigger_method'], 'repository.connect.disconnect');
    expect(source.failures.last.failureDetails, error.failureDetails);
    expect(source.bondStarts, 0);
    source.cleanupFails = false;
    await cubit.close();
    await repository.dispose();
    await api.dispose();
  });
  test('repository and Cubit wait for the full reset then permit one explicit pairing', () async {
    final platform = PreflightBlePlatform()..boardOld = true;
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    final api = ApiClient();
    final store = MemoryDirectApAuthorizationStore();
    await store.write(PreflightBlePlatform.device, {'pairing_session_id': 'FAKE_HTTP_HANDOFF_ONLY'});
    final repository = ProvisioningRepositoryImpl(
      ble: source,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: PreflightBlePlatform.client),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
      directApAuthorizationStore: store,
    );
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
      await api.dispose();
    });
    final phases = <ProvisioningPhase>[];
    final sub = cubit.stream.listen((state) => phases.add(state.phase));
    addTearDown(sub.cancel);
    await cubit.selectDevice(device);
    expect(cubit.state.phase, ProvisioningPhase.trusted);
    expect(phases, isNot(contains(ProvisioningPhase.failure)));
    expect(platform.bondsInitiated, 0);
    expect(repository.connectedDeviceInfo?.deviceId, PreflightBlePlatform.device);
    expect((await store.load(PreflightBlePlatform.device))?['pairing_session_id'], 'FAKE_HTTP_HANDOFF_ONLY');
    // A second connect to the same identity must still use the public status read.
    await cubit.selectDevice(device);
    expect(platform.protectedWrites, 0);
    await cubit.openPairing();
    expect(cubit.state.phase, ProvisioningPhase.pairingCode);
    expect(platform.bondsInitiated, 1);
  });

  test('cancelled preparation cannot publish stale trusted state', () async {
    final platform = PreflightBlePlatform()..dropResponses = true;
    final source = PlatformBirdBoxBleDataSource(platform: platform);
    final api = ApiClient();
    final repository = ProvisioningRepositoryImpl(
      ble: source,
      wifi: FakeBirdBoxWifiPlatform(),
      dpp: FakeBirdBoxDppPlatform(),
      clientIdentityStore: MemoryClientIdentityStore(initialValue: PreflightBlePlatform.client),
      credentialStore: MemorySecureSessionStore(),
      healthApi: HealthApi(api),
      pairingApi: PairingApi(api),
    );
    final cubit = ProvisioningCubit(repository);
    addTearDown(() async {
      await cubit.close();
      await repository.dispose();
      await api.dispose();
    });
    final connection = cubit.selectDevice(device);
    while (platform.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await cubit.reset();
    await connection;
    expect(cubit.state.phase, ProvisioningPhase.idle);
    expect(repository.connectedDeviceInfo, isNull);
    expect(platform.bondsInitiated, 0);
  });
}

class _FailingConnection implements BirdBoxBleDataSource, BleFailureDiagnostics {
  final failures = <ProvisioningException>[];
  bool cleanupFails = true;
  int bondStarts = 0;
  @override
  Stream<ProvisioningEvent> get events => const Stream.empty();
  @override
  Stream<void> get disconnects => const Stream.empty();
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(BirdBoxAdvertisement advertisement) async => throw const ProvisioningException(code: ProvisioningErrorCode.blePairingRejected, retryable: false);
  @override
  Future<void> disconnect() async {
    if (cleanupFails) throw StateError('private cleanup diagnostic');
  }

  @override
  Future<void> recordFailureDetails(ProvisioningException error) async => failures.add(error);
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
