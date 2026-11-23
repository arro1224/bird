"""Extract only actual test outcomes from the retained verbose device run."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'build/task1_B7_20261123_01/private'
OUT = ROOT / 'outputs/task1_B7_20261123_01'

log = (PRIVATE / 'device_integration_retry.log').read_text(encoding='utf-8-sig')
assert re.search(r'\+9: All tests passed!', log)
assert 'exiting with code 0' in log
assert '00:12 +4:' in log
safe_lines = [line for line in log.splitlines() if re.match(r'^\d\d:\d\d \+', line)
              or line.startswith('TASK2_') or 'test package returned with exit code' in line]
(OUT / 'device_integration_final.log').write_text('\n'.join(safe_lines) + '\n', encoding='utf-8')
initial = (PRIVATE / 'device_integration.log').read_text(encoding='utf-8-sig')
initial_safe = [line for line in initial.splitlines() if re.match(r'^\d\d:\d\d \+', line)]
(OUT / 'device_integration_initial.log').write_text('\n'.join(initial_safe) +
    '\nOperator interrupted after second test stopped progressing while paused; not a successful run.\n', encoding='utf-8')
result = {'client': 'vivo X20 / Android8.1.0 / API27', 'exit_code': 0,
    'passed': 9, 'failed': 0, 'task1': {'passed': 4, 'transport': 'simulated BLE/repository with real widgets'},
    'task2': {'passed': 5, 'ssid_observed': 'permissionDenied', 'ssid_result': 'explicit fallback explanation; actual SSID prefill not proven',
              'single_qr_decode': True, 'double_qr_rejected': True, 'gallery_cancel_safe': True,
              'simulated_first_join_commands': 1, 'box_transport': 'simulated repository'},
    'normal_B6_candidate': False, 'final_log': 'device_integration_final.log',
    'initial_attempt': {'status': 'interrupted', 'passed_before_interruption': 1,
                        'reason': 'paused binding cannot pumpAndSettle until resumed',
                        'log': 'device_integration_initial.log'},
    'test_harness_fix': 'tester.idle while paused; pumpAndSettle only after resumed; shared host 4 passed',
    'runner_cleanup': {'automatic_same_package_uninstalls_observed_in_final_log': log.count(' uninstall deckers.thibault.aves.bird'),
        'app_local_state_cleared': True, 'full_data_backup_available': False,
        'restoration': 'normal B6 APK reinstalled separately; cannot claim all prior preferences/credentials restored'},
    'acceptance_scope': 'on-device widgets/platform decoding only; not real board AP or prescribed client matrix'}
(OUT / 'integration_results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'passed': 9, 'failed': 0, 'ssid': result['task2']['ssid_result']}))
