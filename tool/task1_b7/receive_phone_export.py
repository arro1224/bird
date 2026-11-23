"""Receive only the prepared Debug App export identified by a captured receipt."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'deckers.thibault.aves.bird'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', required=True)
    parser.add_argument('--receipt-capture', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    labels = [n.get('text') or n.get('content-desc') or ''
              for n in ET.parse(args.receipt_capture).iter('node') if n.get('package') == PACKAGE]
    names = [s for s in labels if re.fullmatch(r'BirdBox_[A-Za-z0-9_.-]+\.zip', s)]
    hashes = [m.group(1) for s in labels if (m := re.fullmatch(r'文件 SHA-256：([a-f0-9]{64})', s))]
    sizes = [int(m.group(1)) for s in labels if (m := re.fullmatch(r'文件大小：(\d+) 字节', s))]
    assert len(names) == len(hashes) == len(sizes) == 1, 'Missing unique App receipt'
    assert not args.output.exists(), 'Never overwrite an earlier export'
    remote = 'cache/ble_diagnostics/' + names[0]
    result = subprocess.run(['D:/Androidstudio2/platform-tools/adb.exe', '-s', args.serial,
        'exec-out', 'run-as', PACKAGE, 'cat', remote], capture_output=True, check=True, timeout=40)
    assert len(result.stdout) == sizes[0]
    assert hashlib.sha256(result.stdout).hexdigest() == hashes[0]
    args.output.write_bytes(result.stdout)
    receipt = {'file': args.output.name, 'source_file': names[0], 'bytes': sizes[0], 'sha256': hashes[0],
        'expected_hash_source': 'independently observed App final-file SHA256 in UI hierarchy',
        'receipt_capture': args.receipt_capture.relative_to(ROOT).as_posix(),
        'receipt_xml_sha256': hashlib.sha256(args.receipt_capture.read_bytes()).hexdigest(),
        'transport': 'ADB run-as of own Debug App; native file picker cancelled; no external share',
        'received_hash_and_size_match_ui': True}
    args.output.with_suffix('.receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, ensure_ascii=True))


if __name__ == '__main__':
    main()
