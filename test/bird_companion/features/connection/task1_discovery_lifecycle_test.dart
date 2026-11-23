import 'dart:async';

import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/presentation/provisioning_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/reusable_provisioning_repository.dart';

void main() {
  test('late scan cancellation after owner replacement cannot stop the new session scan', () async {
    final repository = _LateCancellationRepository();
    final page = ProvisioningCubit(repository);
    await page.discover();
    final retry = page.discover();
    await Future<void>.delayed(Duration.zero);
    final stops = repository.calls.where((call) => call == 'stopDiscovery').length;
    repository.claimSession();
    await Future<void>.delayed(Duration.zero);
    repository.cancelled.complete();
    await retry;
    expect(repository.calls.where((call) => call == 'stopDiscovery'), hasLength(stops));
    await page.close();
    await repository.controller.close();
    await repository.dispose();
  });
  test('permission preflight and denial survive foreground without another scan', () async {
    final repository = _LateScanRepository();
    final page = ProvisioningCubit(repository);
    addTearDown(() async {
      await page.close();
      await repository.dispose();
    });
    await page.discover();
    await page.onAppBackgrounded();
    await page.onAppResumed();
    expect(repository.rounds, hasLength(1));
    repository.rounds.single.addError(const ProvisioningException(code: ProvisioningErrorCode.bluetoothPermissionDenied, retryable: true));
    await Future<void>.delayed(Duration.zero);
    expect(page.state.phase, ProvisioningPhase.failure);
    await page.onAppBackgrounded();
    await page.onAppResumed();
    expect(repository.rounds, hasLength(1));
  });
  test('reopening observes trusted GATT without claims, advertisements or teardown', () async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice);
    final owner = repository.owner;
    for (var i = 0; i < 3; i++) {
      final page = ProvisioningCubit(repository);
      await page.discover();
      await Future<void>.delayed(Duration.zero);
      expect(page.state.deviceInfo?.deviceId, firstBleInfo.deviceId);
      expect(page.state.devices, isEmpty);
      expect(page.state.linkStatus, BleLinkStatus.connected);
      await page.close();
      expect(repository.owner, same(owner));
      expect(repository.claims, 0);
      expect(repository.endedSessions, 0);
    }
    expect(repository.calls, isNot(contains('disconnect')));
    await repository.dispose();
  });
  test('rescan preserves current box and merges candidates only by opaque transport', () async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice, advertisements: [firstBleDevice, secondBleDevice, secondBleDevice]);
    final page = ProvisioningCubit(repository);
    addTearDown(() async {
      await page.close();
      await repository.dispose();
    });
    for (var i = 0; i < 3; i++) {
      await page.discover();
      await Future<void>.delayed(Duration.zero);
      expect(page.state.deviceInfo?.deviceId, firstBleInfo.deviceId);
      expect(page.state.devices.map((d) => d.scanId), [secondBleDevice.scanId]);
    }
    expect(repository.claims, 0);
    expect(repository.endedSessions, 0);
    await page.useCurrentDevice();
    await page.returnToDiscovery();
    expect(page.state.deviceInfo?.deviceId, firstBleInfo.deviceId);
    expect(repository.calls.where((c) => c.startsWith('connect:')), isEmpty);
    expect(repository.calls, isNot(contains('disconnect')));
  });
  test('foreground return restarts one scan and leaves GATT intact', () async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice);
    final page = ProvisioningCubit(repository);
    addTearDown(() async {
      await page.close();
      await repository.dispose();
    });
    await page.discover();
    await Future<void>.delayed(Duration.zero);
    await page.onAppBackgrounded();
    await Future.wait([page.onAppResumed(), page.onAppResumed()]);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls.where((c) => c == 'discover'), hasLength(2));
    expect(page.state.linkStatus, BleLinkStatus.connected);
    expect(repository.claims, 0);
    expect(repository.endedSessions, 0);
  });
  test('disconnected current box is removed and cannot be used from cached identity', () async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice);
    final page = ProvisioningCubit(repository);
    addTearDown(() async {
      await page.close();
      await repository.dispose();
    });
    await page.discover();
    await Future<void>.delayed(Duration.zero);
    repository.emitDisconnect();
    await Future<void>.delayed(Duration.zero);
    expect(page.state.deviceInfo, isNull);
    expect(page.state.linkStatus, BleLinkStatus.disconnected);
    await page.useCurrentDevice();
    expect(page.state.phase, isNot(ProvisioningPhase.trusted));
    await page.discover();
    expect(page.state.deviceInfo, isNull);
  });
  test('explicit switch invalidates the old page without old cleanup claiming the new owner', () async {
    final repository = ReusableProvisioningRepository(current: firstBleDevice);
    final old = ProvisioningCubit(repository), next = ProvisioningCubit(repository);
    await next.selectDevice(secondBleDevice);
    await Future<void>.delayed(Duration.zero);
    final owner = repository.owner;
    expect(next.state.deviceInfo?.deviceId, secondBleInfo.deviceId);
    expect(old.state.deviceInfo?.deviceId, secondBleInfo.deviceId);
    expect(repository.calls.where((c) => c == 'disconnect'), hasLength(1));
    final ended = repository.endedSessions;
    await old.close();
    expect(repository.owner, same(owner));
    expect(repository.endedSessions, ended);
    next.retainSession = true;
    await next.close();
    await repository.dispose();
  });
  test('late scan result from a superseded round cannot populate the new list', () async {
    final repository = _LateScanRepository();
    final page = ProvisioningCubit(repository);
    addTearDown(() async {
      await page.close();
      await repository.dispose();
    });
    await page.discover();
    await page.discover();
    repository.rounds.first.add(firstBleDevice);
    repository.rounds.last.add(secondBleDevice);
    await Future<void>.delayed(Duration.zero);
    expect(page.state.devices.map((d) => d.scanId), [secondBleDevice.scanId]);
  });
}

class _LateScanRepository extends ReusableProvisioningRepository {
  final rounds = <StreamController<ProvisioningDevice>>[];
  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) {
    final stream = StreamController<ProvisioningDevice>.broadcast();
    rounds.add(stream);
    return stream.stream;
  }

  @override
  Future<void> dispose() async {
    for (final round in rounds) {
      await round.close();
    }
    await super.dispose();
  }
}

class _LateCancellationRepository extends ReusableProvisioningRepository {
  final cancelled = Completer<void>();
  late final controller = StreamController<ProvisioningDevice>(onCancel: () => cancelled.future);
  @override
  Stream<ProvisioningDevice> discoverDevices({Duration? timeout}) => controller.stream;
}
