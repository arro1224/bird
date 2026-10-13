"""Summarize BLE22 records; acceptance is never inferred from individual passes."""
import argparse
import json
from pathlib import Path


def summarize(root, previous=None):
    result = dict(previous or {})
    result.setdefault('schema_version', 1)
    result.setdefault('acceptance_status', 'paused_by_user')
    result.setdefault('handoff_readiness', 'blocked')
    result.update(hardware_status='pending', releasable=False)
    rounds = []
    for directory in sorted(Path(root).glob('ble22-*')):
        manifest = directory / 'builds.json'
        if not manifest.exists():
            continue
        runs = []
        for path in sorted(directory.glob('*/evidence.json')):
            evidence = json.loads(path.read_text(encoding='utf-8-sig'))
            app = evidence.get('app_evidence') or {}
            native = [event for event in app.get('events', []) if event.get('source') == 'android']
            validation = path.parent / 'validation.log'
            text = validation.read_text(encoding='utf-8-sig') if validation.exists() else ''
            run_status = evidence.get('run_status')
            passed = text.startswith('Virtual BirdBox evidence passed') and evidence.get('test_exit_code') == 0 and (run_status is None or run_status == 'passed')
            receiver = path.parent / 'receiver-verification.json'
            runs.append(dict(run_id=evidence['run_id'], role=evidence['role'], scenario=evidence['scenario'],
                iteration=evidence.get('iteration'), run_status=run_status, last_stage=evidence.get('last_stage'),
                test_exit_code=evidence.get('test_exit_code'), validation='passed' if passed else 'failed_or_pending',
                pairing_expected_outcome=evidence.get('pairing_expected_outcome'), pairing_check_status=evidence.get('pairing_check_status'),
                counts_as_normal_success=passed and evidence.get('pairing_expected_outcome', 'Confirm') == 'Confirm' and app.get('response_type') == 'pairing_opened',
                initial_bond_state=app.get('initial_bond_state'), failure_code=app.get('failure_code'),
                failure_stage=app.get('failure_stage'), runner_failure=evidence.get('failure'), response_type=app.get('response_type'),
                create_bond_calls=sum(event.get('event_type') == 'create_bond_invoked' for event in native),
                att_write_calls=sum(event.get('event_type') == 'security_write_api_invoked' for event in native),
                retry_count=max((event.get('retry_count') or 0 for event in native), default=0),
                connection_event_count=len(app.get('events', [])), app_build=app.get('build'), export=evidence.get('export'),
                receiver=json.loads(receiver.read_text(encoding='utf-8-sig')) if receiver.exists() else None))
        rounds.append(dict(round_id=directory.name, builds=json.loads(manifest.read_text(encoding='utf-8-sig')), runs=runs,
            unexecuted_starts=[p.parent.name for p in directory.glob('*/app-launch.log') if not (p.parent / 'evidence.json').exists()]))
    result['rounds'] = rounds
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    destination = Path(args.output)
    previous = json.loads(destination.read_text(encoding='utf-8-sig')) if destination.exists() else None
    result = summarize(args.input_root, previous)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'rounds': len(result['rounds']), 'runs': sum(len(r['runs']) for r in result['rounds']),
                      'acceptance_status': result['acceptance_status'], 'releasable': False}))


if __name__ == '__main__':
    main()
