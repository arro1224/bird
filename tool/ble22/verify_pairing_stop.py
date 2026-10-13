"""Check actual pairing cancel/timeout evidence without changing integration results."""
import argparse
import json
from pathlib import Path
import sys


def verify_stop(evidence, actions):
    errors = []
    def check(condition, reason):
        if not condition:
            errors.append(reason)
    app = evidence.get('app_evidence') or {}
    mode = evidence.get('pairing_expected_outcome')
    check(mode in ('Cancel', 'Timeout'), 'not_a_pairing_stop_check')
    code, outcome, action = {
        'Cancel': ('BLE_PAIRING_REJECTED', 'bond_rejected', 'test_pairing_cancelled'),
        'Timeout': ('BLE_PAIRING_TIMEOUT', 'bond_timeout', 'owned_pairing_intentionally_left_for_timeout'),
    }.get(mode, (None, None, None))
    check(evidence.get('scenario') == 'bond_first' and app.get('scenario') == 'bond_first', 'wrong_scenario')
    check(evidence.get('test_invoked') is True and evidence.get('test_exit_code') == 1, 'raw_expected_success_test_result_missing')
    check(evidence.get('run_status') == 'test_failed', 'interrupted_or_unknown_runner_state')
    check(evidence.get('hardware_status') == 'pending', 'hardware_scope_changed')
    phones = evidence.get('phones') or {}
    app_phone, box_phone = phones.get('app') or {}, phones.get('box') or {}
    check(bool(app_phone.get('physical_device_alias')) and bool(box_phone.get('physical_device_alias')) and app_phone.get('physical_device_alias') != box_phone.get('physical_device_alias'), 'two_physical_phone_identities_required')
    builds = evidence.get('builds') or {}
    app_build, box_build = builds.get('app') or {}, builds.get('box') or {}
    check(app_build.get('installed_verified') is True and box_build.get('installed_verified') is True and (app.get('build') or {}).get('apk_sha256') == app_build.get('apk_sha256') and bool(app_build.get('apk_sha256')), 'actual_build_identity_missing')
    check(evidence.get('export_received') is True and not (evidence.get('cleanup') or {}).get('errors'), 'file_or_cleanup_incomplete')
    check(app.get('failure_code') == code and app.get('response_type') is None, 'actual_stop_result_mismatch')
    check(app.get('initial_bond_state') == 'not_bonded', 'initial_native_baseline_missing')
    request = app.get('request_id')
    check(isinstance(request, str) and bool(request), 'request_identity_missing')
    all_events = app.get('events') or []
    events = [e for e in all_events if e.get('request_id') == request and e.get('source') == 'android']
    starts = [e for e in events if e.get('event_type') == 'user_start_pairing']
    facts = [e for e in events if e.get('event_type') == 'security_write_fact_finalized']
    check(len(starts) == 1 and starts[0].get('bond_state') == 'not_bonded', 'native_first_bond_start_missing')
    check(sum(e.get('event_type') == 'create_bond_invoked' for e in events) == 1, 'create_bond_count_mismatch')
    check(any(e.get('event_type') == 'create_bond_returned' and e.get('create_bond_returned') is True for e in events), 'bond_api_not_accepted')
    check(len(facts) == 1, 'terminal_parent_fact_missing')
    if len(facts) == 1:
        fact = facts[0]
        check(fact.get('terminal_outcome') == outcome and fact.get('cleanup_outcome') == 'complete', 'terminal_outcome_or_cleanup_mismatch')
        check(fact.get('create_bond_call_count') == 1 and fact.get('att_write_call_count') == 0 and fact.get('command_attempt_count') == 0, 'side_effect_counts_mismatch')
        check(bool(fact.get('attempt_id')) and type(fact.get('connection_generation')) is int, 'attempt_ownership_missing')
        if mode == 'Timeout':
            elapsed = fact.get('bond_elapsed_ms')
            check(type(elapsed) is int and 29500 <= elapsed <= 45000, 'timeout_not_bounded_near_30_seconds')
    check(not any(e.get('event_type') in ('security_write_api_invoked', 'gatt_rebuild_completed') for e in all_events), 'protected_path_entered')
    phone = (evidence.get('phones') or {}).get('app') or {}
    selector = phone.get('adb_selector_alias')
    check(bool(selector), 'physical_and_selector_identity_required')
    owned_actions = [a for a in actions if a.get('run_id') == evidence.get('run_id') and a.get('adb_selector_alias') == selector and a.get('pair_mode') == mode]
    check(not any(a.get('decision', {}).get('action') == 'blocked' for a in actions if a.get('run_id') == evidence.get('run_id')), 'unknown_or_blocked_ui')
    check(any(a.get('decision', {}).get('action') == action or a.get('decision', {}).get('reason') == action for a in owned_actions), 'actual_owned_operator_action_missing')
    return {'schema_version': 1, 'run_id': evidence.get('run_id'), 'expected_outcome': mode,
            'status': 'passed_expected_stop' if not errors else 'failed_or_incomplete', 'errors': errors,
            'raw_run_status': evidence.get('run_status'), 'raw_test_exit_code': evidence.get('test_exit_code'),
            'counts_as_normal_success': False, 'hardware_status': 'pending', 'releasable': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_directory')
    args = parser.parse_args()
    root = Path(args.run_directory)
    try:
        evidence = json.loads((root / 'evidence.json').read_text(encoding='utf-8-sig'))
        actions = [json.loads(line) for line in (root / 'operator-actions.jsonl').read_text(encoding='utf-8-sig').splitlines() if line.strip()]
        report = verify_stop(evidence, actions)
    except (OSError, ValueError, TypeError, KeyError) as error:
        report = {'status': 'failed_or_incomplete', 'errors': [str(error)], 'counts_as_normal_success': False,
                  'hardware_status': 'pending', 'releasable': False}
    (root / 'pairing-stop-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report['status'] == 'passed_expected_stop' else 2


if __name__ == '__main__':
    sys.exit(main())
