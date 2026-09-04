import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Preflight invokes simulated RC4 acceptance and records fail-closed metadata', () {
    final source = File('tool/release/run_b7_gate.ps1').readAsStringSync();
    expect(source, contains('simulated RC4 acceptance'));
    expect(source, contains('tool/acceptance/ble_provisioning_rc4_acceptance.dart'));
    expect(source, contains('environment = "simulated"'));
    expect(source, contains(r'releasable = $false'));
    expect(source, contains('real_k7_status = "pending"'));
    expect(source, contains(r'if ($Mode -eq "Preflight")'));
  });

  test('Release retains real evidence requirements and cannot use simulated acceptance', () {
    final source = File('tool/release/run_b7_gate.ps1').readAsStringSync();
    expect(source, contains(r'[string]$RealBoxEvidencePath'));
    expect(source, contains('Release mode requires -RealBoxEvidencePath.'));
    expect(source, contains(r'[string]$BleRc4EvidencePath'));
    expect(source, contains('Release mode requires -BleRc4EvidencePath.'));
    expect(source, contains(r'[string]$B12BEvidencePath'));
    expect(source, contains('Release mode requires -B12BEvidencePath.'));
    expect(source, contains('BLE RC4 K7 real-hardware evidence'));
    expect(
      source,
      contains('tool/acceptance/ble_provisioning_rc4_real_device_gate.dart'),
    );
    expect(source, contains(r'$script:bleRc4Verified = $true'));
    expect(
      source,
      contains(
        r'elseif ($Mode -eq "Release" -and $status -eq "passed" -and $script:bleRc4Verified)',
      ),
    );
    expect(source, contains('environment = "real_k7"'));
    expect(source, contains('real_k7_status = "verified"'));
  });

  test('Preflight tolerates simulated runner diagnostics on stderr', () {
    final source = File('tool/release/run_b7_gate.ps1').readAsStringSync();
    expect(source, contains(r'$runnerErrorActionPreference = $ErrorActionPreference'));
    expect(source, contains(r'$ErrorActionPreference = "Continue"'));
    expect(source, contains(r'$ErrorActionPreference = $runnerErrorActionPreference'));
  });
}
