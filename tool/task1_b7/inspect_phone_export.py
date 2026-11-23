"""Inspect the current all-retained-flow phone ZIP; does not certify acceptance.

The legacy ble19 verifier expects a single-flow retention header. Current App
exports have a compact summary and per-flow counters in full_trace.json.
Keep that legacy failure as evidence, and verify hashes/identity here without
equating the selected flow's retained count with the whole archive's count.
"""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('file', type=Path)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--since', required=True, help='Inclusive UTC ISO timestamp')
    parser.add_argument('--until', help='Exclusive UTC ISO timestamp')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    raw = args.file.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == args.sha256.lower(), 'File hash mismatch'
    with zipfile.ZipFile(args.file) as archive:
        assert set(archive.namelist()) == {'summary.json', 'full_trace.json', 'README.txt'}
        assert len(archive.infolist()) == 3
        assert all(not e.flag_bits & 1 and e.file_size <= 32 * 1024 * 1024 for e in archive.infolist())
        assert archive.testzip() is None
        payload = archive.read('full_trace.json')
        summary = json.loads(archive.read('summary.json'))
        readme = archive.read('README.txt').decode('utf-8')
    digest = hashlib.sha256(payload).hexdigest()
    assert re.findall(r'[a-fA-F0-9]{64}', readme) == [digest], 'Payload hash mismatch'
    full = json.loads(payload)
    for key in ['trace_id', 'generated_at', 'build', 'exporting_app_build']:
        assert summary.get(key) == full.get(key), 'Summary identity mismatch: ' + key
    assert full['schema_version'] == 4 and full['retained_records_complete'] is True
    assert summary['retained_event_count'] == len(full['connection_events'])
    retention = full['retention']
    flows = retention['per_flow_retention']
    events = full['connection_events']
    scans = full['scan_sessions']
    def group(record):
        return record.get('flow_id') or record.get('trace_id')
    event_groups = Counter(group(e) for e in events)
    scan_groups = Counter(group(s) for s in scans)
    # The App deliberately includes historical flows with zero surviving records.
    assert set(event_groups) | set(scan_groups) <= set(flows)
    for flow_id, stats in flows.items():
        assert stats['events']['retained'] == event_groups[flow_id]
        assert stats['scans']['retained'] == scan_groups[flow_id]
    expected_summary = {
        'export_scope': retention['export_scope'],
        'included_flow_count': len(retention['included_flow_ids']),
        'observations_dropped': retention['observations_dropped'],
        'truncated': summary['retention']['truncated'],
        'per_flow_loss_details_in_full_file': True,
    }
    assert summary['retention'] == expected_summary
    def in_window(record):
        stamp = record.get('occurred_at') or record.get('started_at') or ''
        if not stamp:
            return False
        instant = datetime.fromisoformat(stamp.replace('Z', '+00:00'))
        return instant >= datetime.fromisoformat(args.since.replace('Z', '+00:00')) and (
            not args.until or instant < datetime.fromisoformat(args.until.replace('Z', '+00:00')))
    current_events = [e for e in events if in_window(e)]
    phone = full.get('phone_diagnostics', {})
    current_phone = [e for e in phone.get('events', []) if in_window(e)]
    current_scans = [s for s in scans if in_window(s)]
    def safe_event(e):
        keys = ['occurred_at', 'event_type', 'source', 'flow_id', 'operation_name',
                'result_code', 'gatt_instance_id', 'gatt_generation', 'gatt_status',
                'connection_generation', 'error_code', 'release_reason']
        return {k: e[k] for k in keys if k in e}
    selected = [e for e in current_events if e.get('source') != 'app_connection']
    relevant_flows = set(group(e) for e in current_events) | set(group(s) for s in current_scans)
    report = {
        'file_integrity': 'passed', 'scope': 'hash_identity_per_flow_counts_and_retained_window_only',
        'formal_acceptance': False, 'file_bytes': len(raw), 'file_sha256': args.sha256.lower(),
        'payload_sha256': digest, 'trace_id': full['trace_id'], 'exported_at': full['generated_at'],
        'exporting_app_build': full['exporting_app_build'],
        'window': {'since_inclusive': args.since, 'until_exclusive': args.until},
        'retained_event_count': len(events), 'retained_scan_count': len(scans),
        'raw_history_complete': full.get('raw_history_complete'),
        'phone_retention': phone.get('retention'),
        'window_event_types': dict(Counter(e['event_type'] for e in current_events)),
        'window_phone_event_types': dict(Counter(e['event_type'] for e in current_phone)),
        'window_http_results': dict(Counter(
            f"{e.get('request_kind')} {e.get('route')} {e.get('http_status')} {e.get('outcome')}"
            for e in current_phone if e.get('event_type') == 'http_request_finished')),
        'window_ble_events': [safe_event(e) for e in selected],
        'window_scans': [{k: s.get(k) for k in ['scan_session_id', 'flow_id', 'scan_trigger',
            'started_at', 'native_started_at', 'ended_at', 'raw_result_count', 'accepted_count',
            'permission_before', 'adapter_before', 'location_service_before']} for s in current_scans],
        'window_flow_retention': {k: flows[k] for k in sorted(relevant_flows)},
        'interpretation': 'No event in bounded retained history is not proof that an event never occurred.',
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'integrity': 'passed', 'window_events': len(current_events),
                      'window_phone_events': len(current_phone), 'window_scans': len(current_scans)}))


if __name__ == '__main__':
    main()
