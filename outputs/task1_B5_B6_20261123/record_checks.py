"""Collect B5/B6 evidence; never stages files or changes Git history."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
DELIVERY = ROOT / 'build/delivery/task1_B6_20261123_01'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def test_result(name):
    terminal = (OUT / name).read_text(encoding='utf-8-sig').splitlines()[-1]
    match = re.search(r'\+(\d+)(?: ~(\d+))?: All tests passed!', terminal)
    assert match, (name, terminal)
    return {'passed': int(match[1]), 'skipped': int(match[2] or 0), 'failed': 0, 'log': name}


assert git('branch', '--show-current') == 'thirdtime'
assert git('rev-parse', 'HEAD') == '28aeae2a0ba5edf4c19dca584117345d26762e05'
assert not git('diff', '--cached', '--name-only')
expected_changes = {
    'lib/bird_companion/features/connection/domain/provisioning_repository.dart',
    'lib/bird_companion/features/connection/data/provisioning_repository_impl.dart',
    'lib/bird_companion/features/connection/presentation/provisioning_cubit.dart',
    'lib/bird_companion/features/connection/presentation/connection_page.dart',
    'lib/bird_companion/features/connection/presentation/widgets/discovered_device_card.dart',
    'test/bird_companion/features/connection/provisioning_repository_a3_a4_test.dart',
    'doc/任务/任务一_实施方案_2026-11-23.md',
    'doc/任务/任务一_实施任务批次_2026-11-23.md',
}
prior = json.loads((OUT / 'start_manifest.json').read_text(encoding='utf-8-sig'))
unchanged, continued = [], []
for name, before in prior.items():
    path = ROOT / name
    assert path.is_file(), f'Missing earlier work: {name}'
    if sha(path) == before:
        unchanged.append(name)
    else:
        assert name in expected_changes, f'Unexpected earlier-file change: {name}'
        continued.append(name)
protected = [
    'android/app/src/main/AndroidManifest.xml', 'android/app/src/bird/AndroidManifest.xml',
    'lib/bird_companion/features/connection/data/platform/phone_wifi_platform.dart',
    'lib/bird_companion/features/connection/presentation/pages/connection_method_page.dart',
    'lib/bird_companion/features/connection/presentation/pages/wifi_qr_scanner_page.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_parser.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_import.dart',
    'lib/bird_companion/features/connection/domain/wifi_qr_credentials.dart',
    'tool/release/verify_production_integrity.dart', 'tool/release/build_android_apks.ps1',
    'integration_test/task2_provisioning_test.dart',
]
for name in protected:
    assert (ROOT / name).is_file(), name
    subprocess.run(['git', 'diff', '--quiet', 'HEAD', '--', name], cwd=ROOT, check=True)
write('preservation.json', {'starting_files': len(prior), 'byte_identical_count': len(unchanged),
    'byte_identical': unchanged, 'intentionally_continued': continued, 'protected_unchanged_from_HEAD': protected})

suites = list((ROOT / 'build/app/test-results/testBirdDebugUnitTest').glob('TEST-*.xml'))
unit = {'tests': 0, 'failures': 0, 'errors': 0, 'skipped': 0, 'xml_files': len(suites)}
for path in suites:
    suite = ET.parse(path).getroot()
    for key in ['tests', 'failures', 'errors', 'skipped']:
        unit[key] += int(suite.get(key, '0'))
assert unit['tests'] and not (unit['failures'] or unit['errors'])
assert 'BUILD SUCCESSFUL' in (OUT / 'android_checks.txt').read_text(encoding='utf-8-sig')
write('android_unit_summary.json', unit)
for name, marker in [('analyze_final.txt', 'No issues found!'),
                     ('production_integrity.txt', 'PASS production integrity'),
                     ('contracts.txt', 'PASS birdbox-v1@1.0.0')]:
    assert marker in (OUT / name).read_text(encoding='utf-8-sig'), name

if '--prebuild' in sys.argv:
    print(f'Prebuild preserved {len(unchanged)} earlier files; intentional continuations: {len(continued)}; native tests: {unit["tests"]}.')
    raise SystemExit(0)

manifest = json.loads((DELIVERY / 'build-manifest.json').read_text(encoding='utf-8-sig'))
assert manifest['mode'] == 'Normal' and manifest['releasable'] is False
assert manifest['source']['git_sha'] == git('rev-parse', 'HEAD')
assert manifest['source']['working_tree_clean'] is False and manifest['source']['build_dirty'] is True
artifact = manifest['artifacts'][0]
assert artifact['flavor'] == 'bird' and artifact['build_type'] == 'debug' and artifact['target'] == 'lib/main.dart'
assert artifact['package_id'] == 'deckers.thibault.aves.bird'
apk = DELIVERY / artifact['file']
assert sha(apk) == artifact['sha256']
fingerprint = hashlib.sha256((DELIVERY / 'source-files.sha256').read_bytes()).hexdigest()
assert fingerprint == manifest['source']['source_fingerprint']
assert 'build_complete' in (OUT / 'build_01.txt').read_text(encoding='utf-8-sig')
metadata = (OUT / 'apk_metadata.txt').read_text(encoding='utf-8-sig')
assert "package: name='deckers.thibault.aves.bird'" in metadata
assert "versionCode='176'" in metadata and "versionName='1.14.11'" in metadata

# Verify the exact application inputs still match. Reports may be finalized
# after packaging, but no compiled Dart/native/assets/build configuration may drift.
compiled_paths = []
for line in (DELIVERY / 'source-files.sha256').read_text(encoding='utf-8-sig').splitlines():
    name, expected = line.split('\t')
    if name.startswith(('lib/', 'android/', 'assets/')) or name in ['pubspec.yaml', 'pubspec.lock']:
        assert expected == sha(ROOT / name), f'Compiled input drifted: {name}'
        compiled_paths.append(name)

checks = {'date': '2026-11-23', 'branch': 'thirdtime', 'head': git('rev-parse', 'HEAD'),
    'index_empty': True, 'committed_by_agent': False,
    'full_suite': test_result('full_suite_final.txt'), 'native_unit': unit,
    'static_analysis': 'passed', 'production_integrity': 'passed', 'contracts': 'passed',
    'android_instrumentation_compilation': 'passed', 'android_device_tests': 'not run; adb lists no devices',
    'task1_shared_ui_scenarios': 'host run; Android entry added, device execution pending',
    'task2_device_integration': 'not run; host regressions included in full suite',
    'candidate_directory': DELIVERY.relative_to(ROOT).as_posix(), 'artifact': artifact,
    'build_identity': manifest['source'], 'compiled_input_files_reverified': len(compiled_paths),
    'starting_files_preserved': len(unchanged), 'starting_files_intentionally_continued': len(continued),
    'real_box_acceptance': 'pending B7'}
write('checks.json', checks)
names = git('-c', 'core.quotePath=false', 'ls-files', '--cached', '--others', '--exclude-standard').splitlines()
write('source_manifest.json', {name: sha(ROOT / name) for name in sorted(names)
    if name.startswith(('lib/', 'test/', 'integration_test/', 'android/app/src/', 'doc/任务/任务一')) and (ROOT / name).is_file()})
print(json.dumps(checks, ensure_ascii=False, indent=2))
