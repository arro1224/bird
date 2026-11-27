import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../mock_box_server.dart';

/// The simulated hardware lives in this Android app, listening only on loopback.
/// Real repositories, validation, authentication and events remain in use.
class DemoRuntime {
  DemoRuntime._(this.server, this.dependencies, this.provisioning, this.clientIdentity);

  static const deviceId = 'bbx-1118de0011184de08de0111811180001';
  static const sampleNames = ['egret.png', 'kingfisher.png', 'sandpiper.png', 'warbler.png'];
  final MockBoxServer server;
  final BirdCompanionDependencies dependencies;
  final B7SimulatedProvisioningRepository provisioning;
  final ClientIdentityStore clientIdentity;
  Future<void>? _closing;

  static Future<DemoRuntime> start({RepairAcceptanceProfile? acceptanceProfile, bool autoConnect = true}) async {
    final profile = acceptanceProfile ?? RepairAcceptanceProfile.parse(const String.fromEnvironment('BIRDBOX_DEMO_PROFILE', defaultValue: 'demo'));
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/embedded_demo_box${profile == null ? '' : '/acceptance/${profile.id}'}');
    await directory.create(recursive: true);
    final media = Directory('${directory.path}/media');
    await media.create(recursive: true);
    for (final name in sampleNames) {
      final bytes = await rootBundle.load('tool/mock_box_server/assets/$name');
      await File('${media.path}/$name').writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    }
    B7SimulatedProvisioningRepository? provisioning;
    final server = MockBoxServer(
      photoCount: profile?.total ?? 60,
      acceptanceProfile: profile,
      embeddedDemo: true,
      assetDirectory: media,
      deviceId: deviceId,
      requireAuthentication: true,
      tokenLifetime: const Duration(days: 365),
      workflowAutoAdvance: true,
      stateFile: File('${directory.path}/state.json'),
      logRequests: false,
      networkModeProvider: () => switch (provisioning?.currentNetworkMode) {
        ProvisioningNetworkMode.infrastructureSta => 'infrastructure_sta',
        _ => 'direct_ap',
      },
    );
    BirdCompanionDependencies? dependencies;
    try {
      final uri = await server.start();
      final identity = MemoryClientIdentityStore();
      provisioning = B7SimulatedProvisioningRepository(
        baseUri: uri,
        deviceId: deviceId,
        clientIdentity: identity,
        sessionLifetime: const Duration(days: 365),
      );
      dependencies = await BirdCompanionDependencies.create(
        connectEnvironmentTestEndpoint: false,
        restoreSavedSession: false,
        provisioningRepositoryOverride: provisioning,
        phoneWifiOverride: const DemoPhoneWifiPlatform(),
        isEmbeddedDemo: true,
        connectivityMonitorOverride: DemoConnectivityMonitor(),
        sessionStoreOverride: MemorySecureSessionStore(),
        clientIdentityStore: identity,
      );
      final runtime = DemoRuntime._(server, dependencies, provisioning, identity);
      if (autoConnect) await runtime.connect();
      return runtime;
    } catch (_) {
      dependencies?.dispose();
      await server.close();
      rethrow;
    }
  }

  Future<void> connect([ProvisioningCompletion? completion]) async {
    if (completion != null && (completion.deviceId != deviceId || completion.baseUri != server.baseUri)) {
      throw StateError('演示盒子身份不匹配。');
    }
    final peer = await provisioning.discoverDevices().first;
    await provisioning.connect(peer);
    await provisioning.openPairing();
    await provisioning.authorizePairing('123456');
    final clientId = await clientIdentity.readOrCreate();
    final sessionId = provisioning.takePairingSessionForHttp();
    server.registerPairingSession(sessionId, clientId: clientId, lifetime: const Duration(minutes: 2));
    final credential = await PairingApi(dependencies.apiClient).exchangeSession(
      server.baseUri!,
      deviceId: deviceId,
      clientId: clientId,
      pairingSessionId: sessionId,
      clientName: 'birdbox-embedded-demo-v1',
    );
    await dependencies.sessionCoordinator.activate(credential);
    final status = await dependencies.connectionRepository.connect(
      server.baseUri!,
      networkMode: completion?.networkMode == ProvisioningNetworkMode.infrastructureSta ? NetworkMode.infrastructureSta : NetworkMode.directAp,
    );
    await dependencies.deviceSessionCubit.setConnectedFromStatus(status);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    dependencies.dispose();
    await server.close();
  }
}

/// Loopback is available in flight mode and never depends on the phone Wi-Fi.
class DemoConnectivityMonitor extends ConnectivityMonitor implements DiagnosticNetworkTypes {
  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();
  @override
  Stream<void> get onTransportChanged => const Stream.empty();
  @override
  Future<bool> get hasNetwork async => true;
  @override
  Future<bool> get hasWifi async => true;
  @override
  Future<List<String>> get networkTypes async => const ['simulated_loopback'];
}


/// Supplies a predictable phone Wi-Fi name in the offline demo without Android location access.
final class DemoPhoneWifiPlatform implements PhoneWifiPlatform {
  const DemoPhoneWifiPlatform();

  @override
  Future<PhoneWifiSsid> currentSsid() async => const PhoneWifiSsid.readable('BirdLab-5G');

  @override
  Future<String?> pickQrImage() async => null;
}
