import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production entrypoints share one integrated bootstrap', () {
    final defaultMain = File('lib/main.dart').readAsStringSync();
    final compatibilityMain = File('lib/main_bird.dart').readAsStringSync();
    final bootstrap = File(
      'lib/bird_companion/app/integrated_bird_bootstrap.dart',
    ).readAsStringSync();

    expect(defaultMain, contains('runIntegratedBirdApp()'));
    expect(compatibilityMain, contains('runIntegratedBirdApp()'));
    expect(bootstrap, contains('class IntegratedBirdBootstrap'));
    expect(bootstrap, contains('BirdCompanionDependencies.create()'));
    expect(bootstrap, contains('BirdCompanionApp(dependencies:'));
    expect(defaultMain, isNot(contains('DemoTaskExperienceDataSource')));
    expect(compatibilityMain, isNot(contains('DemoTaskExperienceDataSource')));
  });

  test('settings showcase entrypoint is explicitly demo-only', () {
    final demoMain = File('lib/main_bird_settings.dart').readAsStringSync();

    expect(demoMain, contains("bool.fromEnvironment('BIRD_DEMO_MODE')"));
    expect(demoMain, contains('DemoTaskExperienceDataSource'));
    expect(demoMain, contains('demo-only'));
  });

  test('settings entrypoint routes device setup through production repository', () {
    final demoMain = File('lib/main_bird_settings.dart').readAsStringSync();

    expect(demoMain, isNot(contains('B7SimulatedDemoPage')));
    expect(demoMain, contains("BirdRoutes.connection"));
    expect(demoMain, contains('provisioningRepository: widget.dependencies.provisioningRepository'));
  });

  test('production task flow has no demo fallback or fixed task totals', () {
    final root = File(
      'lib/bird_companion/features/tasks/presentation/task_experience_root.dart',
    ).readAsStringSync();
    final repositoryController = File(
      'lib/bird_companion/features/tasks/presentation/'
      'repository_task_experience_controller.dart',
    ).readAsStringSync();
    final sdPage = File(
      'lib/bird_companion/features/tasks/presentation/pages/'
      'sd_card_flow_page.dart',
    ).readAsStringSync();

    expect(root, contains('RepositoryTaskExperienceController'));
    expect(root, isNot(contains('DemoTaskExperienceDataSource')));
    expect(root, contains('onStartTask: _startTask'));
    expect(root, contains('BirdRoutes.copyConfirmation'));
    expect(repositoryController, contains('const Duration(seconds: 4)'));
    expect(repositoryController, contains("startsWith('demo-')"));
    expect(sdPage, isNot(contains('3,672')));
    expect(sdPage, isNot(contains('86.4')));
    expect(sdPage, isNot(contains('2026.07.16')));
  });
}
