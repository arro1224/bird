import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'creation_fixtures.dart';

void main() {
  late CreationEnvironment env;
  SmartFollowConfigurationReader reader() => SmartFollowConfigurationReader(contextKey: env.context!, isCurrent: () => env.configuration.current, readSnapshot: () async => env.configuration.snapshot());
  Future<SmartFollowConfiguredIntent> confirm() async {
    final controller = SmartFollowConfigurationController(reader());
    await controller.refresh();
    controller.selectTarget('media_usb_fake');
    controller.selectConflict(ConflictStrategy.skip);
    expect(await controller.confirm(), isTrue, reason: controller.blockReason);
    final intent = controller.confirmed!;
    controller.dispose();
    return intent;
  }

  setUp(() {
    env = CreationEnvironment(atomic: true);
    env.configuration.bindingBatch = null;
  });
  tearDown(() => env.follows.dispose());

  test('new-project confirmation is revalidated without staging, analysis POST or follow creation', () async {
    final intent = await confirm();
    expect(intent.batchId, isNull);
    await env.service.validateForImport(intent, reader());
    expect(env.jobs.requests, isEmpty);
    expect(env.cache.values, isEmpty);
    expect(await env.backend.sessionIdForRecognitionJob('rec-1'), isNull);
  });

  for (final change in ['source', 'preferences', 'page', 'context']) {
    test('changed $change rejects old import copy confirmation before any task writes', () async {
      final intent = await confirm();
      switch (change) {
        case 'source':
          env.configuration.sourceId = 'changed-card';
        case 'preferences':
          env.configuration.preferencesVersion++;
        case 'page':
          env.configuration.current = false;
        case 'context':
          env.context = 'other-box';
      }
      await expectLater(env.service.validateForImport(intent, reader()), throwsA(isA<SmartFollowConfirmationRequired>()));
      expect(env.jobs.requests, isEmpty);
      expect(env.cache.values, isEmpty);
    });
  }

  test('box owner rejects legacy staged and direct follow creation before either POST', () async {
    final intent = (await confirm()).forBatch('batch-1');
    final guarded = SmartFollowCreationService(jobs: env.jobs, follows: env.follows, cache: env.cache, deviceId: () => env.device, contextKey: () => env.context, boxOwnsBatch: (_) async => true);
    final error = isA<ApiException>().having((e) => e.code, 'code', 'import_analysis_owned');
    await expectLater(guarded.startStaged('batch-1', reader()), throwsA(error));
    await expectLater(guarded.start(intent, reader()), throwsA(error));
    expect(env.jobs.requests, isEmpty);
    expect(env.cache.values, isEmpty);
    expect(await env.backend.sessionIdForRecognitionJob('rec-1'), isNull);
  });
}
