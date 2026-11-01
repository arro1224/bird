import 'dart:async';

import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter_test/flutter_test.dart';

import 'configuration_fixtures.dart';

void main() {
  test('an entry cannot silently rebind its configuration to another recognition round', () async {
    final fixture = ConfigurationFixture();
    final controller = SmartFollowConfigurationController(fixture.reader(), expectedRecognitionJobId: 'rec-1', expectedRecognitionPhase: RecognitionEntryPhase.running);
    addTearDown(controller.dispose);
    await controller.refresh();
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    fixture.jobId = 'rec-2';
    expect(await controller.confirm(), isFalse);
    expect(controller.blockReason, contains('识别任务已变化'));
    expect(await controller.confirm(), isFalse);
    final newRoundController = SmartFollowConfigurationController(fixture.reader(), expectedRecognitionPhase: RecognitionEntryPhase.notStarted);
    addTearDown(newRoundController.dispose);
    await newRoundController.refresh();
    newRoundController.selectTarget('target');
    newRoundController.selectConflict(ConflictStrategy.skip);
    expect(await newRoundController.confirm(), isFalse);
    expect(newRoundController.blockReason, contains('识别阶段已变化'));
  });

  testWidgets('binding expiry clears confirmation even without another interaction', (tester) async {
    final fixture = ConfigurationFixture();
    fixture.expiry = fixture.clock.add(const Duration(seconds: 10));
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    expect(await controller.confirm(), isTrue);
    fixture.clock = fixture.clock.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    expect(controller.confirmed, isNull);
    expect(controller.blockReason, contains('过期'));
  });

  test('does not guess a target or a conflict policy', () async {
    final fixture = ConfigurationFixture()..preferred = PairPolicy.both;
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    expect(controller.pairPolicy, PairPolicy.both);
    expect(controller.targetMediaId, isNull);
    expect(controller.conflictStrategy, isNull);
    expect(await controller.confirm(), isFalse);
    controller.selectTarget('target');
    expect(controller.blockReason, contains('同名'));
    expect(await controller.confirm(), isFalse);
  });

  test('excludes the source/import role and explains offline, readonly and busy targets', () async {
    final fixture = ConfigurationFixture()
      ..devices = [
        configDevice('source', source: true),
        configDevice('import', role: 'import_source'),
        configDevice('offline', online: false),
        configDevice('readonly', writable: false, reasons: ['COPY_TARGET_READ_ONLY']),
        configDevice('busy', reasons: ['COPY_TARGET_BUSY']),
        configDevice('target'),
      ];
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    expect(controller.candidates.map((device) => device.mediaId), ['offline', 'readonly', 'busy', 'target']);
    for (final id in ['source', 'import', 'offline', 'readonly', 'busy']) {
      controller.selectTarget(id);
      expect(controller.targetMediaId, isNull);
    }
    expect(controller.targetBlockReason(fixture.devices[2]), contains('断开'));
    expect(controller.targetBlockReason(fixture.devices[3]), contains('只读'));
    expect(controller.targetBlockReason(fixture.devices[4]), contains('占用'));
  });

  test('zero space, unknown capacity and unknown identity cannot be confirmed', () async {
    for (final target in [configDevice('target', free: 0), configDevice('target', capacity: 0), configDevice('target', free: 3000000), configDevice('target', identity: 'unknown')]) {
      final fixture = ConfigurationFixture()..devices = [configDevice('source', source: true), target];
      final controller = await fixture.controller();
      controller.selectTarget('target');
      controller.selectConflict(ConflictStrategy.skip);
      expect(controller.targetMediaId, isNull);
      expect(await controller.confirm(), isFalse);
      controller.dispose();
    }
  });

  test('unverified, expired, wrong-batch and offline source bindings are blocked', () async {
    for (final mutate in <void Function(ConfigurationFixture)>[
      (fixture) => fixture.readOnly = false,
      (fixture) => fixture.expiry = fixture.clock.subtract(const Duration(minutes: 1)),
      (fixture) => fixture.bindingBatch = 'other',
      (fixture) => fixture.devices[0] = configDevice('source', source: true, online: false),
      (fixture) => fixture.token = '',
    ]) {
      final fixture = ConfigurationFixture();
      mutate(fixture);
      final controller = await fixture.controller();
      controller.selectTarget('target');
      controller.selectConflict(ConflictStrategy.skip);
      expect(controller.blockReason, isNotNull);
      expect(await controller.confirm(), isFalse);
      controller.dispose();
    }
  });

  test('all file/conflict strategies produce the existing complete request DTO', () async {
    for (final policy in PairPolicy.values) {
      for (final conflict in ConflictStrategy.values) {
        final fixture = ConfigurationFixture();
        final controller = await fixture.controller();
        controller.selectTarget('target');
        controller.selectPairPolicy(policy);
        controller.selectConflict(conflict);
        controller.setReviewExport(true);
        expect(await controller.confirm(), isTrue);
        expect(fixture.reads, 2);
        expect(controller.confirmed!.request.toJson(), {
          'target_media_id': 'target',
          'eligibility_mode': 'recognized_only_v1',
          'pair_policy': policy.wireValue,
          'conflict_strategy': conflict.wireValue,
          'review_export': {'enabled': true, 'prefer_embedded': true},
        });
        expect(controller.confirmed!.recognitionJobId, 'rec-1');
        expect(controller.confirmed!.sourceMediaId, 'source');
        expect(controller.confirmed!.preferencesVersion, 1);
        controller.dispose();
      }
    }
  });

  test('metadata-update capability is independent; initial copy export is separately gated', () async {
    final fixture = ConfigurationFixture();
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    controller.setReviewExport(true);
    expect(await controller.confirm(), isTrue);
    expect(controller.snapshot!.entry.capabilities.metadataUpdate, isFalse);
    fixture.exports = false;
    expect(await controller.confirm(), isFalse);
    expect(controller.reviewExportEnabled, isFalse);
    controller.setReviewExport(true);
    expect(controller.reviewExportEnabled, isFalse);
    expect(await controller.confirm(), isTrue);
    expect(controller.confirmed!.request.toJson()['review_export'], {'enabled': false, 'prefer_embedded': true});
  });

  test('fresh device or preference changes require another explicit confirmation', () async {
    final fixture = ConfigurationFixture();
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.keepBoth);
    fixture.beforeRead = (count) {
      if (count == 2) {
        fixture.devices[1] = configDevice('target', free: 900000);
        fixture.preferencesVersion = 2;
      }
    };
    expect(await controller.confirm(), isFalse);
    expect(controller.notice, contains('再次确认'));
    expect(controller.confirmed, isNull);
    expect(await controller.confirm(), isTrue);
    expect(controller.confirmed!.targetFreeBytes, 900000);
    expect(controller.confirmed!.preferencesVersion, 2);
  });

  test('removed target never auto-switches to another device', () async {
    final fixture = ConfigurationFixture();
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    expect(await controller.confirm(), isTrue);
    fixture.devices = [configDevice('source', source: true), configDevice('other')];
    await controller.refresh();
    expect(controller.targetMediaId, 'target');
    expect(controller.target, isNull);
    expect(controller.confirmed, isNull);
    expect(await controller.confirm(), isFalse);
  });

  test('confirmed intent is frozen and editing invalidates only the current confirmation', () async {
    final controller = await ConfigurationFixture().controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    expect(await controller.confirm(), isTrue);
    final original = controller.confirmed!;
    controller.selectPairPolicy(PairPolicy.both);
    expect(controller.confirmed, isNull);
    expect(original.request.pairPolicy, 'raw_only');
    expect(await controller.confirm(), isTrue);
    controller.setReviewExport(true);
    expect(controller.confirmed, isNull);
  });

  test('failure and capability loss invalidate prior confirmation without a POST', () async {
    final fixture = ConfigurationFixture();
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    expect(await controller.confirm(), isTrue);
    fixture.pending = () => Future.error(StateError('unreachable'));
    expect(await controller.refresh(), isFalse);
    expect(controller.confirmed, isNull);
    expect(await controller.confirm(), isFalse);
    fixture.pending = null;
    fixture.available = false;
    await controller.refresh();
    expect(await controller.confirm(), isFalse);
  });

  test('device invalidation interrupts an in-flight confirmation', () async {
    final fixture = ConfigurationFixture();
    final controller = await fixture.controller();
    addTearDown(controller.dispose);
    controller.selectTarget('target');
    controller.selectConflict(ConflictStrategy.skip);
    final pending = Completer<SmartFollowConfigurationSnapshot>();
    fixture.pending = () => pending.future;
    final confirmation = controller.confirm();
    fixture.current = false;
    controller.invalidate();
    pending.complete(fixture.snapshot());
    expect(await confirmation, isFalse);
    expect(controller.confirmed, isNull);
  });
}
