import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/theme/app_theme.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/widgets/bird_feedback.dart';
import 'package:aves/bird_companion/features/connection/data/health_api.dart';
import 'package:aves/bird_companion/features/connection/data/pairing_api.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/b7_simulated_demo_page.dart';
import 'package:aves/bird_companion/features/device/data/device_status_api.dart';
import 'package:flutter/material.dart';

typedef SimulatedHealthVerifier =
    Future<BirdBoxHealth> Function(
      Uri baseUri,
      String expectedDeviceId,
    );

final class SimulatedBirdBoxDebugConfig {
  const SimulatedBirdBoxDebugConfig({
    required this.baseUri,
    required this.deviceId,
  });

  final Uri baseUri;
  final String deviceId;

  factory SimulatedBirdBoxDebugConfig.parse({
    required String baseUrl,
    required String deviceId,
  }) {
    final uri = Uri.tryParse(baseUrl.trim());
    const allowedHosts = {'127.0.0.1', 'localhost', '10.0.2.2'};
    if (uri == null || uri.scheme != 'http' || !allowedHosts.contains(uri.host) || !uri.hasPort || uri.userInfo.isNotEmpty || uri.query.isNotEmpty || uri.fragment.isNotEmpty || (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'BIRD_TEST_BASE_URL must be an HTTP loopback URL with an explicit port.',
      );
    }
    if (!RegExp(r'^bbx-[0-9a-f]{32}$').hasMatch(deviceId)) {
      throw const FormatException(
        'BIRD_SIMULATED_DEVICE_ID must match bbx- plus 32 lowercase hex characters.',
      );
    }
    return SimulatedBirdBoxDebugConfig(baseUri: uri, deviceId: deviceId);
  }
}

/// Debug-only host that replaces the physical BLE/Wi-Fi transport while still
/// using the production repositories, session cubit, router and three-tab app.
class SimulatedBirdBoxDebugApp extends StatefulWidget {
  const SimulatedBirdBoxDebugApp({
    super.key,
    required this.config,
    this.healthVerifier,
  });

  final SimulatedBirdBoxDebugConfig config;
  final SimulatedHealthVerifier? healthVerifier;

  @override
  State<SimulatedBirdBoxDebugApp> createState() => _SimulatedBirdBoxDebugAppState();
}

class _SimulatedBirdBoxDebugAppState extends State<SimulatedBirdBoxDebugApp> {
  late final B7SimulatedProvisioningRepository _repository;
  late final Future<BirdCompanionDependencies> _dependenciesFuture;
  BirdCompanionDependencies? _dependencies;

  @override
  void initState() {
    super.initState();
    _repository = B7SimulatedProvisioningRepository(
      baseUri: widget.config.baseUri,
      deviceId: widget.config.deviceId,
    );
    _dependenciesFuture = BirdCompanionDependencies.create(
      connectEnvironmentTestEndpoint: false,
      restoreSavedSession: false,
    );
    unawaited(_captureDependencies());
  }

  Future<void> _captureDependencies() async {
    try {
      final dependencies = await _dependenciesFuture;
      if (mounted) {
        _dependencies = dependencies;
      } else {
        dependencies.dispose();
      }
    } catch (_) {
      // FutureBuilder renders the startup error from the original future.
    }
  }

  @override
  void dispose() {
    unawaited(_repository.dispose());
    _dependencies?.dispose();
    super.dispose();
  }

  Future<void> _complete(ProvisioningCompletion completion) async {
    if (completion.deviceId != widget.config.deviceId || completion.baseUri != widget.config.baseUri) {
      throw StateError(
        'Simulated BLE identity/address does not match its HTTP Mock.',
      );
    }

    final dependencies = await _dependenciesFuture;
    final verifier = widget.healthVerifier ?? (baseUri, expectedDeviceId) => _verifyHealth(dependencies, baseUri, expectedDeviceId);
    final health = await verifier(completion.baseUri, completion.deviceId);
    if (health.deviceId != completion.deviceId) {
      throw StateError(
        'HTTP Mock device_id does not match simulated BLE identity.',
      );
    }

    // Exchange the same transient pairing session exposed by the simulated BLE
    // layer. Persist is false so a debug run cannot replace real credentials.
    final credential = await PairingApi(dependencies.apiClient).exchangeSession(
      completion.baseUri,
      deviceId: completion.deviceId,
      clientId: _simulatedClientId,
      pairingSessionId: simulatedBirdBoxPairingSessionId,
      clientName: 'Bird Companion Android (Simulated)',
    );
    await dependencies.sessionCoordinator.activate(
      credential,
      persist: false,
    );

    final status = await DeviceStatusApi(dependencies.apiClient).fetchStatus();
    if (status.connection.id != completion.deviceId) {
      throw StateError(
        'HTTP Mock device status does not match simulated BLE identity.',
      );
    }
    await dependencies.deviceSessionCubit.connected(
      DeviceSessionState(
        phase: DeviceSessionPhase.connected,
        device: status.connection.copyWith(
          baseUri: completion.baseUri,
          networkMode: switch (completion.networkMode) {
            ProvisioningNetworkMode.directAp => NetworkMode.directAp,
            ProvisioningNetworkMode.infrastructureSta => NetworkMode.infrastructureSta,
            ProvisioningNetworkMode.none => NetworkMode.none,
          },
        ),
        lastUpdatedAt: DateTime.now(),
      ),
    );
  }

  Future<BirdBoxHealth> _verifyHealth(
    BirdCompanionDependencies dependencies,
    Uri baseUri,
    String expectedDeviceId,
  ) async {
    final health = await HealthApi(dependencies.apiClient).read(baseUri);
    if (health.deviceId != expectedDeviceId) {
      throw StateError(
        'HTTP Mock device_id does not match simulated BLE identity.',
      );
    }
    return health;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BirdCompanionDependencies>(
    future: _dependenciesFuture,
    builder: (context, snapshot) {
      final dependencies = snapshot.data;
      if (dependencies == null) {
        return _StartupPage(error: snapshot.error);
      }
      return BirdCompanionScope(
        dependencies: dependencies,
        child: MaterialApp(
          scaffoldMessengerKey: BirdFeedback.messengerKey,
          navigatorObservers: [BirdFeedbackNavigatorObserver()],
          title: '拍鸟伴侣 · 模拟盒子调试',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          home: B7SimulatedDemoPage(
            repository: _repository,
            onProvisioningCompleted: _complete,
            titlePrefix: '模拟 · ',
          ),
          onGenerateRoute: (settings) => BirdAppRouter.onGenerateRoute(
            settings,
            provisioningRepository: _repository,
            onProvisioningCompleted: _complete,
          ),
        ),
      );
    },
  );
}

class _StartupPage extends StatelessWidget {
  const _StartupPage({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: error == null
              ? const CircularProgressIndicator()
              : Text(
                  '模拟环境初始化失败：$error',
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    ),
  );
}

const _simulatedClientId = '8ab5fe4e-a835-4cd3-8bc6-d7e09a89d61a';
