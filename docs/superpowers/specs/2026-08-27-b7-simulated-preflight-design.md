# B7 Simulated Preflight Design

**Goal:** Add a repeatable RC4 simulated acceptance path for B7 while preserving the real-device Release gate.

**Scope:** The change covers a Dart acceptance command, a blank real-device evidence template, focused flow/page/acceptance tests, and Preflight evidence metadata. It does not change production dependency injection, frozen RC4 contracts, or Release requirements.

## Architecture

The acceptance command reuses the existing MockBoxServer and test-only Fake BLE/Wi-Fi/DPP adapters. It runs ten SIM cases from the A7 handoff, records each result, and emits a report whose top-level metadata is always `environment=simulated`, `releasable=false`, and `real_k7_status=pending`. Synthetic identifiers and data are used; no pairing code, password, token, DPP URI, or real MAC is persisted.

`run_b7_gate.ps1 -Mode Preflight` remains usable without real-box evidence. It invokes production-integrity checks and the simulated acceptance path, then writes those simulation metadata fields into the B7 evidence file. `Release` continues to require real-box evidence, a release signature, and B12-B evidence; simulated evidence cannot satisfy it.

## Testing

Acceptance tests assert all ten SIM case IDs, successful report status, simulation metadata, and sensitive-data exclusion. Page/flow tests continue to use Fake repositories only. Script-level tests assert that Preflight carries simulated metadata while Release still requires `-RealBoxEvidencePath` and rejects simulated evidence.

## Completion boundary

The simulated B7 preflight may be marked passed after the focused tests, analyzer, contract checks, and Preflight command pass. Real K7 acceptance, Release approval, and S4 closure remain `real_pending` until real hardware evidence is supplied.
