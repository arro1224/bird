# BLE B5/B6 DPP and Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Member B DPP presentation lifecycle and prove startup recovery, dynamic-address migration, and production Fake isolation on top of `thirdtime@290f801fb38ae1a96b2410bdf75c2d02b8a13e2c` without modifying Member A code.

**Architecture:** Keep the existing `NetworkProvisioningCubit` and page. Add only safe DPP result classification and presentation actions, then validate A5/A6 through black-box integration tests and a stronger production-integrity gate. B6 public-layer failures stop execution and are reported as Member A blockers instead of being patched in A-owned files.

**Tech Stack:** Flutter, Dart, `flutter_bloc`, `flutter_test`, Dio, `web_socket_channel`, local loopback HTTP/WebSocket tests, repository Fake injection.

---

## Baseline and ownership gate

- Start from local `part2` containing design commit `244ce661f` on top of `thirdtime@290f801fb38ae1a96b2410bdf75c2d02b8a13e2c`.
- Do not merge `origin/part1`.
- Keep these paths read-only throughout implementation:
  - `android/app/src/main/java/**`
  - `lib/bird_companion/features/connection/data/ble/**`
  - `lib/bird_companion/features/connection/data/platform/**`
  - `lib/bird_companion/features/connection/domain/**`
  - `lib/bird_companion/features/connection/data/provisioning_repository_impl.dart`
  - `lib/bird_companion/features/connection/data/connection_repository_impl.dart`
  - `lib/bird_companion/core/session/**`
  - `lib/bird_companion/app/app_dependencies.dart`
- Allowed production changes are limited to connection presentation and the release integrity checker.
- A failing B6 public-contract test is evidence of an A5/A6 blocker. Do not make it green by editing a read-only path.

## File map

- Modify `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`: classify DPP-only local outcomes without retaining diagnostics.
- Modify `lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart`: render DPP unavailable and retry actions with fixed safe copy.
- Modify `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`: cover DPP unavailable, cancellation, timeout/failure, system handoff, final confirmation, and secret stripping.
- Modify `test/bird_companion/features/connection/network_provisioning_page_test.dart`: cover safe DPP and network-recovery pages and callback rules.
- Create `test/bird_companion/features/connection/b5_b6_session_recovery_test.dart`: black-box startup and dynamic-address integration contract.
- Create `test/bird_companion/release_fake_ble_isolation_test.dart`: lock the production dependency and gate requirements.
- Modify `tool/release/verify_production_integrity.dart`: require Real BLE/Wi-Fi/DPP construction and dynamic recovery wiring while forbidding Fake imports/construction.

### Task 1: Classify B5 DPP outcomes in the Cubit

**Files:**
- Modify: `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`
- Modify: `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`

- [ ] **Step 1: Add imports and failing DPP outcome tests**

Ensure the Cubit test imports the error model:

```dart
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
```

Add these tests immediately before the closing brace of the existing `NetworkProvisioningCubit STA and DPP` group:

```dart
test('maps unavailable phone DPP to a dedicated safe phase', () async {
  const diagnostic = 'DPP:K:SYNTHETIC_PRIVATE_DIAGNOSTIC;;';
  final repository = FakeProvisioningRepository(
    startDppError: const ProvisioningException(
      code: ProvisioningErrorCode.phoneDppNotSupported,
      retryable: false,
      diagnosticMessage: diagnostic,
    ),
  );
  final cubit = NetworkProvisioningCubit(repository);
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  cubit.openWifiProvisioning(_deviceInfo());

  await cubit.startDppProvisioning();

  expect(cubit.state.phase, NetworkProvisioningPhase.dppUnavailable);
  expect(cubit.state.activeOperationId, isNull);
  expect(cubit.state.canCancel, isFalse);
  expect(cubit.state.error, isNull);
  expect(cubit.state.toString(), isNot(contains(diagnostic)));
  expect(repository.calls.where((call) => call == 'startDppProvisioning'), hasLength(1));
});

test('maps a system DPP cancellation to the cancelled result', () async {
  final repository = FakeProvisioningRepository(
    startDppResult: const CommandAccepted(
      operationId: 'op_dpp_cancelled',
      desiredMode: ProvisioningNetworkMode.infrastructureSta,
      provisioningMethod: ProvisioningMethod.androidDpp,
    ),
  );
  final cubit = NetworkProvisioningCubit(repository);
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  cubit.openWifiProvisioning(_deviceInfo());
  await cubit.startDppProvisioning();

  repository.emitError(
    const ProvisioningException(
      code: ProvisioningErrorCode.userCancelledDppDialog,
      retryable: false,
      diagnosticMessage: 'private system result',
    ),
  );
  await Future<void>.delayed(Duration.zero);

  expect(cubit.state.phase, NetworkProvisioningPhase.cancelled);
  expect(cubit.state.error, isNull);
  expect(cubit.state.activeOperationId, isNull);
  expect(cubit.state.canCancel, isFalse);
});

test('keeps retryable DPP failures sanitized', () async {
  final repository = FakeProvisioningRepository(
    startDppError: const ProvisioningException(
      code: ProvisioningErrorCode.systemDppFailed,
      retryable: true,
      diagnosticMessage: 'platform result contains private data',
    ),
  );
  final cubit = NetworkProvisioningCubit(repository);
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  cubit.openWifiProvisioning(_deviceInfo());

  await cubit.startDppProvisioning();

  expect(cubit.state.phase, NetworkProvisioningPhase.failure);
  final error = cubit.state.error as ProvisioningException;
  expect(error.code, ProvisioningErrorCode.systemDppFailed);
  expect(error.retryable, isTrue);
  expect(error.diagnosticMessage, isNull);
});

test('system DPP handoff waits for box confirmation before success', () async {
  final repository = FakeProvisioningRepository(
    startDppResult: const CommandAccepted(
      operationId: 'op_dpp_success',
      desiredMode: ProvisioningNetworkMode.infrastructureSta,
      provisioningMethod: ProvisioningMethod.androidDpp,
    ),
    networkStatus: _networkStatus(
      mode: ProvisioningNetworkMode.infrastructureSta,
      operationState: NetworkOperationState.staConnected,
      operationId: 'op_dpp_success',
      baseUri: Uri.parse('http://192.0.2.20'),
    ),
  );
  final cubit = NetworkProvisioningCubit(repository);
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  cubit.openWifiProvisioning(_deviceInfo());
  await cubit.startDppProvisioning();

  repository.emitEvent(
    ProvisioningEvent.fromJson({
      'protocol_version': '1.0-rc4',
      'type': 'dpp_bootstrap_ready',
      'request_id': 'request-dpp-bootstrap',
      'device_id': _deviceInfo().deviceId,
      'ok': true,
      'payload': {
        'operation_id': 'op_dpp_success',
        'operation_state': 'waiting_dpp_configurator',
        'dpp_uri': 'DPP:K:SYNTHETIC_PUBLIC_KEY;C:81/1;;',
        'expires_in_seconds': 120,
      },
    }),
  );
  await Future<void>.delayed(Duration.zero);
  expect(cubit.state.phase, NetworkProvisioningPhase.preparingDpp);
  expect(
    cubit.state.operationState,
    NetworkOperationState.waitingDppConfigurator,
  );
  expect(cubit.state.baseUri, isNull);

  repository.emitEvent(
    ProvisioningEvent(
      type: ProvisioningEventType.staConnected,
      requestId: 'request-dpp-connected',
      deviceId: _deviceInfo().deviceId,
      payload: StaConnected(
        operationId: 'op_dpp_success',
        ssid: 'Synthetic-WiFi',
        ipv4: '192.0.2.20',
        prefixLength: 24,
        gatewayIpv4: '192.0.2.1',
        baseUri: Uri.parse('http://192.0.2.20'),
        networkKind: StaNetworkKind.router,
        provisioningMethod: ProvisioningMethod.androidDpp,
      ),
    ),
  );
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);

  expect(cubit.state.phase, NetworkProvisioningPhase.success);
  expect(cubit.state.baseUri, Uri.parse('http://192.0.2.20'));
});
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_cubit_test.dart --plain-name 'maps unavailable phone DPP to a dedicated safe phase'
```

Expected: compile failure because `NetworkProvisioningPhase.dppUnavailable` does not exist.

- [ ] **Step 3: Add the dedicated phase and one safe DPP outcome mapper**

Add `dppUnavailable` immediately after `preparingDpp`:

```dart
enum NetworkProvisioningPhase {
  idle,
  methodUnavailable,
  startingDirectAp,
  stoppingDirectAp,
  choosingWifiMethod,
  scanningWifi,
  choosingWifiNetwork,
  enteringWifiManually,
  configuringSta,
  preparingDpp,
  dppUnavailable,
  confirmingNetwork,
  success,
  stopped,
  recovered,
  cancelled,
  failure,
}
```

Add this private method before `_onEvent`:

```dart
void _emitDppOutcome(Object error) {
  final safeError = _safePresentationError(error);
  final phase = safeError is ProvisioningException
      ? switch (safeError.code) {
          ProvisioningErrorCode.userCancelledDppDialog =>
            NetworkProvisioningPhase.cancelled,
          ProvisioningErrorCode.phoneDppNotSupported ||
          ProvisioningErrorCode.systemDppActivityUnavailable ||
          ProvisioningErrorCode.systemDppInvalidUri =>
            NetworkProvisioningPhase.dppUnavailable,
          _ => NetworkProvisioningPhase.failure,
        }
      : NetworkProvisioningPhase.failure;
  emit(
    state.copyWith(
      phase: phase,
      error: phase == NetworkProvisioningPhase.failure ? safeError : null,
      clearError: phase != NetworkProvisioningPhase.failure,
      clearOperation: true,
      canCancel: false,
    ),
  );
}
```

Replace the `startDppProvisioning()` catch-body emission with:

```dart
} catch (error) {
  if (isClosed || generation != _generation) return;
  _emitDppOutcome(error);
}
```

At the start of `_onEventError`, after the trusted-device guard, add:

```dart
if (state.phase == NetworkProvisioningPhase.preparingDpp) {
  _emitDppOutcome(error);
  return;
}
```

- [ ] **Step 4: Format and run the complete Cubit test file**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format lib\bird_companion\features\connection\presentation\network_provisioning_cubit.dart test\bird_companion\features\connection\network_provisioning_cubit_test.dart
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_cubit_test.dart
```

Expected: all Cubit tests pass, including the three new B5 cases.

- [ ] **Step 5: Commit the B5 Cubit behavior**

```powershell
git add lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart test/bird_companion/features/connection/network_provisioning_cubit_test.dart
git commit -m "feat(connection): classify B5 DPP outcomes"
```

### Task 2: Render safe B5 DPP actions

**Files:**
- Modify: `test/bird_companion/features/connection/network_provisioning_page_test.dart`
- Modify: `lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart`

- [ ] **Step 1: Add the error import and failing Widget tests**

Add:

```dart
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
```

Add these tests before the closing `}` of `main()`:

```dart
testWidgets('DPP unavailable returns to the safe method choice', (tester) async {
  final repository = FakeProvisioningRepository(
    startDppError: const ProvisioningException(
      code: ProvisioningErrorCode.systemDppActivityUnavailable,
      retryable: false,
      diagnosticMessage: 'DPP:K:PRIVATE;;',
    ),
  );
  final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  await tester.pumpWidget(_pageHarness(cubit));

  await tester.tap(find.text('使用 DPP 安全配网'));
  await tester.pump();

  expect(find.text('手机暂不支持 DPP 配网'), findsOneWidget);
  expect(find.text('请选择搜索 Wi-Fi 或手动输入继续连接。'), findsOneWidget);
  expect(find.textContaining('DPP:K:'), findsNothing);
  await tester.tap(find.text('选择其他方式'));
  await tester.pump();
  expect(find.text('选择 Wi-Fi 配网方式'), findsOneWidget);
});

testWidgets('retryable DPP failure exposes one safe retry action', (tester) async {
  final repository = FakeProvisioningRepository(
    startDppError: const ProvisioningException(
      code: ProvisioningErrorCode.systemDppFailed,
      retryable: true,
      diagnosticMessage: 'private platform result',
    ),
  );
  final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  await tester.pumpWidget(_pageHarness(cubit));

  await tester.tap(find.text('使用 DPP 安全配网'));
  await tester.pump();
  expect(find.text('重新尝试 DPP'), findsOneWidget);
  expect(find.textContaining('private platform result'), findsNothing);

  await tester.tap(find.text('重新尝试 DPP'));
  await tester.pump();
  expect(
    repository.calls.where((call) => call == 'startDppProvisioning'),
    hasLength(2),
  );
});

testWidgets('DPP timeout still offers a safe fresh attempt', (tester) async {
  final repository = FakeProvisioningRepository(
    startDppError: const ProvisioningException(
      code: ProvisioningErrorCode.dppTimeout,
      retryable: false,
      diagnosticMessage: 'private timeout context',
    ),
  );
  final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  await tester.pumpWidget(_pageHarness(cubit));

  await tester.tap(find.text('使用 DPP 安全配网'));
  await tester.pump();

  expect(find.text('重新尝试 DPP'), findsOneWidget);
  expect(find.textContaining('private timeout context'), findsNothing);
});
```

Add this reusable harness below `main()`:

```dart
Widget _pageHarness(
  NetworkProvisioningCubit cubit, {
  ValueChanged<Uri>? onCompleted,
  VoidCallback? onBack,
}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: BlocProvider.value(
      value: cubit,
      child: NetworkProvisioningPage(
        onBack: onBack ?? cubit.backToMethodSelection,
        onCompleted: onCompleted,
      ),
    ),
  ),
);
```

- [ ] **Step 2: Run both Widget tests and verify RED**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_page_test.dart --plain-name 'DPP unavailable returns to the safe method choice'
```

Expected: failure because the `dppUnavailable` phase has no page branch and the required copy is absent.

- [ ] **Step 3: Add the DPP-unavailable page branch**

In the phase switch, add:

```dart
NetworkProvisioningPhase.dppUnavailable => _MessageView(
  icon: Icons.phonelink_erase_rounded,
  title: '手机暂不支持 DPP 配网',
  message: '请选择搜索 Wi-Fi 或手动输入继续连接。',
  actionLabel: '选择其他方式',
  onAction: cubit.returnToWifiMethodSelection,
),
```

Add this Cubit method next to `showManualWifi()`:

```dart
void returnToWifiMethodSelection() {
  _generation++;
  _clearScanAccumulator();
  emit(
    state.copyWith(
      phase: NetworkProvisioningPhase.choosingWifiMethod,
      clearOperation: true,
      clearOperationState: true,
      clearNetworks: true,
      clearBaseUri: true,
      clearConfirmedMode: true,
      clearRecoveredMode: true,
      clearError: true,
      canCancel: false,
    ),
  );
}
```

- [ ] **Step 4: Add a DPP-only retry action to the failure page**

Replace the failure branch with:

```dart
NetworkProvisioningPhase.failure => _FailureView(
  error: state.error,
  onBack: widget.onBack,
  onRetry: _canRetryDpp(state)
      ? () => unawaited(cubit.startDppProvisioning())
      : null,
),
```

Extend `_FailureView`:

```dart
class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.error,
    required this.onBack,
    this.onRetry,
  });

  final Object? error;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = UserMessageMapper.fromError(
      error ?? const NetworkStatusConfirmationException(),
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
      children: [
        ErrorNotice(title: message.title, message: message.message),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          BirdButton(label: '重新尝试 DPP', onPressed: onRetry),
        ],
        const SizedBox(height: AppSpacing.md),
        BirdButton(
          label: '返回连接方式',
          onPressed: onBack,
          variant: BirdButtonVariant.outlined,
        ),
      ],
    );
  }
}
```

Add this safe classifier near the bottom of the page file:

```dart
bool _canRetryDpp(NetworkProvisioningState state) {
  final error = state.error;
  if (error is! ProvisioningException) return false;
  return error.code == ProvisioningErrorCode.systemDppFailed ||
      error.code == ProvisioningErrorCode.dppTimeout;
}
```

Add the error-model import to the page:

```dart
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
```

- [ ] **Step 5: Format and run all B5 presentation tests**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format lib\bird_companion\features\connection\presentation\network_provisioning_cubit.dart lib\bird_companion\features\connection\presentation\pages\network_provisioning_page.dart test\bird_companion\features\connection\network_provisioning_page_test.dart
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_cubit_test.dart test\bird_companion\features\connection\network_provisioning_page_test.dart
```

Expected: all B5 Cubit and Widget tests pass.

- [ ] **Step 6: Commit the B5 pages**

```powershell
git add lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart test/bird_companion/features/connection/network_provisioning_page_test.dart
git commit -m "feat(connection): complete B5 DPP presentation"
```

### Task 3: Lock the B6 network-recovery presentation contract

**Files:**
- Modify: `test/bird_companion/features/connection/network_provisioning_page_test.dart`

- [ ] **Step 1: Add a recovery regression test using a secret-bearing domain payload**

Add:

```dart
testWidgets('network recovery is not reported as DPP success', (tester) async {
  final repository = FakeProvisioningRepository(
    startDppResult: const CommandAccepted(
      operationId: 'op_dpp_recovery',
      desiredMode: ProvisioningNetworkMode.infrastructureSta,
      provisioningMethod: ProvisioningMethod.androidDpp,
    ),
  );
  final cubit = NetworkProvisioningCubit(repository)..openWifiProvisioning(_deviceInfo());
  var completed = false;
  addTearDown(cubit.close);
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    _pageHarness(cubit, onCompleted: (_) => completed = true),
  );
  await tester.tap(find.text('使用 DPP 安全配网'));
  await tester.pump();

  repository.emitEvent(
    ProvisioningEvent(
      type: ProvisioningEventType.networkRecovered,
      requestId: 'request-recovery',
      deviceId: 'bbx-0123456789abcdef0123456789abcdef',
      payload: NetworkRecovered(
        operationId: 'op_dpp_recovery',
        activeMode: ProvisioningNetworkMode.directAp,
        operationState: NetworkOperationState.idle,
        recoveredMode: ProvisioningNetworkMode.directAp,
        recoveryReason: 'previous_sta_connect_failed',
        ssid: 'Synthetic-AP',
        security: WifiSecurity.wpa2Personal,
        passphrase: 'must-never-render',
        gatewayIpv4: '192.0.2.1',
        prefixLength: 24,
        baseUri: Uri.parse('http://192.0.2.1'),
      ),
    ),
  );
  await tester.pump();

  expect(find.text('已恢复可用网络'), findsOneWidget);
  expect(find.text('盒子已加入 Wi-Fi'), findsNothing);
  expect(find.text('完成'), findsNothing);
  expect(find.textContaining('must-never-render'), findsNothing);
  expect(find.textContaining('192.0.2.1'), findsNothing);
  expect(completed, isFalse);
});
```

- [ ] **Step 2: Run the test as a public-baseline contract check**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_page_test.dart --plain-name 'network recovery is not reported as DPP success'
```

Expected: PASS on the A5/A6 public baseline. If it fails because domain/repository recovery data is wrong, stop and report the failure without editing A-owned files. If it fails only because B presentation renders a secret or calls completion, fix only `network_provisioning_page.dart` and rerun.

- [ ] **Step 3: Commit the B6 recovery contract**

```powershell
git add test/bird_companion/features/connection/network_provisioning_page_test.dart
git commit -m "test(connection): lock B6 recovery presentation"
```

### Task 4: Prove B6 startup and dynamic-address session behavior

**Files:**
- Create: `test/bird_companion/features/connection/b5_b6_session_recovery_test.dart`

- [ ] **Step 1: Create the startup recovery test harness**

Create the file with these imports, two startup tests, and fakes:

```dart
import 'dart:async';
import 'dart:io';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/secure_session_store.dart';
import 'package:aves/bird_companion/core/session/session_coordinator.dart';
import 'package:aves/bird_companion/core/session/session_credential.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('offline startup retains the saved device without reconnecting', () async {
    final repository = _RecoveryRepository(saved: _savedDevice);
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    final session = DeviceSessionCubit(
      repository,
      _FixedConnectivityMonitor(false),
      events,
      refresh,
    );
    addTearDown(() async {
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    final restored = await session.restoreSavedSession();

    expect(restored, isFalse);
    expect(repository.reconnectCalls, 0);
    expect(session.state.device, _savedDevice);
    expect(session.state.isConnected, isFalse);
  });

  test('online startup restores once and runs retained-write recovery', () async {
    final repository = _RecoveryRepository(
      saved: _savedDevice,
      reconnectStatus: _status(_savedDevice),
    );
    final events = EventClient();
    final refresh = SessionRefreshCoordinator();
    var recoveryCalls = 0;
    final session = DeviceSessionCubit(
      repository,
      _FixedConnectivityMonitor(true),
      events,
      refresh,
      onConnectionRecovered: () async {
        recoveryCalls++;
      },
    );
    addTearDown(() async {
      await session.close();
      await events.dispose();
      await refresh.dispose();
    });

    final restored = await session.restoreSavedSession();

    expect(restored, isTrue);
    expect(repository.reconnectCalls, 1);
    expect(recoveryCalls, 1);
    expect(session.state.isConnected, isTrue);
    expect(refresh.generation, 2);
  });
}

final _savedDevice = DeviceConnection(
  id: 'bbx-82f41c9e7a3d4b68a1501e21e536c649',
  name: '测试盒子',
  baseUri: Uri.parse('http://192.0.2.10:8080'),
  networkMode: NetworkMode.infrastructureSta,
  isPaired: true,
);

DeviceStatus _status(DeviceConnection device) => DeviceStatus(
  connection: device,
  card: const CardStatus(inserted: true, readable: true),
);

final class _FixedConnectivityMonitor extends ConnectivityMonitor {
  _FixedConnectivityMonitor(this.available);
  final bool available;

  @override
  Stream<bool> get onNetworkChanged => const Stream.empty();

  @override
  Future<bool> get hasNetwork async => available;
}

final class _RecoveryRepository implements ConnectionRepository {
  _RecoveryRepository({required this.saved, this.reconnectStatus});

  final DeviceConnection? saved;
  final DeviceStatus? reconnectStatus;
  int reconnectCalls = 0;

  @override
  Future<DeviceConnection?> savedDevice() async => saved;

  @override
  Future<DeviceStatus> reconnect({CancelToken? cancelToken}) async {
    reconnectCalls++;
    return reconnectStatus ?? (throw StateError('offline'));
  }

  @override
  Future<List<DeviceConnection>> discover() async => const [];

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<DeviceStatus> pair(
    Uri baseUri, {
    required NetworkMode networkMode,
    required String pairingCode,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forgetDevice() async {}
}
```

- [ ] **Step 2: Add the dynamic-address Cubit integration test before the end of `main()`**

```dart
test('dynamic address updates the active device and refreshes B views', () async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  final serverSubscription = server
      .transform(WebSocketTransformer())
      .listen(sockets.add);
  final api = ApiClient();
  final eventEndpoints = <Uri>[];
  final eventAuthorizations = <Object?>[];
  final events = EventClient(
    connector: (endpoint, headers) {
      eventEndpoints.add(endpoint);
      eventAuthorizations.add(headers['Authorization']);
      return IOWebSocketChannel.connect(endpoint, headers: headers);
    },
  );
  final coordinator = SessionCoordinator(
    api,
    events,
    MemorySecureSessionStore(),
  );
  final refresh = SessionRefreshCoordinator();
  final repository = _RecoveryRepository(saved: _savedDevice);
  final session = DeviceSessionCubit(
    repository,
    _FixedConnectivityMonitor(true),
    events,
    refresh,
    sessionCoordinator: coordinator,
  );
  addTearDown(() async {
    await session.close();
    await coordinator.dispose();
    await events.dispose();
    await api.dispose();
    await refresh.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await serverSubscription.cancel();
    await server.close(force: true);
  });

  final oldBase = Uri.parse('http://127.0.0.1:${server.port}');
  final newBase = Uri.parse('http://localhost:${server.port}');
  final oldDevice = _savedDevice.copyWith(baseUri: oldBase);
  await session.setConnectedFromStatus(_status(oldDevice));
  final credential = SessionCredential(
    deviceId: oldDevice.id,
    baseUri: oldBase,
    accessToken: 'synthetic-session-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    apiVersion: 'v1',
    clientId: 'a870bcb1-d423-4d66-96f7-f809ce786543',
  );
  await coordinator.activate(credential);
  expect(sockets, hasLength(1));
  final oldSocket = sockets.single;
  final generationBeforeMove = refresh.generation;

  await coordinator.activate(
    SessionCredential(
      deviceId: credential.deviceId,
      baseUri: newBase,
      accessToken: credential.accessToken,
      expiresAt: credential.expiresAt,
      apiVersion: credential.apiVersion,
      clientId: credential.clientId,
    ),
  );
  await Future<void>.delayed(Duration.zero);
  await oldSocket.done.timeout(const Duration(seconds: 2));

  expect(session.state.device?.id, oldDevice.id);
  expect(session.state.device?.baseUri, newBase);
  expect(refresh.generation, greaterThan(generationBeforeMove));
  expect(api.baseUri, newBase);
  expect(eventEndpoints.last.host, 'localhost');
  expect(eventAuthorizations.last, 'Bearer synthetic-session-token');
  expect(
    api.resolveMediaReference('/media/photo-1/preview'),
    newBase.resolve('/media/photo-1/preview').toString(),
  );

  final generationBeforeForeignEvent = refresh.generation;
  await coordinator.activate(
    SessionCredential(
      deviceId: 'bbx-foreign-device',
      baseUri: oldBase,
      accessToken: credential.accessToken,
      expiresAt: credential.expiresAt,
      apiVersion: credential.apiVersion,
      clientId: credential.clientId,
    ),
  );
  await Future<void>.delayed(Duration.zero);

  expect(session.state.device?.id, oldDevice.id);
  expect(session.state.device?.baseUri, newBase);
  expect(refresh.generation, generationBeforeForeignEvent);
});
```

- [ ] **Step 3: Run the B6 contract file**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format test\bird_companion\features\connection\b5_b6_session_recovery_test.dart
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\b5_b6_session_recovery_test.dart
```

Expected: three tests pass. If a test fails due to `DeviceSessionCubit`, `SessionCoordinator`, repositories, or other A-owned production code, preserve the failing test and report the blocker. Do not modify those production files.

- [ ] **Step 4: Commit the B6 public contract evidence**

```powershell
git add test/bird_companion/features/connection/b5_b6_session_recovery_test.dart
git commit -m "test(connection): verify B6 session recovery"
```

### Task 5: Strengthen production Fake isolation

**Files:**
- Create: `test/bird_companion/release_fake_ble_isolation_test.dart`
- Modify: `tool/release/verify_production_integrity.dart`

- [ ] **Step 1: Write the failing gate-coverage test**

Create:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production integrity gate enforces real connection dependencies', () {
    final gate = File(
      'tool/release/verify_production_integrity.dart',
    ).readAsStringSync();

    for (final requiredCheck in const [
      'PlatformBirdBoxBleDataSource()',
      'MethodChannelBirdBoxWifiPlatform()',
      'MethodChannelBirdBoxDppPlatform()',
      'rememberDynamicAddress:',
      'restoreSavedSession()',
      'FakeBirdBox',
      'FakeProvisioningRepository',
    ]) {
      expect(gate, contains(requiredCheck), reason: requiredCheck);
    }
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\release_fake_ble_isolation_test.dart
```

Expected: FAIL because the current gate does not yet name the Real connection dependencies or Fake types.

- [ ] **Step 3: Add Real dependency requirements and Fake prohibitions to the gate**

After the existing settings requirement, add:

```dart
const dependencyPath = 'lib/bird_companion/app/app_dependencies.dart';
for (final requirement in const <(String, String)>[
  (
    'PlatformBirdBoxBleDataSource()',
    'production dependencies must construct the Real BLE data source',
  ),
  (
    'MethodChannelBirdBoxWifiPlatform()',
    'production dependencies must construct the Android Wi-Fi bridge',
  ),
  (
    'MethodChannelBirdBoxDppPlatform()',
    'production dependencies must construct the Android DPP bridge',
  ),
  (
    'rememberDynamicAddress:',
    'production provisioning must persist dynamic device addresses',
  ),
  (
    'restoreSavedSession()',
    'production startup must restore a saved device session',
  ),
]) {
  _requireContains(
    failures,
    dependencyPath,
    requirement.$1,
    requirement.$2,
  );
}
for (final forbidden in const <(String, String)>[
  (
    'FakeBirdBox',
    'production dependencies must not construct a Fake BirdBox adapter',
  ),
  (
    'FakeProvisioningRepository',
    'production dependencies must not construct a Fake provisioning repository',
  ),
]) {
  _forbid(
    failures,
    dependencyPath,
    forbidden.$1,
    forbidden.$2,
  );
}
```

- [ ] **Step 4: Run the test and executable gate**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format tool\release\verify_production_integrity.dart test\bird_companion\release_fake_ble_isolation_test.dart
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\release_fake_ble_isolation_test.dart
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' run tool\release\verify_production_integrity.dart
```

Expected: test passes and the gate prints:

```text
PASS production integrity: entrypoints, dependencies and fallbacks are valid.
```

- [ ] **Step 5: Commit the release gate**

```powershell
git add tool/release/verify_production_integrity.dart test/bird_companion/release_fake_ble_isolation_test.dart
git commit -m "test(connection): enforce production BLE isolation"
```

### Task 6: Run B5/B6 verification and ownership audit

**Files:**
- Verify: all changed files since `290f801fb38ae1a96b2410bdf75c2d02b8a13e2c`

- [ ] **Step 1: Verify formatting**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format --output=none --set-exit-if-changed lib\bird_companion\features\connection\presentation test\bird_companion\features\connection test\bird_companion\release_fake_ble_isolation_test.dart tool\release\verify_production_integrity.dart
```

Expected: exit code 0 and no formatting changes required.

- [ ] **Step 2: Run the connection and B6 startup suites**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection test\bird_companion\app\disconnected_device_startup_test.dart test\bird_companion\core\offline_sync_test.dart test\bird_companion\release_fake_ble_isolation_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Run static analysis and the production gate**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' analyze --no-pub
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' run tool\release\verify_production_integrity.dart
```

Expected: `No issues found!` and the production-integrity PASS line.

- [ ] **Step 4: Audit sensitive text in B-side changes**

Run:

```powershell
rg -n "diagnosticMessage|dppUri|DPP:|passphrase|pairingCode|accessToken|print\(|debugPrint\(" lib\bird_companion\features\connection\presentation test\bird_companion\features\connection\network_provisioning_cubit_test.dart test\bird_companion\features\connection\network_provisioning_page_test.dart test\bird_companion\features\connection\b5_b6_session_recovery_test.dart
```

Expected: production presentation has no secret-bearing state or output. Test matches are limited to synthetic inputs and explicit negative assertions; no assertion prints or compares a real secret.

- [ ] **Step 5: Audit ownership and whitespace**

Run:

```powershell
git diff --name-only 290f801fb38ae1a96b2410bdf75c2d02b8a13e2c..HEAD
git diff --check 290f801fb38ae1a96b2410bdf75c2d02b8a13e2c..HEAD
```

Expected changed paths are limited to:

```text
docs/superpowers/specs/2026-08-25-ble-b5-b6-dpp-recovery-design.md
docs/superpowers/plans/2026-08-25-ble-b5-b6-dpp-recovery.md
lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart
lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart
test/bird_companion/features/connection/network_provisioning_cubit_test.dart
test/bird_companion/features/connection/network_provisioning_page_test.dart
test/bird_companion/features/connection/b5_b6_session_recovery_test.dart
test/bird_companion/release_fake_ble_isolation_test.dart
tool/release/verify_production_integrity.dart
```

No whitespace errors. If an A-owned path appears, stop before pushing and remove only the unauthorized B-side edit without resetting user work.

- [ ] **Step 6: Build the debug APK using the known valid flavor**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' build apk --debug --flavor birdV1 -t lib\main.dart --no-pub
```

Expected: debug APK build succeeds. Record that this proves build integration only; it does not prove real K7 or real Android Easy Connect behavior.

- [ ] **Step 7: Confirm a clean worktree and report commits**

Run:

```powershell
git status --short --branch
git log --oneline --decorate 290f801fb38ae1a96b2410bdf75c2d02b8a13e2c..HEAD
```

Expected: clean `part2` worktree and separate commits for design, B5 Cubit, B5 pages, B6 recovery contract, B6 session contract, and release isolation. Do not push or merge until the user explicitly requests it.
