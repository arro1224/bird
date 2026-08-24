# BLE B3/B4 Network Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Member B presentation-only Direct AP and existing Wi-Fi provisioning flows on top of the frozen `ProvisioningRepository`, without modifying Member A Android, BLE data, platform, domain, or production-composition code.

**Architecture:** Keep B1/B2 discovery and pairing in `ProvisioningCubit`, and add one independent `NetworkProvisioningCubit` that subscribes to the shared repository event stream and starts only after trusted Device Info is available. Render B3/B4 through focused presentation widgets, keep credentials out of state and fakes, and require a matching `getNetworkStatus()` confirmation before reporting AP or STA success.

**Tech Stack:** Flutter, Dart 3.12, flutter_bloc, flutter_test, existing Bird UI primitives and frozen rc4 provisioning domain.

---

## File map and ownership guard

Create:

- `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`: B3/B4 state, command lifecycle, event filtering, scan aggregation and terminal confirmation.
- `lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart`: phase router and direct/Wi-Fi progress, scan and success views.
- `lib/bird_companion/features/connection/presentation/widgets/sta_network_form.dart`: password-owning selected/manual Wi-Fi form.
- `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`: B3/B4 state-machine tests.
- `test/bird_companion/features/connection/network_provisioning_page_test.dart`: capability, form and rendering widget tests.

Modify:

- `lib/bird_companion/features/connection/presentation/connection_page.dart`: provide the network Cubit and route the post-pairing method choice into B3/B4.
- `lib/bird_companion/features/connection/presentation/pages/connection_method_page.dart`: capability-aware enabled/disabled method cards.
- `lib/bird_companion/features/connection/presentation/widgets/provisioning_method_card.dart`: optional tap and disabled reason.
- `test/bird_companion/features/connection/fakes/fake_provisioning_repository.dart`: safe configurable B3/B4 behavior and event emission.
- `test/bird_companion/features/connection/provisioning_cubit_test.dart`: remove pairing-code material from fake call assertions.
- `test/bird_companion/features/connection/ble_connection_page_test.dart`: preserve B1/B2 behavior and add method capability coverage.

Never modify in this plan:

- `android/app/src/main/java/**`
- `lib/bird_companion/features/connection/data/ble/**`
- `lib/bird_companion/features/connection/data/platform/**`
- `lib/bird_companion/features/connection/domain/**`
- `lib/bird_companion/app/app_dependencies.dart`

### Task 1: Establish the test baseline and secure fake repository

**Files:**
- Modify: `test/bird_companion/features/connection/fakes/fake_provisioning_repository.dart`
- Modify: `test/bird_companion/features/connection/provisioning_cubit_test.dart`

- [ ] **Step 1: Run the existing connection suite**

Run:

```powershell
$env:GIT_CONFIG_COUNT='2'
$env:GIT_CONFIG_KEY_0='safe.directory'
$env:GIT_CONFIG_VALUE_0='D:/birdphoto/.tooling/flutter-3.44.5'
$env:GIT_CONFIG_KEY_1='safe.directory'
$env:GIT_CONFIG_VALUE_1='D:/birdphoto/bird_thirdtime_fresh_run'
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection
```

Expected: existing connection tests pass before B3/B4 changes.

- [ ] **Step 2: Write a failing fake-safety test**

Add a test to `provisioning_cubit_test.dart` that authorizes pairing and expects the call ledger to contain only `authorizePairing`, never the submitted digits:

```dart
expect(repository.calls, contains('authorizePairing'));
expect(repository.calls.any((call) => call.contains(RegExp(r'\d{6}'))), isFalse);
```

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\provisioning_cubit_test.dart
```

Expected: FAIL because the current fake stores `authorize:<pairing code>`.

- [ ] **Step 4: Add safe B3/B4 fake behavior**

Replace secret-bearing call records and implement configurable command results. The fake must expose safe observation only:

```dart
final class FakeStaConfigObservation {
  const FakeStaConfigObservation({
    required this.provisioningMethod,
    required this.selectionMethod,
    required this.hidden,
    required this.networkKind,
    required this.hasBssid,
    required this.passwordProvided,
  });

  final ProvisioningMethod provisioningMethod;
  final WifiSelectionMethod selectionMethod;
  final bool hidden;
  final StaNetworkKind networkKind;
  final bool hasBssid;
  final bool passwordProvided;
}
```

Add constructor fields for `networkStatus`, command results and command errors. Add `emitEvent(ProvisioningEvent event)` and `emitError(Object error)`. Implement methods with safe records such as `startDirectAp`, `scanWifi`, `setStaConfig`, `startDppProvisioning`, and `cancelNetworkOperation:<operationId>`. `setStaConfig` may store only `FakeStaConfigObservation`; it must not retain the configuration object, SSID or password.

Change authorization recording to:

```dart
calls.add('authorizePairing');
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the same focused command. Expected: all `provisioning_cubit_test.dart` tests pass.

- [ ] **Step 6: Commit the safe fake**

```powershell
git add test/bird_companion/features/connection/fakes/fake_provisioning_repository.dart test/bird_companion/features/connection/provisioning_cubit_test.dart
git commit -m "test(connection): add safe provisioning fake"
```

### Task 2: Build the Direct AP state machine with TDD

**Files:**
- Create: `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`
- Create: `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`

- [ ] **Step 1: Write failing capability and single-command tests**

Tests must establish this API:

```dart
final cubit = NetworkProvisioningCubit(repository);
await cubit.startDirectAp(deviceInfo);

expect(cubit.state.phase, NetworkProvisioningPhase.startingDirectAp);
expect(cubit.state.activeOperationId, 'op-direct');
expect(repository.calls.where((call) => call == 'startDirectAp'), hasLength(1));
```

For `directAp: false`, expect `methodUnavailable`, no operation ID and no repository call.

- [ ] **Step 2: Run and verify RED**

Run:

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection\network_provisioning_cubit_test.dart
```

Expected: compile failure because `NetworkProvisioningCubit` does not exist.

- [ ] **Step 3: Implement minimal Direct AP state and start action**

Create the phase/state types with explicit clear flags:

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
  confirmingNetwork,
  success,
  recovered,
  cancelled,
  failure,
}
```

State fields are limited to trusted device ID, capabilities, phase, active operation ID, operation state, immutable scan networks, safe base URI, recovered mode, safe error and cancellability. Do not add credential, passphrase, DPP URI or configuration fields.

Subscribe once in the constructor:

```dart
NetworkProvisioningCubit(this._repository)
    : super(const NetworkProvisioningState()) {
  _eventSubscription = _repository.events.listen(_onEvent, onError: _onEventError);
}
```

Implement `startDirectAp(ProvisioningDeviceInfo info)` with capability guard, generation increment, one repository call, and late-Future check.

- [ ] **Step 4: Run and verify GREEN**

Expected: capability and start tests pass.

- [ ] **Step 5: Write failing event-filter and terminal-confirmation tests**

Cover:

- wrong device ID ignored;
- wrong operation ID ignored;
- matching `NetworkProgress` updates operation state/cancellability;
- matching `DirectApReady` triggers one `getNetworkStatus()`;
- success requires direct AP mode, `apReady`, matching operation ID and non-null base URI;
- Direct AP event passphrase never appears in state;
- mismatched status enters failure rather than success.

Create events through `ProvisioningEvent.fromJson` with synthetic non-production values. Assertions must inspect phase, IDs and URI only, never secret payload text.

- [ ] **Step 6: Run and verify RED**

Expected: matching events do not yet change state.

- [ ] **Step 7: Implement event filtering and confirmation**

Use this gate before handling events:

```dart
if (event.deviceId != state.trustedDeviceId) return;
final eventOperationId = event.operationId;
if (eventOperationId != null &&
    eventOperationId != state.activeOperationId) {
  return;
}
```

On `DirectApReady`, set `confirmingNetwork` and call a generation-guarded `_confirmTerminalStatus` without copying the payload to state. Confirm exact mode, terminal state, operation ID and non-null base URI.

- [ ] **Step 8: Add stop, recovery and lifecycle tests and implementation**

Test first, then implement:

- `stopDirectAp()` only from confirmed Direct AP success and tracks its new operation ID;
- `NetworkRecovered` becomes recovered, never success;
- `close()` cancels only the event subscription and does not call repository `disconnect` or `dispose`;
- `backToMethodSelection()` increments generation and clears operation/result/error.

- [ ] **Step 9: Run the focused suite and commit**

```powershell
git add lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart test/bird_companion/features/connection/network_provisioning_cubit_test.dart
git commit -m "feat(connection): add Direct AP provisioning state"
```

### Task 3: Add Wi-Fi scan aggregation with TDD

**Files:**
- Modify: `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`
- Modify: `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`

- [ ] **Step 1: Write failing scan capability and start tests**

Establish:

```dart
cubit.openWifiProvisioning(deviceInfo);
await cubit.scanWifi();

expect(cubit.state.phase, NetworkProvisioningPhase.scanningWifi);
expect(cubit.state.activeOperationId, 'op-scan');
expect(repository.calls.where((call) => call == 'scanWifi'), hasLength(1));
```

Test `infrastructureSta: false` and `wifiScan: false` produce method-unavailable state and no call.

- [ ] **Step 2: Run and verify RED**

Expected: Wi-Fi methods are absent.

- [ ] **Step 3: Implement minimal Wi-Fi entry and scan start**

`openWifiProvisioning` stores only trusted device/capability data and enters `choosingWifiMethod`. `scanWifi` clears old batches/results, calls once, and stores the returned operation ID.

- [ ] **Step 4: Write failing multi-batch tests**

Emit batches out of order and assert that no list is shown until every index arrives. Then assert:

- duplicate BSSID keeps the stronger RSSI record;
- supported networks precede unsupported networks;
- each group sorts by RSSI descending, then SSID/BSSID;
- batches emitted outside scanning phase are ignored;
- rescan clears prior results.

- [ ] **Step 5: Run and verify RED**

Expected: scan batches are ignored because aggregation is absent.

- [ ] **Step 6: Implement batch aggregation**

Maintain a private `Map<int, WifiScanBatch>` and expected batch count outside public state. Accept a `WifiScanBatch` only while scanning with an active operation. When complete, deduplicate into an immutable list and enter `choosingWifiNetwork`.

- [ ] **Step 7: Run focused tests and commit**

```powershell
git add lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart test/bird_companion/features/connection/network_provisioning_cubit_test.dart
git commit -m "feat(connection): aggregate BLE Wi-Fi scans"
```

### Task 4: Add STA, DPP, cancellation and safe retry behavior

**Files:**
- Modify: `lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart`
- Modify: `test/bird_companion/features/connection/network_provisioning_cubit_test.dart`

- [ ] **Step 1: Write failing selected/manual STA tests**

Pass a `StaNetworkConfiguration` into `submitStaConfiguration`. Assert only safe fake metadata:

```dart
expect(repository.lastStaObservation?.selectionMethod, WifiSelectionMethod.manual);
expect(repository.lastStaObservation?.passwordProvided, isTrue);
expect(cubit.state.phase, NetworkProvisioningPhase.configuringSta);
expect(cubit.state.activeOperationId, 'op-sta');
```

Assert the Cubit state API has no configuration/password field and configuration errors return to an actionable failure without retaining credentials.

- [ ] **Step 2: Run and verify RED, then implement minimal submission**

Guard manual versus scan capability, increment generation, call `setStaConfig()` once and never assign the configuration to state or a Cubit field.

- [ ] **Step 3: Write failing STA terminal confirmation tests**

Matching `StaConnected` must trigger `getNetworkStatus()` and succeed only for infrastructure STA, `staConnected`, matching operation ID and non-null base URI. Wrong device/operation and mismatched status remain non-success.

- [ ] **Step 4: Run RED, implement confirmation and verify GREEN**

Reuse the Direct AP confirmation helper with an expected mode/state pair.

- [ ] **Step 5: Write failing DPP tests**

Cover unavailable box capability, one `startDppProvisioning()` call, matching `DppBootstrapReady` updating only safe progress, and no DPP URI field in state.

- [ ] **Step 6: Run RED, implement DPP and verify GREEN**

The Cubit must not call platform interfaces. It only tracks the repository operation and waits for STA terminal confirmation.

- [ ] **Step 7: Write failing cancellation and late-result tests**

Cover:

- cancellation unavailable during non-cancellable states;
- scan/DPP cancellation calls `cancelNetworkOperation(activeOperationId)` once;
- matching cancelled event returns to a safe cancelled state;
- a Future completing after back/reset cannot overwrite the current state;
- event stream errors map to failure without raw diagnostic state.

- [ ] **Step 8: Implement cancellation/generation guards and commit**

```powershell
git add lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart test/bird_companion/features/connection/network_provisioning_cubit_test.dart
git commit -m "feat(connection): add STA and DPP provisioning state"
```

### Task 5: Build capability-aware pages and credential-owning form

**Files:**
- Create: `lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart`
- Create: `lib/bird_companion/features/connection/presentation/widgets/sta_network_form.dart`
- Modify: `lib/bird_companion/features/connection/presentation/pages/connection_method_page.dart`
- Modify: `lib/bird_companion/features/connection/presentation/widgets/provisioning_method_card.dart`
- Create: `test/bird_companion/features/connection/network_provisioning_page_test.dart`

- [ ] **Step 1: Write failing method-card capability widget tests**

Pump `ConnectionMethodPage` with Device Info capabilities. Assert unsupported cards show `此盒子不支持` and cannot invoke the callback; supported cards remain tappable.

- [ ] **Step 2: Run RED, implement optional tap and disabled reason, verify GREEN**

Change the card contract to:

```dart
final VoidCallback? onTap;
final String? disabledReason;
```

Render muted color/lock icon and disabled reason when `onTap == null`. Pass capabilities into `ConnectionMethodPage` and disable each method independently.

- [ ] **Step 3: Write failing STA form validation tests**

Cover:

- blank SSID rejected;
- protected security requires a non-empty password;
- open network submits without password;
- manual mode uses null BSSID and `bleManual`;
- selected mode uses scan BSSID and `bleScanSelection`;
- password field is obscured;
- successful submit clears the password controller.

- [ ] **Step 4: Run RED and implement `StaNetworkForm`**

The widget owns and disposes its controllers. Its callback accepts a one-shot `StaNetworkConfiguration`. It must never display the configuration with `toString()` or retain it after callback completion.

- [ ] **Step 5: Write failing network-page phase tests**

Pump `NetworkProvisioningPage` with a real Cubit and fake repository. Cover Direct AP progress/success/recovered, Wi-Fi method choices, scan results with unsupported entries, DPP gating, cancellable versus non-cancellable progress, safe errors and completion callback only after confirmation.

- [ ] **Step 6: Run RED and implement the page router**

Use existing `ConnectionBackground`, `BirdCard`, `BirdButton`, `BirdListItem`, `ErrorNotice`, colors and spacing. Map every operation state to fixed safe Chinese text. Do not interpolate raw errors, AP passphrase, DPP payload, configuration or diagnostic text.

- [ ] **Step 7: Run widget tests and commit**

```powershell
git add lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart lib/bird_companion/features/connection/presentation/widgets/sta_network_form.dart lib/bird_companion/features/connection/presentation/pages/connection_method_page.dart lib/bird_companion/features/connection/presentation/widgets/provisioning_method_card.dart test/bird_companion/features/connection/network_provisioning_page_test.dart
git commit -m "feat(connection): add B3 B4 provisioning pages"
```

### Task 6: Integrate B3/B4 into the BLE connection page

**Files:**
- Modify: `lib/bird_companion/features/connection/presentation/connection_page.dart`
- Modify: `test/bird_companion/features/connection/ble_connection_page_test.dart`

- [ ] **Step 1: Write a failing post-pairing navigation test**

Drive the existing BLE page through device selection, pairing and method choice. Assert selecting Direct AP calls `startDirectAp` and renders the B3 progress page. Add a parallel existing-Wi-Fi test that renders B4 choices without issuing a network-changing command yet.

- [ ] **Step 2: Run RED**

Expected: the current `onSelected ?? (_) {}` discards the choice.

- [ ] **Step 3: Provide both Cubits for BLE mode**

Use `MultiBlocProvider`:

```dart
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => ProvisioningCubit(provisioning)..discover()),
    BlocProvider(create: (_) => NetworkProvisioningCubit(provisioning)),
  ],
  child: _BleConnectionView(
    onMethodSelected: onProvisioningMethodSelected,
    onProvisioningCompleted: onProvisioningCompleted,
  ),
)
```

Add an optional `ValueChanged<Uri>? onProvisioningCompleted` to `ConnectionPage`. Do not wire `BirdCompanionDependencies` in this batch.

- [ ] **Step 4: Route the method choice**

When B1/B2 is at `methodSelection` and the network Cubit is idle, show capability-aware `ConnectionMethodPage`. On Direct AP, notify the optional existing selection callback and call `startDirectAp(deviceInfo)`. On existing Wi-Fi, notify the callback and call `openWifiProvisioning(deviceInfo)`. Once network state is active, render `NetworkProvisioningPage`.

- [ ] **Step 5: Test back/reset semantics**

Returning from B3/B4 calls `backToMethodSelection()` and reveals the B1/B2 method page without disconnecting or re-authorizing. Closing the whole `ConnectionPage` retains the existing `ProvisioningCubit` disconnect behavior.

- [ ] **Step 6: Run focused tests and commit**

```powershell
git add lib/bird_companion/features/connection/presentation/connection_page.dart test/bird_companion/features/connection/ble_connection_page_test.dart
git commit -m "feat(connection): connect pairing to B3 B4 flows"
```

### Task 7: Security audit and complete verification

**Files:**
- Verify all files listed above.
- Modify only failing Member B presentation/test files if verification exposes a defect.

- [ ] **Step 1: Scan the diff boundary**

Run:

```powershell
git diff origin/thirdtime~0 --name-only
git status --short
```

Manually confirm there are no changes under Android, BLE data, platform, domain or app dependencies.

- [ ] **Step 2: Scan for secret-bearing state/logging**

Run targeted searches over changed Member B files for `password`, `passphrase`, `dppUri`, `pairingCode`, `diagnosticMessage`, `print(`, `debugPrint(` and logging calls. Every occurrence must be either an ephemeral form parameter/controller, a domain payload that is immediately ignored, or an explicit negative security test. State classes and fake ledgers must contain none of these values.

- [ ] **Step 3: Format check**

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' format --output=none --set-exit-if-changed lib\bird_companion\features\connection\presentation test\bird_companion\features\connection
```

Expected: exit 0 and no formatting changes required.

- [ ] **Step 4: Run all connection tests**

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat' test --no-pub test\bird_companion\features\connection
```

Expected: all connection tests pass.

- [ ] **Step 5: Run targeted analysis**

```powershell
& 'D:\birdphoto\.tooling\flutter-3.44.5\bin\dart.bat' analyze lib\bird_companion\features\connection\presentation test\bird_companion\features\connection
```

Expected: `No issues found` with exit 0. A sandbox telemetry write warning may be reported separately but does not replace the analyzer exit code.

- [ ] **Step 6: Run Git integrity checks**

```powershell
git diff --check
git status --short --branch
git diff --name-only origin/thirdtime
```

Expected: no whitespace errors and only authorized Member B docs/presentation/test files.

- [ ] **Step 7: Commit any verification-only corrections**

If formatting or verification required Member B corrections, commit them as:

```powershell
git add lib/bird_companion/features/connection/presentation test/bird_companion/features/connection
git commit -m "test(connection): verify B3 B4 provisioning flows"
```

- [ ] **Step 8: Report unresolved production boundaries**

The completion report must state that production repository injection, Android Wi-Fi/DPP, `/health.device_id`, real-box behavior and device smoke tests remain unverified Member A dependencies. Do not label them failed or passed.
