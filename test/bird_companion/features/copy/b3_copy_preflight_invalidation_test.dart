import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository, {Stream<void>? sessions, bool Function()? available, Duration poll = Duration.zero, Future<void> Function(CopyJobSummary)? onCreated}) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, sessionChanges: sessions, canUseDevice: available, pollInterval: poll, onJobCreated: onCreated);
  addTearDown(cubit.close);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('State did not settle');
}

void main() {
  test('a preflight for another source never enables Start', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.storage.add(b3Device('different-source', source: true, target: false));
    repository.makePreview = (draft) async =>
        repository.previewFor(CopyRequestDraft(batchId: draft.batchId, scope: draft.scope, sourceMediaId: 'different-source', targetMediaId: draft.targetMediaId, conflictStrategy: draft.conflictStrategy, reviewExport: draft.reviewExport));
    expect(await cubit.fetchPreview(), false);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.planInconsistent);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('preflight read-only target evidence blocks creation even when the last device list allowed it', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.makePreview = (draft) async {
      final previous = repository.storage[1];
      repository.storage[1] = b3Device('target', target: false, reasons: ['COPY_TARGET_READ_ONLY']);
      final result = repository.previewFor(draft);
      repository.storage[1] = previous;
      return result;
    };
    expect(await cubit.submit(), false);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.targetUnavailable);
    expect(repository.createCalls, 0);
  });

  test('confirmed source failure invalidates promptly while the parallel device read is pending', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    final slow = Completer<CopyDeviceList>();
    repository.readDevices = () => slow.future;
    repository.readSource = () async => throw const ApiException(message: '', code: 'COPY_SOURCE_NOT_PRESENT', statusCode: 409);
    expect(await cubit.refreshDevices(), false);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.sourceOffline);
    expect(cubit.state.preview, isNull);
    slow.complete(CopyDeviceList(devices: repository.storage));
  });

  test('disconnect during metadata read is detected even before the session signal arrives', () async {
    final repository = FakeCopyEnvironment();
    var available = true;
    final cubit = await ready(repository, available: () => available);
    final slow = Completer<CopyDeviceList>();
    repository.readDevices = () => slow.future;
    final refresh = cubit.refreshDevices();
    available = false;
    slow.complete(CopyDeviceList(devices: repository.storage));
    expect(await refresh, false);
    expect(cubit.state.sessionAvailable, false);
    expect(cubit.state.preview, isNull);
    expect(await cubit.submit(), false);
  });

  test('routine token issuance cannot mix a different binding into a confirmed preview or POST', () async {
    final repository = FakeCopyEnvironment();
    var issued = 0;
    repository.readSource = () async => SourceBinding(sourceMediaId: 'source', displayName: 'source', token: 'issued-${++issued}', expiresAt: DateTime.now().add(const Duration(minutes: 2)), verifiedReadOnly: true);
    final cubit = await ready(repository);
    final confirmed = cubit.state.sourceBindingToken;
    await cubit.refreshDevices();
    expect(cubit.state.sourceBindingToken, confirmed);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
    expect(await cubit.submit(), true);
    expect(repository.createdDraft!.sourceBindingToken, confirmed);
    expect(repository.drafts.last.sourceBindingToken, confirmed);
    expect(repository.createCalls, 1);
    expect(issued, greaterThan(3));
  });

  test('background during initialization detaches old reads and resumes initialization', () async {
    final repository = FakeCopyEnvironment();
    final gate = Completer<CopyDeviceList>();
    repository.readDevices = () => gate.future;
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    addTearDown(cubit.close);
    final old = cubit.initialize();
    await until(() => repository.deviceCalls == 1);
    cubit.setPageActive(false);
    repository.readDevices = null;
    cubit.setPageActive(true);
    await until(() => cubit.state.copyReady);
    gate.complete(const CopyDeviceList(devices: []));
    await old;
    expect(cubit.state.devices, isNotEmpty);
    expect(cubit.state.loadingDevices, false);
  });

  test('authoritative preference version drift invalidates a confirmed token', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.preferenceVersion++;
    await cubit.refreshDevices();
    expect(cubit.state.preview, isNull);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.configurationChanged);
    expect(await cubit.submit(), false);
    expect(await cubit.fetchPreview(), true);
    expect(cubit.state.preferencesVersion, 2);
  });

  test('external copy preferences signal invalidates the current configuration', () async {
    final repository = FakeCopyEnvironment(), bus = AppDataChangeBus();
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, dataChanges: bus, pollInterval: Duration.zero);
    addTearDown(cubit.close);
    addTearDown(bus.dispose);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    bus.publish({AppDataResource.copyPreferences});
    await until(() => cubit.state.preview == null);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.configurationChanged);
    expect(await cubit.submit(), false);
  });

  test('diagnostic failure cannot bypass invalidation and does not receive raw exception text', () async {
    final repository = FakeCopyEnvironment();
    final entries = <Map<String, dynamic>>[];
    final cubit = CopyConfigCubit(
      repository,
      batchId: 'b',
      scope: CopyScope.batchAllAssets,
      pollInterval: Duration.zero,
      diagnostic: (entry) {
        entries.add(entry);
        throw StateError('diagnostic disk full');
      },
    );
    addTearDown(cubit.close);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    repository.makePreview = (_) async => throw const ApiException(message: 'private payload', code: 'COPY_TARGET_NOT_PRESENT', statusCode: 409);
    expect(await cubit.submit(), false);
    expect(entries.toString(), contains('COPY_TARGET_NOT_PRESENT'));
    expect(entries.toString(), isNot(contains('private payload')));
    expect(cubit.state.preview, isNull);
    expect(repository.createCalls, 0);
  });

  test('an old second-preview completion cannot release a newer POST latch', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    final gate = Completer<CopyPreview>(), response = repository.previewFor(cubit.state.draft);
    repository.makePreview = (_) => gate.future;
    final old = cubit.submit();
    await until(() => repository.previewCalls == 2);
    cubit.selectTarget('other-target');
    repository.makePreview = null;
    expect(await cubit.fetchPreview(), true);
    repository.pendingCreate = Completer<CopyJobSummary>();
    final current = cubit.submit();
    await until(() => repository.createCalls == 1);
    gate.complete(response);
    expect(await old, false);
    expect(cubit.state.submitting, true);
    expect(await cubit.submit(), false);
    repository.pendingCreate!.complete(const CopyJobSummary(copyJobId: 'current-job', state: 'queued', eventSeq: 0));
    expect(await current, true);
    expect(repository.createCalls, 1);
  });

  test('preference saves serialize versions and block preview while acknowledgement is pending', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    final firstAck = Completer<CopyPreferences>();
    repository.savePolicy = (value, version) async => version == 1 ? await firstAck.future : CopyPreferences(pairPolicy: value, version: version + 1, origin: 'user_saved');
    final first = cubit.setPairPolicy(PairPolicy.jpegOnly);
    await until(() => repository.savedVersions.isNotEmpty);
    final second = cubit.setPairPolicy(PairPolicy.both);
    expect(cubit.state.savingPreferences, true);
    expect(cubit.state.canFetchPreview, false);
    expect(await cubit.fetchPreview(), false);
    firstAck.complete(const CopyPreferences(pairPolicy: PairPolicy.jpegOnly, version: 2, origin: 'user_saved'));
    await Future.wait([first, second]);
    expect(repository.savedVersions, [1, 2]);
    expect(cubit.state.preferencesVersion, 3);
    expect(cubit.state.pairPolicy, PairPolicy.both);
    expect(cubit.state.savingPreferences, false);
    expect(cubit.state.preview, isNull);
  });

  test('re-preflight cancels the expiry of the discarded preview', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(milliseconds: 100);
    final cubit = await ready(repository);
    repository.previewLifetime = const Duration(minutes: 1);
    final fresh = repository.previewFor(cubit.state.draft), gate = Completer<CopyPreview>();
    repository.makePreview = (_) => gate.future;
    final fetching = cubit.fetchPreview();
    await until(() => repository.previewCalls == 2);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    gate.complete(fresh);
    expect(await fetching, true);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
  });

  test('a source binding not verified read-only cannot authorize a preview', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.verifiedReadOnly = false;
    await cubit.refreshDevices();
    expect(cubit.state.canFetchPreview, false);
    expect(await cubit.submit(), false);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.bindingChanged);
    expect(repository.createCalls, 0);
  });

  for (final source in [true, false]) {
    test('authoritative ${source ? 'source' : 'target'} unplug invalidates preview and blocks POST', () async {
      final repository = FakeCopyEnvironment();
      final cubit = await ready(repository);
      repository.storage[source ? 0 : 1] = b3Device(source ? 'source' : 'target', source: source, target: !source, online: false);
      await cubit.refreshDevices();
      expect(cubit.state.preview, isNull);
      expect(cubit.state.preflightStatus, CopyPreflightStatus.invalidated);
      expect(cubit.state.submissionBlockReason, contains(source ? '相机卡已断开' : '目标 U 盘已断开'));
      expect(await cubit.submit(), false);
      expect(repository.createCalls, 0);
      expect(cubit.state.targetMediaId, 'target');
      repository.storage[source ? 0 : 1] = b3Device(source ? 'source' : 'target', source: source, target: !source);
      await cubit.refreshDevices();
      expect(cubit.state.preflightStatus, CopyPreflightStatus.needsRecheck);
      expect(cubit.state.preflightNotice, '设备已恢复，请重新预检后开始复制。');
      expect(await cubit.submit(), false);
      expect(await cubit.fetchPreview(), true);
      expect(await cubit.submit(), true);
      expect(repository.createCalls, 1);
    });
  }

  test('missing selected target is not silently replaced by another available disk', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.storage.removeAt(1);
    await cubit.refreshDevices();
    expect(cubit.state.targetMediaId, 'target');
    expect(cubit.state.submissionBlockReason, contains('目标 U 盘已断开'));
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('network failure marks device data stale, never fabricates an unplug', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    repository.readDevices = () async => throw const SocketException('network');
    expect(await cubit.refreshDevices(), false);
    expect(cubit.state.devicesFresh, false);
    expect(cubit.state.devices.every((d) => d.online), true);
    expect(cubit.state.preflightNotice, contains('状态暂时无法确认'));
    expect(cubit.state.preflightNotice, isNot(contains('拔')));
    expect(await cubit.submit(), false);
    repository.readDevices = null;
    await cubit.refreshDevices();
    expect(cubit.state.preview, isNull);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.needsRecheck);
  });

  for (final code in ['COPY_SOURCE_NOT_PRESENT', 'COPY_TARGET_NOT_PRESENT', 'COPY_TARGET_READ_ONLY', 'UNKNOWN_CONFLICT']) {
    test('submit failure $code clears old token instead of leaving Start enabled', () async {
      final repository = FakeCopyEnvironment();
      final cubit = await ready(repository);
      repository.makePreview = (_) async => throw ApiException(message: code, code: code, statusCode: 409);
      expect(await cubit.submit(), false);
      expect(cubit.state.preview, isNull);
      expect(cubit.state.submissionBlockReason, isNotNull);
      expect(repository.createCalls, 0);
      repository.makePreview = null;
      await cubit.refreshDevices();
      expect(cubit.state.preview, isNull);
      expect(await cubit.fetchPreview(), true);
      expect(cubit.state.error, isNull);
    });
  }

  for (final change in ['conflict', 'target', 'scope', 'review', 'embed', 'pair']) {
    test('$change change rejects an already in-flight preview', () async {
      final repository = FakeCopyEnvironment();
      final cubit = await ready(repository);
      final response = repository.previewFor(cubit.state.draft);
      final gate = Completer<CopyPreview>();
      repository.makePreview = (_) => gate.future;
      final loading = cubit.fetchPreview();
      await until(() => repository.previewCalls == 2);
      switch (change) {
        case 'conflict':
          cubit.setConflictStrategy(ConflictStrategy.keepBoth);
        case 'target':
          cubit.selectTarget('other-target');
        case 'scope':
          cubit.setScope(CopyScope.recognizedAssets);
        case 'review':
          cubit.setReviewExportEnabled(true);
        case 'embed':
          cubit.setEmbedReviewMetadata(false);
        case 'pair':
          await cubit.setPairPolicy(PairPolicy.both);
      }
      gate.complete(response);
      expect(await loading, false);
      expect(cubit.state.preview, isNull);
      expect(await cubit.submit(), false);
      expect(repository.createCalls, 0);
    });
  }

  test('binding changes during the second preview cannot submit the old draft', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    final response = repository.previewFor(cubit.state.draft), gate = Completer<CopyPreview>();
    repository.makePreview = (_) => gate.future;
    final submitting = cubit.submit();
    await until(() => repository.previewCalls == 2);
    repository.storage.add(b3Device('new-source', source: true, target: false));
    repository.sourceId = 'new-source';
    repository.bindingToken = 'binding-new';
    await cubit.refreshDevices();
    gate.complete(response);
    expect(await submitting, false);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.bindingChanged);
    expect(cubit.state.preview, isNull);
    expect(repository.createCalls, 0);
  });

  test('final device read detects unplug while the second preflight was running', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    final response = repository.previewFor(cubit.state.draft), gate = Completer<CopyPreview>();
    repository.makePreview = (_) => gate.future;
    final submitting = cubit.submit();
    await until(() => repository.previewCalls == 2);
    repository.storage[1] = b3Device('target', online: false);
    gate.complete(response);
    expect(await submitting, false);
    expect(repository.createCalls, 0);
    expect(cubit.state.submissionBlockReason, contains('目标 U 盘已断开'));
  });

  test('refresh requests coalesce and stale old-session reads cannot overwrite recovery', () async {
    final repository = FakeCopyEnvironment(), sessions = StreamController<void>.broadcast(sync: true);
    var available = true;
    final cubit = await ready(repository, sessions: sessions.stream, available: () => available);
    addTearDown(sessions.close);
    final gate = Completer<CopyDeviceList>();
    repository.readDevices = () => gate.future;
    final before = repository.deviceCalls;
    final first = cubit.refreshDevices(), second = cubit.refreshDevices();
    expect(identical(first, second), true);
    expect(repository.deviceCalls, before + 1);
    available = false;
    sessions.add(null);
    expect(cubit.state.preview, isNull);
    final blockedCalls = repository.deviceCalls;
    await cubit.refreshDevices();
    expect(repository.deviceCalls, blockedCalls);
    repository.readDevices = null;
    available = true;
    sessions.add(null);
    await until(() => cubit.state.devicesFresh);
    gate.complete(CopyDeviceList(devices: [b3Device('source', source: true, target: false)]));
    expect(await first, false);
    expect(cubit.state.targetDevice?.online, true);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.needsRecheck);
  });

  test('preview expiry fires without another tap', () async {
    final repository = FakeCopyEnvironment()..previewLifetime = const Duration(milliseconds: 70);
    final cubit = await ready(repository);
    await until(() => cubit.state.preview == null);
    expect(cubit.state.invalidationReason, CopyPreflightInvalidation.expired);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 0);
  });

  test('visible polling stops in background and requires a new preview after returning', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository, poll: const Duration(milliseconds: 20));
    final initial = repository.deviceCalls;
    await until(() => repository.deviceCalls > initial);
    cubit.setPageActive(false);
    final paused = repository.deviceCalls;
    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(repository.deviceCalls, paused);
    expect(cubit.state.preview, isNull);
    cubit.setPageActive(true);
    await until(() => repository.deviceCalls > paused && cubit.state.devicesFresh);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.needsRecheck);
    expect(await cubit.submit(), false);
  });

  test('successful POST arriving after disconnect remains a single persisted job', () async {
    final repository = FakeCopyEnvironment()..pendingCreate = Completer<CopyJobSummary>();
    final saved = <String>[];
    var available = true;
    final cubit = await ready(repository, available: () => available, onCreated: (job) async => saved.add(job.copyJobId));
    final submitting = cubit.submit();
    await until(() => repository.createCalls == 1);
    available = false;
    cubit.sessionChanged();
    repository.pendingCreate!.complete(const CopyJobSummary(copyJobId: 'posted-job', state: 'queued', eventSeq: 0));
    expect(await submitting, true);
    expect(saved, ['posted-job']);
    expect(cubit.state.submitted, true);
    expect(await cubit.submit(), false);
    expect(repository.createCalls, 1);
  });
}
