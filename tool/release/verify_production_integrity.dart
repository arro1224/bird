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
    'PlatformBirdBoxBleDataSource()',
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
