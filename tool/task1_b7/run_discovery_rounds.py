"""Three observed UI rounds on the current B6 normal App; no fake transport."""
import argparse
import datetime
import json
import re
from pathlib import Path
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'build/task1_B7_20261123_01/private'
OUT = ROOT / 'outputs/task1_B7_20261123_01'
PACKAGE = 'deckers.thibault.aves.bird'


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9_-]{1,30}', args.run_id)
    result_path = OUT / (args.run_id + '_rounds.json')
    assert not result_path.exists(), 'Choose a fresh run id'
    report = {'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'evidence_kind': 'real_vivo_normal_app_with_huawei_virtual_peripheral',
              'transport': 'real BLE and LAN; no USB business forwarding', 'rounds': [], 'status': 'running'}

    def checkpoint():
        result_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def ui(name, *action):
        command = [sys.executable, str(ROOT / 'tool/task1_b7/android_ui.py'), '--serial', args.serial, '--name', name, '--quiet']
        if action:
            command += ['--expect-package', PACKAGE, *action]
        subprocess.run(command, cwd=ROOT, check=True, timeout=110)
        tree = ET.parse(PRIVATE / (name + '.xml'))
        return [n.get('text') or n.get('content-desc') or '' for n in tree.iter('node') if n.get('package') == PACKAGE]

    def assert_current(labels):
        assert labels.count('当前已连接盒子') == 1, 'Current business card missing or duplicated'
        assert '当前盒子蓝牙控制已连接' in labels, 'Trusted BLE control was not retained'
        assert any('业务已验证' in value for value in labels), 'Business session is not verified'

    def wait_for_scan(prefix):
        for poll in range(8):
            labels = ui(prefix + f'_idle_{poll}')
            if not any('正在通过蓝牙查找' in label for label in labels):
                return labels
            time.sleep(2)
        raise AssertionError('Scan did not finish inside the observed round budget')

    checkpoint()
    try:
        for i in range(1, 4):
            prefix = f'{args.run_id}_{i}'
            start = datetime.datetime.now(datetime.timezone.utc).isoformat()
            labels = ui(prefix + '_source')
            if '连接设备' in labels:
                ui(prefix + '_enter', '--tap', '连接设备')
            elif '新增或切换设备\n新增或切换设备' in labels:
                ui(prefix + '_enter', '--tap', '新增或切换设备\\n新增或切换设备')
            else:
                raise AssertionError('Expected album or device source page was not observed')
            labels = ui(prefix + '_before')
            assert_current(labels)
            labels = wait_for_scan(prefix + '_initial')
            if '重新搜索' not in labels:
                ui(prefix + '_down', '--scroll', 'down')
            ui(prefix + '_rescan', '--tap', '重新搜索')
            labels = wait_for_scan(prefix + '_rescan')
            if '当前已连接盒子' not in labels:
                ui(prefix + '_up', '--scroll', 'up')
            labels = ui(prefix + '_after')
            assert_current(labels)
            ui(prefix + '_leave', '--tap', '\\n返回')
            report['rounds'].append({'iteration': i, 'started_at_utc': start,
                'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'ui_assertions': 'passed', 'current_business_cards': 1, 'trusted_ble_retained': True,
                'native_no_reconnect_assertion': 'verify separately against retained diagnostic records'})
            checkpoint()
            print('A15_ROUND_PASSED ' + str(i), flush=True)
        report['status'] = 'three_ui_rounds_passed_native_evidence_pending'
    except Exception as error:
        report['status'] = 'failed'
        report['failure_kind'] = type(error).__name__
        report['failure_reason'] = str(error)
        raise
    finally:
        report['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        checkpoint()


if __name__ == '__main__':
    main()
