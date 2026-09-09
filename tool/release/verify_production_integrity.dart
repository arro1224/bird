import 'dart:io';

void main() {
  final failures = <String>[];

  _requireContains(
    failures,
    'lib/main.dart',
    'runIntegratedBirdApp()',
    'default entrypoint must delegate to the integrated bootstrap',
  );
  _requireContains(
    failures,
    'lib/main_bird.dart',
    'runIntegratedBirdApp()',
    'bird entrypoint must delegate to the integrated bootstrap',
  );
  _requireContains(
    failures,
    'lib/bird_companion/app/app_shell.dart',
    'TaskExperienceRoot(',
    'production shell must use the repository-backed task experience',
  );
  _requireContains(
    failures,
    'lib/bird_companion/app/app_shell.dart',
    'SettingsExperienceRoot(',
    'production shell must use the shared device/settings experience',
  );
  _requireContains(
    failures,
    'lib/bird_companion/features/tasks/presentation/task_experience_root.dart',
    'RepositoryTaskExperienceController(',
    'production tasks must be repository-backed',
  );
  _requireContains(
    failures,
    'lib/bird_companion/features/settings/presentation/settings_experience_root.dart',
    'store: dependencies.settingsStore',
    'production settings must use persistent storage',
  );

  const dependencyPath = 'lib/bird_companion/app/app_dependencies.dart';
  _requireContains(
    failures,
    dependencyPath,
    'PlatformBirdBoxBleDataSource(',
    'production must construct the real BLE data source',
  );
  _requireContains(
    failures,
    dependencyPath,
    'MethodChannelBirdBoxWifiPlatform()',
    'production must construct the real Wi-Fi platform bridge',
  );
  _requireContains(
    failures,
    dependencyPath,
    'MethodChannelBirdBoxDppPlatform()',
    'production must construct the real DPP platform bridge',
  );
  _requireContains(
    failures,
    dependencyPath,
    'rememberDynamicAddress:',
    'production must persist dynamically discovered device addresses',
  );
  _requireContains(
    failures,
    dependencyPath,
    'restoreSavedSession()',
    'production must restore the saved device session at startup',
  );
  _requireContains(
    failures,
    dependencyPath,
    'Future<void> completeProvisioning(',
    'production must promote a completed BLE flow into the regular session',
  );
  _requireContains(
    failures,
    dependencyPath,
    'deviceSessionCubit.setConnectedFromStatus(status)',
    'provisioning completion must update the app-wide device session',
  );
  _forbid(
    failures,
    dependencyPath,
    'FakeBirdBox',
    'production must not construct a FakeBirdBox adapter',
  );
  _forbid(
    failures,
    dependencyPath,
    'FakeProvisioningRepository',
    'production must not construct a FakeProvisioningRepository',
  );
  _forbid(
    failures,
    dependencyPath,
    'B7Simulated',
    'production dependencies must not construct the Debug simulator',
  );
  _forbid(
    failures,
    dependencyPath,
    '/simulation/',
    'production dependencies must not import the Debug simulation package',
  );

  const appPath = 'lib/bird_companion/app/bird_companion_app.dart';
  _requireContains(
    failures,
    appPath,
    'onProvisioningCompleted: dependencies.completeProvisioning',
    'production routes must receive the provisioning completion handler',
  );
  const routerPath = 'lib/bird_companion/app/app_router.dart';
  _requireContains(
    failures,
    routerPath,
    'onProvisioningCompleted: onProvisioningCompleted',
    'the router must forward provisioning completion to the connection page',
  );
  const connectionPagePath = 'lib/bird_companion/features/connection/presentation/connection_page.dart';
  _requireContains(
    failures,
    connectionPagePath,
    'if (!_handoffCommitted)',
    'an unfinished provisioning route must release its connection resources',
  );
  _requireContains(
    failures,
    connectionPagePath,
    'widget.repository.disconnect()',
    'an unfinished provisioning route must disconnect the repository',
  );

  const provisioningRepositoryPath = 'lib/bird_companion/features/connection/data/provisioning_repository_impl.dart';
  _requireContains(
    failures,
    provisioningRepositoryPath,
    'DppAvailabilityRepository',
    'production provisioning must expose merged DPP availability',
  );
  _requireContains(
    failures,
    provisioningRepositoryPath,
    'checkDppAvailability()',
    'production provisioning must check DPP before enabling the entry',
  );
  _requireContains(
    failures,
    provisioningRepositoryPath,
    '_dpp.checkCapability()',
    'DPP availability must include the Android platform capability',
  );
  const wifiMethodPagePath = 'lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart';
  for (final entry in const [
    '使用手机安全共享 Wi-Fi',
    '扫描 Wi-Fi 二维码',
    '选择或手动输入网络',
  ]) {
    _requireContains(
      failures,
      wifiMethodPagePath,
      entry,
      'the frozen existing-Wi-Fi entry is missing: $entry',
    );
  }
  _requireContains(
    failures,
    wifiMethodPagePath,
    'WifiQrScannerPage()',
    'the Wi-Fi QR entry must open the dedicated scanner',
  );
  _requireContains(
    failures,
    'lib/bird_companion/features/connection/domain/wifi_qr_parser.dart',
    'parseWifiQrCredentials',
    'the strict local Wi-Fi QR parser is missing',
  );

  const networkSettingsPagePath = 'lib/bird_companion/features/settings/presentation/pages/network_settings_page.dart';
  _requireContains(
    failures,
    routerPath,
    'BirdRoutes.settingsNetwork',
    'the production router must expose the network settings flow',
  );
  _requireContains(
    failures,
    networkSettingsPagePath,
    'NetworkProvisioningPage(',
    'network settings must use the frozen provisioning state machine',
  );
  _requireContains(
    failures,
    provisioningRepositoryPath,
    "'restore_previous_sta': true",
    'stop_direct_ap must always request restoration of the previous STA',
  );
  _requireContains(
    failures,
    provisioningRepositoryPath,
    'ProvisioningNetworkStatusVerifier',
    'a resumed terminal network must be verified before success',
  );
  const networkCubitPath = 'lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
  _requireContains(
    failures,
    networkCubitPath,
    'resumeAfterBleReconnect',
    'BLE reconnect must restore authoritative network operation state',
  );
  _requireContains(
    failures,
    wifiMethodPagePath,
    '断开盒子直连？',
    'stopping Direct AP must require explicit user confirmation',
  );

  const nativeBlePath = 'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java';
  const nativeWifiPath = 'android/app/src/main/java/deckers/thibault/aves/BirdBoxWifiChannel.java';
  const nativeDppPath = 'android/app/src/main/java/deckers/thibault/aves/BirdBoxDppChannel.java';
  const wifiPlatformPath = 'lib/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
  _requireContains(
    failures,
    nativeBlePath,
    'callbackGatt != gatt',
    'stale Android GATT callbacks must not complete a newer connection',
  );
  _requireContains(
    failures,
    nativeBlePath,
    'ble_link_not_encrypted',
    'native GATT security failures must remain distinct from transport errors',
  );
  _requireContains(
    failures,
    nativeWifiPath,
    'bird_companion/birdbox_wifi/network_events',
    'Android local-only Wi-Fi loss must have a dedicated EventChannel',
  );
  _requireContains(
    failures,
    nativeWifiPath,
    'emitNetworkLost(',
    'Android NetworkCallback.onLost must notify Dart',
  );
  _requireContains(
    failures,
    wifiPlatformPath,
    'Stream<WifiNetworkLoss> get networkLosses',
    'the Dart Wi-Fi boundary must expose native network loss',
  );
  _requireContains(
    failures,
    provisioningRepositoryPath,
    '_wifi.networkLosses.listen',
    'the production repository must consume native Wi-Fi loss events',
  );
  _requireContains(
    failures,
    nativeDppPath,
    'requestCodeForGeneration',
    'Easy Connect launches must isolate stale Activity results',
  );
  for (final path in [nativeBlePath, nativeWifiPath, nativeDppPath]) {
    _forbid(
      failures,
      path,
      'android.util.Log',
      'native provisioning bridges must not log transient credentials or identifiers',
    );
  }

  const releaseGatePath = 'tool/release/run_b7_gate.ps1';
  for (final marker in const [
    r'[string]$BleRc4EvidencePath',
    'tool/acceptance/ble_provisioning_rc4_real_device_gate.dart',
    r'$script:bleRc4Verified',
  ]) {
    _requireContains(
      failures,
      releaseGatePath,
      marker,
      'Release must retain the BLE RC4 real-device evidence gate: $marker',
    );
  }
  const bleEvidenceTemplatePath = 'docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json';
  _requireContains(
    failures,
    bleEvidenceTemplatePath,
    '"id": "K7-01"',
    'BLE RC4 evidence must start with the real-device K7 case set',
  );
  _requireContains(
    failures,
    bleEvidenceTemplatePath,
    '"id": "K7-10"',
    'BLE RC4 evidence must include all ten K7 cases',
  );
  _forbid(
    failures,
    bleEvidenceTemplatePath,
    '"id": "SIM-',
    'BLE RC4 release evidence must not use simulated case ids',
  );

  const productionFiles = [
    'lib/main.dart',
    'lib/main_bird.dart',
    'lib/bird_companion/app/integrated_bird_bootstrap.dart',
    'lib/bird_companion/app/bird_companion_app.dart',
    'lib/bird_companion/app/app_shell.dart',
    'lib/bird_companion/features/tasks/presentation/task_experience_root.dart',
    'lib/bird_companion/features/settings/presentation/settings_experience_root.dart',
  ];
  for (final path in productionFiles) {
    _forbid(
      failures,
      path,
      "import 'package:aves/bird_companion/app/bird_demo_shell.dart'",
      'production entry graph imports BirdDemoShell',
    );
    _forbid(
      failures,
      path,
      '/demo/',
      'production entry graph imports a demo data source',
    );
    _forbid(
      failures,
      path,
      'demo-analysis-',
      'production entry graph contains a demo task identifier',
    );
    _forbid(
      failures,
      path,
      'B7Simulated',
      'production entry graph references the Debug box simulator',
    );
    _forbid(
      failures,
      path,
      '/simulation/',
      'production entry graph imports the Debug simulation package',
    );
  }

  const jobFiles = [
    'lib/bird_companion/features/jobs/presentation/job_center_cubit.dart',
    'lib/bird_companion/features/jobs/presentation/job_center_page.dart',
    'lib/bird_companion/features/jobs/presentation/job_detail_cubit.dart',
  ];
  for (final path in jobFiles) {
    _forbid(
      failures,
      path,
      'showDemo',
      'production job flow exposes a demo fallback',
    );
    _forbid(
      failures,
      path,
      'demo-analysis-',
      'production job flow contains a demo task identifier',
    );
  }

  _forbid(
    failures,
    'lib/bird_companion/app/integrated_bird_bootstrap.dart',
    '版本 1.0.0',
    'startup version must come from package metadata',
  );

  if (failures.isNotEmpty) {
    stderr.writeln(
      'FAIL production integrity (${failures.length} errors)',
    );
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'PASS production integrity: entrypoints, dependencies and fallbacks are valid.',
  );
}

void _requireContains(
  List<String> failures,
  String path,
  String expected,
  String message,
) {
  final content = _read(failures, path);
  if (content != null && !content.contains(expected)) {
    failures.add('$path: $message');
  }
}

void _forbid(
  List<String> failures,
  String path,
  String forbidden,
  String message,
) {
  final content = _read(failures, path);
  if (content != null && content.contains(forbidden)) {
    failures.add('$path: $message');
  }
}

String? _read(List<String> failures, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    failures.add('$path: required production file is missing');
    return null;
  }
  return file.readAsStringSync();
}
