"""Capture read-only T1-B0 evidence. Run from the project root; refuse overwrite."""
import collections
import hashlib
import json
import platform
import re
import subprocess
import sys
import zipfile
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path.cwd().resolve()
OUT = ROOT / 'outputs/task1_B0_20261123'
EXPECTED_HEAD = '28aeae2a0ba5edf4c19dca584117345d26762e05'


def run(*args):
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, encoding='utf-8', errors='replace')
    return {'command': list(args), 'exit_code': result.returncode,
            'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}


def write(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def sha(data):
    return hashlib.sha256(data).hexdigest()


assert (ROOT / 'pubspec.yaml').exists(), 'Run from project 4 root'
assert not (OUT / 'baseline.json').exists(), 'Evidence already captured; use a new directory'
head = run('git', 'rev-parse', 'HEAD')['stdout']
assert head == EXPECTED_HEAD, 'Baseline HEAD changed'
stamp = datetime.now(timezone(timedelta(hours=8))).isoformat()
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
prefixes = ('lib/', 'android/', 'test/', 'integration_test/', 'tool/', 'docs/contracts/')
files = sorted(p for p in tracked if p and (p.startswith(prefixes) or p in
               {'pubspec.yaml', 'pubspec.lock', 'README.md', 'analysis_options.yaml'}))
manifest = [{'path': p, 'bytes': (ROOT / p).stat().st_size,
             'sha256': sha((ROOT / p).read_bytes())} for p in files if (ROOT / p).is_file()]
write('source_manifest.json', {'captured_at': stamp, 'head': head,
      'scope': list(prefixes), 'fingerprint_kind': 'working-file bytes, not Git blob IDs',
      'files': manifest, 'file_count': len(manifest)})

patterns = [r'\b\w*(?:release|disconnect|claimsession|endsession|dispose|close|stopscan|stopdiscovery|teardown|unbindprocess)\w*\s*\(',
            r"['\"](?:releaseNetwork|disconnect|dispose|stopScan|releaseGatt)['\"]"]
site_re = re.compile('|'.join(patterns), re.IGNORECASE)
scope = [ROOT / 'lib/bird_companion/features/connection', ROOT / 'lib/bird_companion/core/session']
candidates = set(p for d in scope for p in d.rglob('*.dart'))
candidates.update(ROOT / p for p in [
    'lib/bird_companion/app/app_dependencies.dart',
    'lib/bird_companion/app/app_router.dart',
    'lib/bird_companion/features/settings/presentation/pages/network_settings_page.dart'])
native = ROOT / 'android/app/src/main/java/deckers/thibault/aves'
candidates.update(native / name for name in
                  ['BirdBoxWifiChannel.java', 'BirdBoxBleChannel.java', 'BirdBoxDppChannel.java', 'MainActivity.java'])
sites = []
for path in sorted(candidates):
    relative = path.relative_to(ROOT).as_posix()
    if 'b7_simulated' in relative:
        group = 'simulation_only'
    elif 'BirdBoxWifiChannel' in relative or 'birdbox_wifi_platform' in relative:
        group = 'wifi_native_or_bridge'
    elif 'BirdBoxBleChannel' in relative or 'platform_birdbox_ble_data_source' in relative:
        group = 'ble_owner_transport'
    elif 'provisioning_repository_impl' in relative:
        group = 'provisioning_repository'
    elif '/presentation/' in relative:
        group = 'page_or_cubit_lifetime'
    elif '/core/session/' in relative or 'connection_api' in relative or 'connection_repository_impl' in relative:
        group = 'business_session'
    else:
        group = 'application_or_auxiliary_cleanup'
    for line_no, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        if site_re.search(line):
            sites.append({'path': relative, 'line': line_no, 'group': group, 'source': line.strip()})
write('resource_sites.json', {'scope_note': 'Lexical inventory: definitions, calls, channel names and comments; not a runtime call graph. Stream/controller cleanup is included, not counted as network release.',
      'files_scanned': len(candidates), 'matches': len(sites), 'sites': sites})
(OUT / 'resource_sites.tsv').write_text('path\tline\tgroup\tsource\n' + ''.join(
    f"{s['path']}\t{s['line']}\t{s['group']}\t{s['source'].replace(chr(9), ' ')}\n" for s in sites), encoding='utf-8')

events = []
for line in (OUT / 'flutter_test_events.jsonl').read_text(encoding='utf-8-sig').splitlines():
    try:
        events.append(json.loads(line))
    except ValueError:
        pass
starts = {x['test']['id']: x['test'] for x in events if x.get('type') == 'testStart'}
ends = [x for x in events if x.get('type') == 'testDone' and not x.get('hidden')]
counts = collections.Counter('skipped' if x.get('skipped') else x['result'] for x in ends)
checks = {}
for name in ['flutter_test', 'dart_analyze', 'production_integrity', 'contracts']:
    checks[name] = {'exit_code': int((OUT / (name + '_exit.txt')).read_text(encoding='utf-8-sig').strip())}
checks['flutter_test'].update({'scope': ['test/bird_companion/features/connection',
    'test/bird_companion/settings/network_settings_page_test.dart',
    'test/bird_companion/app/reconnect_connection_route_test.dart'],
    'result_counts': dict(counts), 'done': [x for x in events if x.get('type') == 'done'],
    'skipped_cases': [starts[x['testID']] for x in ends if x.get('skipped')]})
write('checks.json', checks)

materials = []
source_dir = Path('D:/wexin/xwechat_files/wxid_p3alcuscjco722_365a/msg/file/2026-11')
for name in ['11-21 材料2.zip', '任务2_回交说明与待确认清单_2026-11-22.md']:
    path = source_dir / name
    materials.append({'name': name, 'bytes': path.stat().st_size, 'sha256': sha(path.read_bytes())})
with zipfile.ZipFile(source_dir / '11-21 材料2.zip') as archive:
    for entry in archive.infolist():
        if entry.filename.endswith('.md'):
            materials.append({'zip_entry': entry.filename, 'bytes': entry.file_size,
                              'sha256': sha(archive.read(entry))})
write('materials_manifest.json', materials)

write('toolchain.json', {'captured_at': stamp,
    'flutter': {'source': 'Successful elevated cached flutter_tools.snapshot --version --machine',
                'version': json.loads(Path('D:/flutter344/flutter/bin/cache/flutter.version.json').read_text())},
    'dart': run('D:/flutter344/flutter/bin/cache/dart-sdk/bin/dart.exe', '--version'),
    'java': run('C:/Program Files/Android/Android Studio/jbr/bin/java.exe', '-version'),
    'adb_version': run('D:/Androidstudio2/platform-tools/adb.exe', 'version'),
    'git': run('git', '--version'), 'python': sys.version, 'host': platform.platform(),
    'adb_devices_observation': {'source': 'Successful elevated adb devices -l in this B0 run',
          'exit_code': 0, 'stdout': 'List of devices attached\n\n', 'device_count': 0,
          'physical_availability': 'unknown; no device connected, not proof of absence'}})

write('baseline.json', {'captured_at': stamp, 'batch': 'T1-B0', 'head': head,
    'tree': run('git', 'rev-parse', 'HEAD^{tree}')['stdout'],
    'branch': run('git', 'branch', '--show-current')['stdout'],
    'source_branch': 'thirdtime', 'task2_commit': EXPECTED_HEAD,
    'working_tree_status': run('git', '-c', 'core.quotePath=false', 'status', '--short'),
    'tracked_input_diff': run('git', 'diff', '--exit-code', 'HEAD', '--', 'lib', 'android', 'test', 'integration_test', 'tool', 'pubspec.yaml', 'pubspec.lock', 'docs/contracts'),
    'source_manifest_sha256': sha((OUT / 'source_manifest.json').read_bytes()),
    'source_file_count': len(manifest), 'resource_site_count': len(sites),
    'business_source_modified': False, 'apk_built': False, 'hardware_acceptance': 'not_run',
    'checks': 'checks.json', 'open_items': '接口待确认清单.md',
    'completion_rule': 'Local B0 audit complete; board answers and hardware evidence remain pending, and do not imply A15/A17/A18 acceptance.'})
assert checks['flutter_test']['exit_code'] == 0 and counts['success'] == 518 and counts['skipped'] == 3
assert all(x['exit_code'] == 0 for x in checks.values())
print(json.dumps({'source_files': len(manifest), 'resource_sites': len(sites), 'tests': dict(counts)}, ensure_ascii=False))
