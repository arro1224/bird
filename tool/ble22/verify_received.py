"""Verify actual App JSON/ZIP exports in a BLE22 round, including failed runs."""
import argparse
import json
from pathlib import Path
import re
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ble19'))
from verify_diagnostic_file import verify


def verify_round(root):
    root = Path(root).resolve()
    reports, skipped, failures = [], [], []
    for evidence_path in sorted(root.glob('*/evidence.json')):
        try:
            evidence = json.loads(evidence_path.read_text(encoding='utf-8-sig'))
            artifact = evidence.get('export') or {}
            name = artifact.get('file_name')
            if not name:
                skipped.append({'run': evidence_path.parent.name, 'reason': 'no_prepared_app_export'})
                continue
            if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9._-]+\.(json|zip)', name):
                raise ValueError('invalid_export_filename')
            received = (evidence_path.parent / name).resolve()
            if received.parent != evidence_path.parent.resolve():
                raise ValueError('export_outside_run_directory')
            report = verify(received, artifact['sha256'])
            if report['critical_events_missing']:
                raise ValueError('critical_events_missing')
            if artifact.get('payload_sha256') != report['payload_sha256']:
                raise ValueError('app_payload_sha256_mismatch')
            if artifact.get('bytes') != report['bytes']:
                raise ValueError('app_file_length_mismatch')
            report.update(run_id=evidence['run_id'], role=evidence['role'], scenario=evidence['scenario'],
                          test_exit_code=evidence.get('test_exit_code'), run_status=evidence.get('run_status'))
            (evidence_path.parent / 'receiver-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            reports.append(report)
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, zipfile.BadZipFile) as error:
            failures.append({'run': evidence_path.parent.name, 'error': str(error)})
    result = {'received_files': len(reports), 'verified': bool(reports) and not failures,
              'reports': reports, 'skipped': skipped, 'failures': failures,
              'scope': 'file_integrity_and_actual_retention_only_not_phone_acceptance'}
    (root / 'receiver-verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('round_directory')
    args = parser.parse_args()
    result = verify_round(args.round_directory)
    print(json.dumps({key: value for key, value in result.items() if key != 'reports'}, ensure_ascii=False))
    return 0 if result['verified'] else 2


if __name__ == '__main__':
    sys.exit(main())
