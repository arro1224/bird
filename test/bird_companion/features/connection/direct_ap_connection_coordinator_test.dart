import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/direct_ap_connection_coordinator.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_birdbox_wifi_platform.dart';

void main() {
  late FakeBirdBoxWifiPlatform wifi;
  late DirectApConnectionCoordinator owner;
  late CancelToken token;
  setUp(() {
    wifi = FakeBirdBoxWifiPlatform();
    owner = DirectApConnectionCoordinator(wifi);
    token = CancelToken();
    wifi.queueJoinResult(
      const WifiJoinResult(
        outcome: WifiJoinOutcome.joined,
        network: BirdBoxWifiNetwork(handle: '1', ssid: 'Box'),
      ),
    );
  });
  tearDown(() async {
    await owner.dispose();
    await wifi.dispose();
  });

  Future<void> connect({String intent = 'intent', String device = 'box', CancelToken? cancellation}) =>
      owner.connect(deviceId: device, operationId: 'op', intentId: intent, ssid: 'Box', passphrase: 'TEST_ONLY_PASSWORD', cancelToken: cancellation ?? token);

  test('same intent shares the native join future; online survives page token disposal', () async {
    final first = connect();
    expect(identical(first, connect()), isTrue);
    await first;
    owner.markOnline('intent');
    token.cancel('page disposed');
    await Future<void>.delayed(Duration.zero);
    expect(wifi.requestedSsids, ['Box']);
    expect(wifi.releaseCount, 0);
    expect(owner.phase, DirectApConnectionPhase.online);
  });

  test('explicit exit releases once and stale cancellation cannot release a new intent', () async {
    await connect();
    owner.markOnline('intent');
    await connect(intent: 'new', cancellation: CancelToken());
    await owner.release(reason: 'cancelled', intentId: 'intent');
    expect(wifi.releaseCount, 0);
    await owner.release(reason: 'stopped', intentId: 'new');
    expect(wifi.releaseCount, 1);
    expect(wifi.boundNetwork, isNull);
  });

  test('cancelled pending join cannot bind a late onAvailable', () async {
    final gate = Completer<void>();
    wifi.beforeJoin = () => gate.future;
    final pending = connect();
    final failed = expectLater(pending, throwsA(isA<DioException>()));
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await failed;
    expect(wifi.boundNetwork, isNull);
    expect(wifi.releaseCount, 1);
  });

  test('binding failure releases the native request and does not retry the same intent', () async {
    wifi.bindError = StateError('bind failed');
    await expectLater(connect(), throwsStateError);
    await expectLater(connect(), throwsStateError);
    expect(wifi.releaseCount, 1);
    expect(wifi.requestedSsids.length, 1);
  });

  test('different device waits for old release before requesting a new network', () async {
    await connect();
    final gate = Completer<void>();
    wifi.beforeRelease = () => gate.future;
    wifi.queueJoinResult(
      const WifiJoinResult(
        outcome: WifiJoinOutcome.joined,
        network: BirdBoxWifiNetwork(handle: '2', ssid: 'Box'),
      ),
    );
    final next = connect(intent: 'other', device: 'other', cancellation: CancelToken());
    await Future<void>.delayed(Duration.zero);
    expect(wifi.requestedSsids.length, 1);
    gate.complete();
    await next;
    expect(wifi.boundNetwork?.handle, '2');
    expect(wifi.releaseCount, 1);
  });

  test('native loss invalidates the lease and stale callbacks cannot promote it online', () async {
    await connect();
    wifi.loseNetwork();
    owner.markOnline('intent');
    expect(owner.phase, DirectApConnectionPhase.failed);
  });

  test('switching the global selected device releases an old online lease only', () async {
    await connect();
    owner.markOnline('intent');
    await owner.selectDevice('box');
    expect(wifi.releaseCount, 0);
    await owner.selectDevice('other');
    expect(wifi.releaseCount, 1);
    expect(wifi.boundNetwork, isNull);
  });

  test('reused intent observes cancellation of the new verifier token', () async {
    await connect();
    final retry = CancelToken();
    await connect(cancellation: retry);
    token.cancel('old verifier superseded');
    await Future<void>.delayed(Duration.zero);
    expect(wifi.releaseCount, 0);
    retry.cancel('retry page closed');
    await Future<void>.delayed(Duration.zero);
    expect(wifi.releaseCount, 1);
    expect(wifi.boundNetwork, isNull);
  });

  test('cleanup failure preserves the join error and an explicit cleanup can retry', () async {
    wifi.bindError = StateError('first bind error');
    var releases = 0;
    wifi.beforeRelease = () async {
      if (releases++ == 0) throw StateError('cleanup failed');
    };
    await expectLater(connect(), throwsA(isA<StateError>().having((e) => e.message, 'first error', 'first bind error')));
    await owner.release(reason: 'retry_cleanup');
    expect(wifi.releaseCount, 1);
  });
}
