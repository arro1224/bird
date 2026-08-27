# B7 Simulated Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a repeatable B7 simulated RC4 acceptance/preflight path without weakening the real K7 Release gate.

**Architecture:** Add a focused Dart acceptance runner that executes ten simulation cases against test-only Fake adapters and emits explicit simulated metadata. Extend the existing PowerShell Preflight orchestration and evidence JSON while leaving Release validation strict. Add a blank real-device evidence template and tests that prove simulation cannot be used as release evidence.

**Tech Stack:** Dart 3.12, Flutter test, existing `MockBoxServer`, Fake BLE/Wi-Fi/DPP adapters, PowerShell, JSON fixtures.

---

### Task 1: Define the RC4 simulated acceptance report contract

**Files:**
- Create: `tool/acceptance/ble_provisioning_rc4_acceptance.dart`
- Test: `test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart`

- [ ] **Step 1: Write the failing report-shape test**

Assert that the runner returns `result=pass`, `environment=simulated`, `releasable=false`, `real_k7_status=pending`, exactly ten case IDs (`SIM-01` through `SIM-10`), and no sensitive values in serialized JSON.

- [ ] **Step 2: Run the focused test and confirm it fails because the runner is absent**

Run: `flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart`

Expected: compilation failure for the missing `ble_provisioning_rc4_acceptance.dart` import/function.

- [ ] **Step 3: Implement the minimal immutable report and command entrypoint**

Define `runBleProvisioningRc4Acceptance()` and a report with `toJson()` fields for simulation metadata and case results. Parse optional `--base-url`, defaulting to the synthetic MockBoxServer URL, and return non-zero from `main` on any failed case.

- [ ] **Step 4: Run the report test and verify the metadata assertions pass**

Run: `flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart`

Expected: PASS for report metadata and secret exclusion.

- [ ] **Step 5: Commit the report contract**

```powershell
git add tool/acceptance/ble_provisioning_rc4_acceptance.dart test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart
git commit -m "test(batch-4/B-preflight): add simulated rc4 acceptance report"
```

### Task 2: Cover the ten simulated RC4 cases with Fake adapters

**Files:**
- Modify: `tool/acceptance/ble_provisioning_rc4_acceptance.dart`
- Test: `test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart`
- Test: `test/bird_companion/features/connection/network_provisioning_page_test.dart`

- [ ] **Step 1: Add failing case assertions for discovery, pairing, network transitions, DPP, recovery, and safety**

Use `FakeBirdBoxBleDataSource`, `FakeBirdBoxWifiPlatform`, and `FakeBirdBoxDppPlatform` to assert the case matrix: compact/full advertisements, transient pairing, Direct AP and STA paths, dynamic `base_uri`, all DPP outcomes, stale/late event handling, and secret-free logs.

- [ ] **Step 2: Run the focused flow/page tests and confirm each missing behavior fails**

Run: `flutter test --no-pub test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart test/bird_companion/features/connection/network_provisioning_page_test.dart`

Expected: failures identify the unimplemented simulated assertions or report case plumbing.

- [ ] **Step 3: Implement each case as a bounded runner function**

Keep production imports out of the simulation switch. Each case returns a structured pass/fail result and only uses synthetic IDs/data. Do not add a fake-provider branch to `lib/main.dart`, production flavors, or `app_dependencies.dart`.

- [ ] **Step 4: Run the case tests until all ten cases pass**

Run: `flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart test/bird_companion/features/connection/network_provisioning_page_test.dart`

Expected: all focused tests pass and the report lists every case exactly once.

- [ ] **Step 5: Commit the simulated case coverage**

```powershell
git add tool/acceptance/ble_provisioning_rc4_acceptance.dart test/bird_companion/features/connection/ble_provisioning_simulated_flow_test.dart test/bird_companion/features/connection/network_provisioning_page_test.dart
git commit -m "test(batch-4/B-preflight): cover simulated rc4 provisioning flows"
```

### Task 3: Add the real-device evidence template and acceptance gate tests

**Files:**
- Create: `docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json`
- Create: `test/bird_companion/acceptance/ble_provisioning_evidence_template_test.dart`
- Modify: `tool/acceptance/ble_provisioning_rc4_acceptance.dart`

- [ ] **Step 1: Write the failing template test**

Assert the template is blank/pending, contains the required real-device metadata and all RC4 acceptance case IDs, and contains no simulated pass values or secrets.

- [ ] **Step 2: Run the template test and confirm the file is missing**

Run: `flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_evidence_template_test.dart`

Expected: failure because the template does not exist.

- [ ] **Step 3: Add the pending real-device template**

Use explicit `REQUIRED_*` placeholders, `environment.real_hardware=false`, `final_result=pending`, empty evidence arrays, and `real_k7_status=pending`; include the ten SIM/RC4 IDs without marking any case passed.

- [ ] **Step 4: Run the template test and verify fail-closed shape**

Run: `flutter test --no-pub test/bird_companion/acceptance/ble_provisioning_evidence_template_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the template and tests**

```powershell
git add docs/acceptance/ble-provisioning-rc4-real-device-evidence.template.json test/bird_companion/acceptance/ble_provisioning_evidence_template_test.dart
git commit -m "docs(batch-4/B-preflight): add rc4 real-device evidence template"
```

### Task 4: Integrate simulated acceptance into B7 Preflight only

**Files:**
- Modify: `tool/release/run_b7_gate.ps1`
- Modify: `tool/release/README.md`
- Test: `test/bird_companion/acceptance/b7_preflight_gate_test.dart`

- [ ] **Step 1: Add failing script-source and evidence assertions**

Assert that Preflight invokes the RC4 simulated runner and writes `environment=simulated`, `releasable=false`, and `real_k7_status=pending`; assert Release still requires `-RealBoxEvidencePath` and rejects simulated evidence.

- [ ] **Step 2: Run the script-source test and confirm the integration is absent**

Run: `flutter test --no-pub test/bird_companion/acceptance/b7_preflight_gate_test.dart`

Expected: failure on the missing Preflight command/metadata.

- [ ] **Step 3: Implement the Preflight-only gate step and evidence fields**

Invoke `dart run tool/acceptance/ble_provisioning_rc4_acceptance.dart` in Preflight, capture its JSON/report path, and add explicit simulation metadata to the generated B7 evidence. Keep all real-box, signing, and B12-B checks under the existing Release branch.

- [ ] **Step 4: Run focused gate tests and a real Preflight**

Run: `flutter test --no-pub test/bird_companion/acceptance/b7_preflight_gate_test.dart test/bird_companion/acceptance/ble_provisioning_rc4_acceptance_test.dart`

Then run: `powershell -ExecutionPolicy Bypass -File tool/release/run_b7_gate.ps1 -Mode Preflight -FlutterCommand D:\birdphoto\.tooling\flutter-3.44.5\bin\flutter.bat -DartCommand dart`

Expected: focused tests pass; Preflight either passes with explicit simulated metadata or reports only an environment/tooling prerequisite, never a Release pass.

- [ ] **Step 5: Commit the Preflight integration**

```powershell
git add tool/release/run_b7_gate.ps1 tool/release/README.md test/bird_companion/acceptance/b7_preflight_gate_test.dart
git commit -m "feat(batch-4/B-preflight): run simulated rc4 acceptance in Preflight"
```

### Task 5: Full verification and handoff

**Files:**
- Modify: `docs/implementation/BLE-RC4-APP-ACCEPTANCE-2026-08-18.md`

- [ ] **Step 1: Record simulated-passed and real-pending status**

Document the ten simulated cases as simulated-only and state that real K7, Release, and S4 remain `real_pending`.

- [ ] **Step 2: Run the focused B7 and contract verification**

Run: `flutter test --no-pub test/bird_companion/acceptance test/bird_companion/features/connection test/contracts`

Expected: all selected tests pass.

- [ ] **Step 3: Run analyzer and contract verifier**

Run: `flutter analyze --no-pub`; then `dart run tool/contracts/verify_contracts.dart`.

Expected: `No issues found` and contract verification pass with frozen SHA unchanged.

- [ ] **Step 4: Run `git diff --check` and inspect production integrity**

Run: `git diff --check`; then `dart run tool/release/verify_production_integrity.dart`.

Expected: no whitespace errors and production integrity pass.

- [ ] **Step 5: Commit documentation and report exact evidence**

```powershell
git add docs/implementation/BLE-RC4-APP-ACCEPTANCE-2026-08-18.md
git commit -m "docs(batch-4/B-preflight): record simulated rc4 acceptance status"
```

