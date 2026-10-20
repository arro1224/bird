import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/storage/diagnostic_storage.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:aves/bird_companion/features/connection/presentation/network_provisioning_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/direct_ap_handoff_cubit.dart';
import 'package:aves/bird_companion/features/connection/presentation/pages/direct_ap_handoff_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_provisioning_repository.dart';

const deviceId = 'bbx-0123456789abcdef0123456789abcdef';
final pending = PendingDirectAp(deviceId: deviceId, baseUri: Uri.parse('http://192.168.82.1:8080'), operationId: 'op_direct', ssid: 'BirdBox-7A533A6F');

class MemoryHandoffStorage implements DiagnosticStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 300; ++i) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('State did not settle');
}

void main() {
  test('already ready AP is reused without a second start command', () async {
    final info = ProvisioningDeviceInfo.fromJson(jsonDecode(File('test/contracts/fixtures/ble-device-info.rc4.json').readAsStringSync()) as Map<String, dynamic>);
    final snapshot = ProvisioningEvent.fromJson(jsonDecode(File('test/contracts/fixtures/ble-network-status.rc4.json').readAsStringSync()) as Map<String, dynamic>).payload as ProvisioningNetworkStatus;
    final repository = FakeProvisioningRepository(networkStatus: snapshot);
    final handoff = DirectApHandoffCubit(store: MemoryHandoffStorage(), verify: (_, _) async {});
    final network = NetworkProvisioningCubit(repository, directApHandoff: handoff);
    addTearDown(network.close);
    addTearDown(handoff.close);
    addTearDown(repository.dispose);
    await network.startDirectAp(info);
    await until(() => handoff.state.phase == DirectApHandoffPhase.directApConnected);
    expect(repository.calls.where((call) => call == 'startDirectAp'), isEmpty);
    expect(repository.calls.where((call) => call == 'getNetworkStatus'), hasLength(1));
  });

  test('local credential persistence can be retried explicitly, not automatically', () async {
    var calls = 0;
    final cubit = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      verify: (_, _) async {
        if (++calls == 1) throw const ProvisioningCredentialSaveException();
      },
    );
    addTearDown(cubit.close);
    await cubit.begin(pending);
    await until(() => cubit.state.phase == DirectApHandoffPhase.failure);
    cubit.lifecycleChanged(resumed: true);
    cubit.networkChanged();
    expect(calls, 1);
    await cubit.continueVerification();
    expect(cubit.state.phase, DirectApHandoffPhase.directApConnected);
    expect(calls, 2);
  });
  test('transient first error waits, resume continues, one verification in flight', () async {
    final store = MemoryHandoffStorage();
    final second = Completer<void>();
    var attempts = 0;
    final events = <Map<String, dynamic>>[];
    final cubit = DirectApHandoffCubit(
      store: store,
      retryUnit: const Duration(milliseconds: 40),
      diagnostic: events.add,
      verify: (_, _) async {
        if (++attempts == 1) throw const SocketException('test network unreachable');
        await second.future;
      },
    );
    addTearDown(cubit.close);
    await cubit.begin(pending);
    await until(() => cubit.state.phase == DirectApHandoffPhase.waitingForPhoneApJoin);
    expect(store.read<Map>(DirectApHandoffCubit.pendingKey), pending.toJson());
    cubit.lifecycleChanged(resumed: false);
    cubit.lifecycleChanged(resumed: true);
    cubit.networkChanged();
    unawaited(cubit.continueVerification());
    await until(() => attempts == 2);
    cubit.networkChanged();
    cubit.lifecycleChanged(resumed: true);
    unawaited(cubit.continueVerification());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(attempts, 2);
    second.complete();
    await until(() => cubit.state.phase == DirectApHandoffPhase.directApConnected);
    expect(cubit.state.firstError, 'SocketException');
    expect(store.read<Map>(DirectApHandoffCubit.pendingKey), isNull);
    expect(events.last['event'], 'direct_ap_http_verified');
    expect(events.toString(), isNot(contains('passphrase')));
  });

  for (final error in <Object>[
    const ProvisioningException(code: ProvisioningErrorCode.deviceIdMismatch, retryable: false),
    const ProvisioningException(code: ProvisioningErrorCode.protocolVersionUnsupported, retryable: false),
    const ApiException(message: 'denied', statusCode: 401),
    const ApiException(message: 'denied', statusCode: 403),
    const ApiException(message: 'server error', statusCode: 500, retryable: true),
    StateError('unexpected programming error'),
  ]) {
    test('permanent ${directApErrorKind(error)} stops without retry', () async {
      var calls = 0;
      final cubit = DirectApHandoffCubit(
        store: MemoryHandoffStorage(),
        retryUnit: const Duration(milliseconds: 1),
        verify: (_, _) async {
          ++calls;
          throw error;
        },
      );
      addTearDown(cubit.close);
      await cubit.begin(pending);
      await until(() => cubit.state.phase == DirectApHandoffPhase.failure);
      cubit.lifecycleChanged(resumed: true);
      cubit.networkChanged();
      await cubit.continueVerification();
      expect(calls, 1);
    });
  }

  test('timeout bounds even an uncooperative request; continue is HTTP only', () async {
    var calls = 0;
    final stuck = Completer<void>();
    final cubit = DirectApHandoffCubit(
      store: MemoryHandoffStorage(),
      window: const Duration(milliseconds: 60),
      verify: (_, _) async {
        if (++calls == 1) await stuck.future;
      },
    );
    addTearDown(cubit.close);
    await cubit.begin(pending);
    await until(() => cubit.state.phase == DirectApHandoffPhase.directApJoinTimeout);
    cubit.lifecycleChanged(resumed: true);
    cubit.networkChanged();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1, reason: 'Only an explicit continue may start another waiting window');
    await cubit.continueVerification();
    expect(cubit.state.phase, DirectApHandoffPhase.directApConnected);
    stuck.complete();
    expect(calls, 2);
  });

  test('cancel and start another operation ignores the old late response', () async {
    final stuck = Completer<void>();
    final store = MemoryHandoffStorage();
    var calls = 0;
    final cubit = DirectApHandoffCubit(
      store: store,
      verify: (_, _) async {
        if (++calls == 1) await stuck.future;
      },
    );
    addTearDown(cubit.close);
    await cubit.begin(pending);
    await until(() => calls == 1);
    await cubit.cancel();
    expect(store.read<Map>(DirectApHandoffCubit.pendingKey), isNull);
    await cubit.begin(PendingDirectAp(deviceId: deviceId, baseUri: pending.baseUri, operationId: 'next'));
    await until(() => cubit.state.phase == DirectApHandoffPhase.directApConnected);
    stuck.complete();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.pending!.operationId, 'next');
  });

  test('cold restore keeps non-secret endpoint and uses no BLE rediscovery', () async {
    final store = MemoryHandoffStorage();
    final first = DirectApHandoffCubit(store: store, verify: (_, token) => token.whenCancel.then<void>((error) => throw error));
    await first.begin(pending);
    await first.close();
    var calls = 0;
    final second = DirectApHandoffCubit(
      store: store,
      verify: (value, _) async {
        expect(value.deviceId, deviceId);
        ++calls;
      },
    );
    addTearDown(second.close);
    expect(await second.restore(), isTrue);
    await until(() => second.state.phase == DirectApHandoffPhase.directApConnected);
    expect(calls, 1);
  });

  test('invalid persisted URI cannot dispatch a request', () async {
    final store = MemoryHandoffStorage();
    await store.write(DirectApHandoffCubit.pendingKey, {...pending.toJson(), 'base_uri': 'http://user:secret@evil.test'});
    final cubit = DirectApHandoffCubit(store: store, verify: (_, _) async => fail('must not connect'));
    addTearDown(cubit.close);
    expect(await cubit.restore(), isFalse);
  });

  testWidgets('waiting panel opens WLAN, resumes one HTTP flow and supports back', (tester) async {
    final store = MemoryHandoffStorage();
    final completion = Completer<void>();
    final cubit = DirectApHandoffCubit(store: store, verify: (_, _) => completion.future);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bird_companion/birdbox_wifi/methods'), (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('bird_companion/birdbox_wifi/methods'), null));
    await tester.runAsync(() => cubit.begin(pending));
    var back = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectApHandoffPanel(
            cubit: cubit,
            onBack: () {
              back = true;
              unawaited(cubit.cancel());
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('BirdBox-7A533A6F'), findsOneWidget);
    await tester.tap(find.text('打开 WLAN 设置'));
    await tester.pump();
    expect(calls, ['openWifiSettings']);
    cubit.lifecycleChanged(resumed: true);
    await tester.tap(find.text('我已连接，继续验证'));
    await tester.pump();
    expect(cubit.state.attempt, 1);
    await tester.tap(find.text('返回连接方式'));
    await tester.pump();
    expect(back, isTrue);
    completion.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(cubit.close);
  });

  test('transport retry classification does not treat HTTP responses as network loss', () {
    expect(isTransientDirectApError(ApiException.fromDio(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError))), isTrue);
    expect(
      isTransientDirectApError(
        ApiException.fromDio(
          DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: RequestOptions(), statusCode: 401),
          ),
        ),
      ),
      isFalse,
    );
  });
}
