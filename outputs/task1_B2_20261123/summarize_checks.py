"""Summarize completed checks and fingerprint the B2 working source."""
import collections
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

OUT = Path('outputs/task1_B2_20261123')


def test_summary(name):
    events = []
    for line in (OUT / name).read_text(encoding='utf-8-sig').splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            pass
    tests = {e['test']['id']: e['test'] for e in events if e.get('type') == 'testStart'}
    ends = [e for e in events if e.get('type') == 'testDone' and not e.get('hidden')]
    counts = collections.Counter('skipped' if e.get('skipped') else e.get('result') for e in ends)
    done = [e for e in events if e.get('type') == 'done']
    assert done, 'Test run still in progress: ' + name
    return {'artifact': name, 'counts': dict(counts), 'done': done[-1],
            'skipped_cases': [tests[e['testID']] for e in ends if e.get('skipped')],
            'errors': [{'test': tests.get(e['testID'], {}), 'error': e['error']}
                       for e in events if e.get('type') == 'error']}


checks = {'source_parent_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD']).decode().strip(),
          'full_suite_90_seconds': test_summary('verified_test_events.jsonl'),
          'final_connection_regression': test_summary('final_connection_events.jsonl'),
          'earlier_default_timeout_runs': [test_summary('full_test_events.jsonl'), test_summary('full_test_final_events.jsonl')],
          'full_suite_command': 'flutter test --no-pub --reporter json --timeout 90s --concurrency 2',
          'scope_note': 'Full suite followed by final connection/settings/route regression after cancellation/intent guards. Only the test runner timeout changed; business timeouts and assertions did not.',
          'real_device_wifi_acceptance': 'pending', 'instrumentation_execution': 'not_run', 'delivery_apk_built': False}
for name in ['analyze_final', 'production_integrity', 'contracts', 'android_final']:
    checks[name] = {'exit_code': int((OUT / (name + '_exit.txt')).read_text(encoding='utf-8-sig').strip())}
native = [ET.parse(p).getroot() for p in Path('build/app/test-results/testBirdDebugUnitTest').glob('*.xml')]
checks['android_unit_tests'] = {key: sum(int(r.get(key, '0')) for r in native) for key in ['tests', 'failures', 'errors', 'skipped']}
checks['android_instrumentation_compile'] = {'exit_code': checks['android_final']['exit_code'],
                                          'executed_on_device': False}
protected = [
    'android/app/src/main/AndroidManifest.xml',
    'lib/bird_companion/features/connection/data/platform/phone_wifi_platform.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_import.dart',
    'lib/bird_companion/features/connection/presentation/pages/network_provisioning_page.dart',
    'lib/bird_companion/features/connection/presentation/pages/wifi_qr_scanner_page.dart',
    'lib/bird_companion/features/connection/presentation/widgets/sta_network_form.dart',
    'tool/release/verify_production_integrity.dart', 'integration_test/task2_provisioning_test.dart',
    'integration_test/task2_qr_fixtures.dart']
preserved = subprocess.run(['git', 'diff', '--quiet', '28aeae2a0', '--', *protected]).returncode == 0
checks['task2_preservation'] = {'unchanged': preserved, 'paths': protected}

changed = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD', '--', 'lib', 'android', 'test'], encoding='utf-8').splitlines()
untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', 'lib', 'android', 'test'], encoding='utf-8').splitlines()
checks['source_files'] = [{'path': p, 'sha256': hashlib.sha256(Path(p).read_bytes()).hexdigest()} for p in sorted(set(changed + untracked))]
(OUT / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
assert checks['full_suite_90_seconds']['done']['success']
assert checks['final_connection_regression']['done']['success']
assert all(checks[n]['exit_code'] == 0 for n in ['analyze_final', 'production_integrity', 'contracts', 'android_final'])
assert checks['android_unit_tests']['failures'] == checks['android_unit_tests']['errors'] == 0
assert preserved
print(json.dumps({k: checks[k] for k in ['android_unit_tests', 'task2_preservation']}, ensure_ascii=False))
print('Full suite:', checks['full_suite_90_seconds']['counts'])
print('Final connection:', checks['final_connection_regression']['counts'])
