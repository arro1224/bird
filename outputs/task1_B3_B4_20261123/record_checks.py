"""Record this batch's local evidence without modifying Git or source files."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def result(name):
    lines = (OUT / name).read_text(encoding='utf-8-sig').splitlines()
    terminal = lines[-1]
    match = re.search(r'\+(\d+)(?: ~(\d+))?: All tests passed!', terminal)
    assert match, (name, terminal)
    return {'passed': int(match[1]), 'skipped': int(match[2] or 0), 'failed': 0, 'log': name}


assert git('rev-parse', 'HEAD') == '28aeae2a0ba5edf4c19dca584117345d26762e05'
assert git('branch', '--show-current') == 'thirdtime'
assert not git('diff', '--cached', '--name-only'), 'Do not stage the user work.'

# These are intentional continuations of B0/B1/B2 files. Other prior artifacts
# must remain byte-for-byte identical to the manifest taken before the reset.
expected = {
    'doc/任务/任务一_实施方案_2026-11-23.md',
    'doc/任务/任务一_实施任务批次_2026-11-23.md',
    'lib/bird_companion/app/app_dependencies.dart',
    'lib/bird_companion/core/session/device_session_cubit.dart',
    'lib/bird_companion/features/connection/data/direct_ap_pending_store.dart',
    'lib/bird_companion/features/connection/data/provisioning_repository_impl.dart',
    'lib/bird_companion/features/connection/domain/connection_attempt.dart',
    'lib/bird_companion/features/connection/domain/provisioning_repository.dart',
    'lib/bird_companion/features/connection/presentation/network_provisioning_cubit.dart',
    'test/bird_companion/features/connection/provisioning_repository_a3_a4_test.dart',
}
prior = json.loads((ROOT / '.codex-tmp/task1_reset_manifest.json').read_text(encoding='utf-8-sig'))
preserved, continued = [], []
for name, original in prior:
    path = ROOT / name
    assert path.is_file(), f'Missing earlier work: {name}'
    if digest(path) == original:
        preserved.append(name)
    else:
        assert name in expected, f'Unexpected change to earlier work: {name}'
        continued.append(name)

protected = [
    'android/app/src/main/AndroidManifest.xml',
    'android/app/src/bird/AndroidManifest.xml',
    'lib/bird_companion/features/connection/data/platform/phone_wifi_platform.dart',
    'lib/bird_companion/features/connection/presentation/pages/connection_method_page.dart',
    'lib/bird_companion/features/connection/presentation/pages/wifi_qr_scanner_page.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_parser.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_import.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_credentials.dart',
    'tool/release/verify_production_integrity.dart',
]
for name in protected:
    assert (ROOT / name).is_file(), name
    subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', name], cwd=ROOT, check=True)
write('preservation.json', {'prior_files': len(prior), 'byte_identical': preserved,
    'intentionally_continued': continued, 'protected_task2_paths_unchanged_from_HEAD': protected})

for name, text in [('analyze_final.txt', 'No issues found!'),
                   ('production_integrity.txt', 'PASS production integrity'),
                   ('contracts.txt', 'PASS birdbox-v1@1.0.0')]:
    assert text in (OUT / name).read_text(encoding='utf-8-sig'), name
checks = {'date': '2026-11-23', 'branch': git('branch', '--show-current'), 'head': git('rev-parse', 'HEAD'),
    'index_empty': True, 'committed_by_agent': False,
    'full_suite': result('full_suite.txt'), 'final_connection': result('connection_final.txt'),
    'final_owner': result('owner_final.txt'), 'analyze': 'passed', 'production_integrity': 'passed', 'contracts': 'passed',
    'coverage_note': 'Full suite ran before the last stop-resume case and small owner/event guards; final connection and owner reruns cover those changes. Counts are not additive.',
    'device_tests': 'not run; adb lists no devices', 'apk': 'not built',
    'prior_preserved_files': len(preserved), 'prior_intentionally_continued_files': len(continued)}
write('checks.json', checks)

names = git('-c', 'core.quotePath=false', 'ls-files', '--cached', '--others', '--exclude-standard').splitlines()
selected = [name for name in names if name.startswith(('lib/', 'test/', 'integration_test/', 'android/app/src/', 'doc/任务/任务一'))]
write('source_manifest.json', {'head': checks['head'], 'branch': checks['branch'], 'state': 'unstaged working tree',
    'sha256': {name: digest(ROOT / name) for name in sorted(selected) if (ROOT / name).is_file()}})
print(json.dumps(checks, ensure_ascii=False, indent=2))
