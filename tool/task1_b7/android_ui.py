"""B7 Android UI capture and single observed-control action (ADB, no root).

Raw XML/screenshots stay under ignored build/. Public actions omit secrets.
Every tap resolves a unique label against a fresh hierarchy and exact package.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'build/task1_B7_20261123_01/private'
PUBLIC = ROOT / 'outputs/task1_B7_20261123_01'
REMOTE = '/data/local/tmp/task1-b7-view.xml'


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--tap')
    parser.add_argument('--resource-id')
    parser.add_argument('--simulator-code', action='store_true')
    parser.add_argument('--checked', choices=['true', 'false'])
    parser.add_argument('--scroll', choices=['down', 'up'])
    parser.add_argument('--quiet', action='store_true')
    parser.add_argument('--expect-package')
    args = parser.parse_args()
    if args.tap:
        args.tap = args.tap.replace('\\n', '\n')
    assert re.fullmatch(r'[a-zA-Z0-9_-]{1,80}', args.name)
    assert sum(bool(x) for x in [args.tap, args.resource_id, args.scroll, args.simulator_code]) <= 1
    PRIVATE.mkdir(parents=True, exist_ok=True)
    adb = ['D:/Androidstudio2/platform-tools/adb.exe', '-s', args.serial]

    def run(*arguments, binary=False):
        result = subprocess.run(adb + list(arguments), capture_output=True, timeout=35)
        if result.returncode:
            raise RuntimeError('ADB action failed; no follow-up action performed')
        return result.stdout if binary else result.stdout.decode('utf-8', errors='replace')

    tree = None
    for attempt in range(3):
        try:
            # Remove only this exact task-owned remote file, preventing stale trees.
            run('shell', 'rm', '-f', REMOTE)
            run('shell', 'uiautomator', 'dump', REMOTE)
            raw = run('shell', 'cat', REMOTE)
            tree = ET.fromstring(raw)
            break
        except (ET.ParseError, RuntimeError):
            if attempt == 2:
                raise
            time.sleep(1)
    assert tree is not None
    xml_path = PRIVATE / (args.name + '.xml')
    png_path = PRIVATE / (args.name + '.png')
    assert not xml_path.exists() and not png_path.exists(), 'Choose a fresh evidence name'
    xml_path.write_text(raw, encoding='utf-8')
    png = run('exec-out', 'screencap', '-p', binary=True)
    png_path.write_bytes(png)
    nodes = list(tree.iter('node'))
    result = {'captured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'evidence_name': args.name, 'private_capture': png_path.relative_to(ROOT).as_posix(),
              'screenshot_sha256': hashlib.sha256(png).hexdigest(), 'action': 'snapshot'}
    if args.tap or args.resource_id:
        assert args.expect_package, 'Exact package is required for a tap'
        matches = [n for n in nodes if n.get('package') == args.expect_package and
                   n.get('enabled') == 'true' and n.get('clickable') == 'true' and
                   ((args.tap and args.tap in [n.get('text'), n.get('content-desc')]) or
                    (args.resource_id and n.get('resource-id') == args.resource_id))]
        assert len(matches) == 1, 'No unique enabled control matched the fresh screen'
        if args.checked is not None:
            assert matches[0].get('checked') == args.checked, 'Unexpected original switch state'
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', matches[0].get('bounds', '')))
        run('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
        result.update(action='tap', label=args.tap, resource_id=args.resource_id, package=args.expect_package,
                      observed_bounds=matches[0].get('bounds'))
    if args.scroll:
        assert args.expect_package
        matches = [n for n in nodes if n.get('package') == args.expect_package and n.get('scrollable') == 'true']
        assert len(matches) == 1, 'No unique observed scroll surface'
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', matches[0].get('bounds', '')))
        top, bottom = y1 + (y2-y1)//5, y2 - (y2-y1)//5
        start, end = (bottom, top) if args.scroll == 'down' else (top, bottom)
        run('shell', 'input', 'swipe', str((x1+x2)//2), str(start), str((x1+x2)//2), str(end), '400')
        result.update(action='scroll', direction=args.scroll, package=args.expect_package)
    if args.simulator_code:
        assert args.expect_package == 'deckers.thibault.aves.bird'
        assert any(n.get('content-desc') == '与 BirdBox-B1E11001 配对' for n in nodes)
        fields = [n for n in nodes if n.get('package') == args.expect_package and
                  n.get('class') == 'android.widget.EditText' and n.get('enabled') == 'true']
        assert len(fields) == 1 and not fields[0].get('text'), 'Expected unique empty simulator code field'
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', fields[0].get('bounds', '')))
        run('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        run('shell', 'input', 'text', '246810')  # Fixed synthetic peripheral test code.
        result.update(action='input_simulator_code', value='<masked-synthetic-test-code>', package=args.expect_package)
    with (PUBLIC / 'ui_actions.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(result, ensure_ascii=False) + '\n')
    print(json.dumps(result, ensure_ascii=False))
    if args.quiet:
        return
    for node in nodes:
        label = node.get('text') or node.get('content-desc')
        if not label:
            continue
        if node.get('password') == 'true':
            label = '<masked>'
        label = re.sub(r'(?i)(?:[0-9a-f]{2}:){5}[0-9a-f]{2}', '<address-redacted>', label)
        print(json.dumps({'package': node.get('package'), 'label': label,
                          'clickable': node.get('clickable'), 'bounds': node.get('bounds')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
