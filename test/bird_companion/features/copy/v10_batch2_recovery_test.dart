import 'dart:async';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_presentation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_detail_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_copy_environment.dart';

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository, {AppDataChangeBus? changes}) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero, dataChanges: changes);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), true);
  return cubit;
}

void main() {
  testWidgets('failed initialization retries with backoff and recovers without a manual scan', (tester) async {
    final repository = FakeCopyEnvironment()..readDevices = () async => throw StateError('temporarily unavailable');
    final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: const Duration(seconds: 1));
    await cubit.initialize();
    expect(repository.deviceCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(repository.deviceCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(repository.deviceCalls, 2);
    repository.readDevices = null;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(cubit.state.devicesFresh, true);
    expect(cubit.state.devices, isNotEmpty);
    await cubit.close();
  });

  test('concurrent preference retries share one write after a failed creation-time save', () async {
    final repository = FakeCopyEnvironment()..savePolicy = (_, _) async => throw StateError('offline');
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    cubit.setPairPolicy(PairPolicy.both);
    await cubit.fetchPreview();
    await cubit.submit();
    final saved = Completer<CopyPreferences>();
    repository.savePolicy = (_, _) => saved.future;
    final first = cubit.retryPreferenceSave();
    await Future<void>.delayed(Duration.zero);
    final second = cubit.retryPreferenceSave();
    expect(repository.savedVersions.length, 2);
    saved.complete(const CopyPreferences(pairPolicy: PairPolicy.both, version: 2, origin: 'user_saved'));
    await Future.wait([first, second]);
    expect(cubit.state.preferenceSavePending, false);
    expect(repository.createCalls, 1);
  });

  test('background ignores refresh signals and an old request cannot invalidate the resumed preview', () async {
    final repository = FakeCopyEnvironment();
    final changes = AppDataChangeBus();
    final cubit = await ready(repository, changes: changes);
    addTearDown(cubit.close);
    addTearDown(changes.dispose);
    final token = cubit.state.preview!.previewToken;
    final oldRead = Completer<CopyDeviceList>();
    repository.readDevices = () => oldRead.future;
    final pending = cubit.refreshDevices();
    cubit.setAppLifecycleActive(false);
    final reads = repository.deviceCalls;
    changes.publish({AppDataResource.device}, reason: 'test');
    await Future<void>.delayed(Duration.zero);
    expect(repository.deviceCalls, reads);
    repository.readDevices = null;
    cubit.setAppLifecycleActive(true);
    await Future<void>.delayed(Duration.zero);
    oldRead.completeError(StateError('late background failure'));
    await pending;
    expect(cubit.state.preview?.previewToken, token);
    expect(cubit.state.devicesFresh, true);
    expect(cubit.state.devicesError, isNull);
  });

  test('preference save failure is visible; retry cannot create another task', () async {
    final repository = FakeCopyEnvironment()..savePolicy = (_, _) async => throw StateError('offline');
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    cubit.setPairPolicy(PairPolicy.both);
    expect(await cubit.fetchPreview(), true);
    expect(await cubit.submit(), true);
    expect(cubit.state.preferenceSavePending, true);
    expect(cubit.state.preferenceSaveNotice, contains('任务已创建'));
    expect(cubit.state.error, isNull);
    repository.savePolicy = null;
    await cubit.retryPreferenceSave();
    expect(cubit.state.preferenceSavePending, false);
    expect(cubit.state.preferenceSaveNotice, '格式偏好已保存。');
    expect(repository.createCalls, 1);
  });

  test('lost save response is reconciled with server preference without another write', () async {
    final repository = FakeCopyEnvironment()..savePolicy = (_, _) async => throw StateError('lost response');
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    cubit.setPairPolicy(PairPolicy.both);
    await cubit.fetchPreview();
    await cubit.submit();
    repository.preferencePolicy = PairPolicy.both;
    repository.preferenceVersion = 2;
    await cubit.retryPreferenceSave();
    expect(repository.savedVersions.length, 1);
    expect(cubit.state.preferenceSavePending, false);
    expect(cubit.state.preferencesVersion, 2);
  });

  test('retry never overwrites a concurrent preference change', () async {
    final repository = FakeCopyEnvironment()..savePolicy = (_, _) async => throw StateError('offline');
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    cubit.setPairPolicy(PairPolicy.both);
    await cubit.fetchPreview();
    await cubit.submit();
    repository.preferencePolicy = PairPolicy.jpegOnly;
    repository.preferenceVersion = 2;
    await cubit.retryPreferenceSave();
    expect(repository.savedVersions.length, 1);
    expect(cubit.state.preferenceSaveNotice, contains('不会覆盖新偏好'));
    expect(repository.createCalls, 1);
  });

  testWidgets('created-job dialog offers preference-only compensation and updates its result', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCopyEnvironment()..savePolicy = (_, _) async => throw StateError('offline');
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CopyConfigFlow(batchId: 'batch'),
        ),
      ),
    );
    await tester.pump();
    cubit.setPairPolicy(PairPolicy.both);
    await cubit.fetchPreview();
    await cubit.submit();
    await tester.pumpAndSettle();
    expect(find.text('重试保存格式偏好'), findsOneWidget);
    repository.savePolicy = null;
    await tester.tap(find.text('重试保存格式偏好'));
    await tester.pumpAndSettle();
    expect(find.text('格式偏好已保存。'), findsOneWidget);
    expect(find.text('重试保存格式偏好'), findsNothing);
    expect(repository.createCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('a successful empty topology is undetected; filtered absence never certifies removal', () async {
    var fail = false;
    final cubit = CopyJobDetailCubit(
      _Jobs(),
      copyJobId: 'job',
      deviceReader: () async {
        if (fail) throw StateError('unavailable');
        return const CopyDeviceList(devices: []);
      },
    );
    addTearDown(cubit.close);
    await cubit.refreshDeviceNames(force: true);
    const disk = CopyJobDeviceSnapshot(mediaId: 'disk', displayName: 'U 盘 Ee');
    expect(copyTaskDeviceName(source: false, snapshot: disk, devices: cubit.state.devices, devicesFresh: cubit.state.devicesFresh), 'U 盘 Ee（暂未检测到）');
    fail = true;
    await cubit.refreshDeviceNames(force: true);
    expect(copyTaskDeviceName(source: false, snapshot: disk, devices: cubit.state.devices, devicesFresh: cubit.state.devicesFresh), 'U 盘 Ee');
  });

  test('connection retries coalesce and recovery clears an earlier error', () async {
    var readable = false, recovering = false, calls = 0;
    final pending = Completer<bool>();
    final cubit = CopyJobDetailCubit(
      _Jobs(),
      copyJobId: 'job',
      canRead: () => readable,
      sessionRecovering: () => recovering,
      onReconnect: () {
        calls++;
        return pending.future;
      },
    );
    addTearDown(cubit.close);
    cubit.sessionChanged();
    expect(cubit.state.error, isNotNull);
    recovering = true;
    cubit.sessionChanged();
    expect(cubit.state.error, isNull);
    final one = cubit.retryConnection(), two = cubit.retryConnection();
    expect(identical(one, two), true);
    expect(calls, 1);
    readable = true;
    pending.complete(true);
    await one;
    expect(cubit.state.detail?.copyJobId, 'job');
    expect(cubit.state.loading, false);
  });
}

class _Jobs implements CopyJobRepository {
  @override
  Future<CopyJobDetail> getJob(String id) async => const CopyJobDetail(copyJobId: 'job', state: CopyJobState.running, stateVersion: 1, eventSeq: 0, allowedActions: []);
  @override
  Future<CopyJobEventPage> jobEvents(String id, {int? afterSeq}) async => const CopyJobEventPage(events: [], hasMore: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
