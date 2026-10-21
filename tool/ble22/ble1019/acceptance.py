"""BLE1019 evidence bookkeeping. No ADB, pairing, deletion or board commands."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'tool' / 'ble19'))
from verify_diagnostic_file import verify as verify_file

PHONES = {'huawei_mis_al00': 'MIS-AL00', 'oppo_pkc110': 'PKC110', 'oppo_pma110': 'PMA110'}
ALL = tuple(PHONES)
OPPO = ('oppo_pkc110', 'oppo_pma110')
# id, source requirement, title, phones, repetitions, popup rule, final UI
CASES = [
    ('M01', 'main-6.1', 'OPPO全新配对', OPPO, 5, 'one', 'method_selection'),
    ('M02', 'main-6.2', '华为全新配对', ('huawei_mis_al00',), 5, 'one', 'method_selection'),
    ('M03', 'main-6.3', '华为手机忘记、盒子保留', ('huawei_mis_al00',), 5, 'one', 'method_selection'),
    ('M04', 'main-6.4', 'OPPO手机忘记、盒子保留', OPPO, 5, 'one', 'method_selection'),
    ('M05', 'main-6.5', '华为手机保留、盒子忘记', ('huawei_mis_al00',), 5, 'zero_or_one', 'recovered_or_phone_forget_guidance'),
    ('M06', 'main-6.6', 'OPPO手机保留、盒子忘记', OPPO, 5, 'zero_or_one', 'recovered_or_phone_forget_guidance'),
    ('M07', 'main-6.7', '已配对重连', ALL, 5, 'zero', 'method_selection'),
    ('M08', 'main-6.8', '用户取消系统弹窗', ALL, 5, 'one', 'cancellation_guidance'),
    ('M09', 'main-6.9', '配对中前后台切换', ALL, 5, 'one', 'method_selection'),
    ('M10', 'main-6.10', '快速重复点击连接', ALL, 5, 'one', 'method_selection'),
    ('M11', 'main-6.11', '失败后手动重试一次', ALL, 5, 'per_action', 'method_selection'),
    *[(f'M12-{mode}', 'main-6.12', f'Wi-Fi环境：{label}', ALL, 5, 'one', 'method_selection')
      for mode, label in [('same', '同一热点'), ('different', '不同热点'), ('none', '无Wi-Fi')]],
    ('P01', 'increment-8.1', '双端无记录', ALL, 5, 'one', 'method_selection'),
    ('P02', 'increment-8.2', '双端有记录重复连接', ALL, 10, 'zero', 'method_selection'),
    ('P03', 'increment-8.3', '手机忘记、盒子保留', ALL, 5, 'one', 'method_selection'),
    ('P04', 'increment-8.4', '前后台切换后重连', ALL, 5, 'native_baseline', 'method_selection'),
    ('P05', 'increment-8.5', '预检响应时主动断链', ALL, 3, 'zero', 'retryable_preflight_failure'),
    ('P06', 'increment-8.6', '确认reset后预期断链', ALL, 5, 'zero', 'fresh_preflight_ready'),
]
CASE = {c[0]: c for c in CASES}
ASYMMETRIC = {'M03', 'M04', 'P03', 'P06'}
NEW_PAIR = {'M01', 'M02', 'M09', 'M10', 'P01', 'M12-same', 'M12-different', 'M12-none'}
SIGNOFFS = ('native_abi_jointly_confirmed', 'native_single_flight_and_idempotent_cleanup',
            'native_first_error_preserved', 'native_gatt_release_and_foreground_sync',
            'no_brand_model_core_branch', 'no_automatic_repeat_pairing', 'dart_first_error_preserved')
DELIVERABLES = ('source_diff', 'native_test_report', 'dart_test_report', 'acceptance_report',
                'successful_asymmetric_trace', 'user_cancel_trace', 'foreground_gatt_trace', 'change_scope')
TOKEN_KEYS = {'resettoken', 'resettokenhash', 'password', 'passphrase', 'accesstoken', 'authorization',
              'pairingsessionid', 'deviceaddress', 'address', 'mac', 'macaddress', 'bluezpath',
              'wifipassword', 'hotspotpassword', 'authtoken', 'authorizationtoken', 'token', 'resettokensha256'}
MAC = re.compile(r'(?i)(?:[0-9a-f]{2}[:_-]){5}[0-9a-f]{2}')
ASSIGNMENT = re.compile(r'(?i)(?:reset_token(?:_hash)?|password|passphrase|access_token|pairing_session_id)\s*[=:]\s*(?!<redacted>)[^\s,;}]+')


def require(condition, code):
    if not condition:
        raise ValueError(code)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def read(path):
    path = Path(path)
    require(path.stat().st_size <= 32 * 1024 * 1024, 'metadata_too_large')
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_new(path, value):
    path = Path(path)
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def inside(root, relative):
    require(isinstance(relative, str) and relative and not Path(relative).is_absolute(), 'relative_artifact_path_required')
    path = (Path(root).resolve() / relative).resolve(strict=True)
    require(path.is_relative_to(Path(root).resolve()) and path.is_file(), 'artifact_outside_round')
    return path


def privacy(value):
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = re.sub(r'[^a-z0-9]', '', str(key).lower())
            require(normalized not in TOKEN_KEYS or item is None, 'sensitive_field_present')
            privacy(item)
    elif isinstance(value, list):
        for item in value:
            privacy(item)
    elif isinstance(value, str):
        require(not MAC.search(value) and not ASSIGNMENT.search(value), 'sensitive_text_present')


def artifact(root, reference, *, json_file=True):
    require(isinstance(reference, dict), 'artifact_reference_missing')
    path = inside(root, reference.get('path'))
    require(path.stat().st_size <= 512 * 1024 * 1024, 'artifact_too_large')
    require(re.fullmatch(r'[a-f0-9]{64}', str(reference.get('sha256', ''))) is not None, 'artifact_sha256_required')
    require(sha(path) == reference['sha256'], 'artifact_sha256_mismatch')
    if json_file:
        value = read(path)
        privacy(value)
        return value
    return path


def trace(root, reference):
    path = artifact(root, reference, json_file=False)
    report = verify_file(path, reference['sha256'])
    require(not report['critical_events_missing'], 'critical_events_missing')
    if path.suffix.lower() == '.zip':
        with zipfile.ZipFile(path) as archive:
            full = json.loads(archive.read('full_trace.json').decode('utf-8'))
            privacy(json.loads(archive.read('summary.json').decode('utf-8')))
            privacy(archive.read('README.txt').decode('utf-8'))
    else:
        full = read(path)
    privacy(full)
    require(any(e.get('source') == 'android' for e in full['connection_events']), 'android_evidence_missing')
    return full, report


def matrix():
    return [{'case_id': c[0], 'requirement': c[1], 'title': c[2], 'phone': p,
             'minimum_runs': c[4], 'popup_rule': c[5], 'expected_ui': c[6], 'status': 'not_run'}
            for c in CASES for p in c[3]]


def matrix_markdown():
    lines = ['# BLE1019验收矩阵', '', '本表由acceptance.py生成。主12项和增量6行分别登记，不去重，共264轮；未执行的项目不得填通过。', '',
             '|编号|要求来源|场景|手机|每机轮次|系统弹窗规则|最终页面/结果|', '|---|---|---|---|---:|---|---|']
    for case in CASES:
        lines.append('|' + '|'.join([case[0], case[1], case[2], '/'.join(PHONES[p] for p in case[3]), str(case[4]), case[5], case[6]]) + '|')
    lines += ['', 'P06的0次弹窗针对reset确认后到fresh预检就绪这一段；后续用户开始配对的弹窗另计。',
              'main-6.n表示主文档§6的第n项；increment-8.n表示增量文档§8表格第n行，不是同名子章节。',
              'P04按实际原生BOND_BONDED=0次、BOND_NONE=1次；M11按首次动作与手动重试分别记录，不允许每个动作重复弹窗。',
              '测试前的目标设备状态准备与失败后的“双端忘记才能恢复”必须区分；后者不得通过。',
              '失败先导出完整诊断并保留现场，不能为凑满成功次数覆盖失败记录。']
    return '\n'.join(lines) + '\n'


def snapshot():
    paths = ['lib/bird_companion', 'android/app/src', 'android/app/build.gradle.kts',
             'android/gradle.properties', 'pubspec.yaml', 'pubspec.lock', 'docs/contracts',
             'test/bird_companion', 'test/contracts', 'tool/ble22', 'tool/ble19', 'tool/contracts']
    raw = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z', '--', *paths], cwd=REPO)
    lines = [f'{p}\t{sha(REPO / p)}' for p in sorted(set(raw.decode('utf-8').strip('\0').split('\0')))
             if p and (REPO / p).is_file()]
    return {'git_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
            'source_fingerprint': hashlib.sha256(('\n'.join(lines) + '\n').encode()).hexdigest(),
            'scope': paths, 'files': lines, 'scope_note': 'review snapshot; not a frozen release build'}


def export_review(root, label):
    root = Path(root).resolve()
    require(root.is_relative_to(REPO) and (root / 'artifacts').resolve().is_relative_to(root), 'round_must_be_inside_workspace')
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,64}', label) is not None, 'invalid_review_label')
    before = snapshot()
    output = root / 'artifacts' / f'source-review-{label}'
    output.mkdir(exist_ok=False)
    patch = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--binary', 'HEAD', '--', *before['scope']], cwd=REPO)
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z', '--', *before['scope']], cwd=REPO)
    new_files = sorted(p for p in untracked.decode('utf-8').split('\0') if p)
    for name in new_files:
        content = (REPO / name).read_text(encoding='utf-8').splitlines(keepends=True)
        if content and not content[-1].endswith('\n'):
            content[-1] += '\n'
        patch += (f'diff --git a/{name} b/{name}\nnew file mode 100644\n' +
                  ''.join(difflib.unified_diff([], content, fromfile='/dev/null', tofile='b/' + name))).encode('utf-8')
    require(snapshot()['source_fingerprint'] == before['source_fingerprint'], 'source_changed_during_review_export')
    (output / 'changes.patch').write_bytes(patch)
    write_new(output / 'source-snapshot.json', before)
    write_new(output / 'manifest.json', {'kind': 'working_tree_review_only', 'git_commit': before['git_commit'],
        'source_fingerprint': before['source_fingerprint'], 'includes_untracked_files': new_files,
        'patch_sha256': sha(output / 'changes.patch'), 'release_build_fingerprint': False,
        'hardware_verified': False, 'releasable': False})
    return output


def initialize(output_root, round_id):
    require(re.fullmatch(r'ble1019-[A-Za-z0-9][A-Za-z0-9._-]{0,64}', round_id) is not None, 'invalid_round_id')
    root = Path(output_root).resolve() / round_id
    require(root.is_relative_to(REPO), 'round_must_be_inside_workspace')
    root.mkdir(parents=True, exist_ok=False)
    for name in ('runs', 'artifacts', 'checks'):
        (root / name).mkdir()
    write_new(root / 'round.json', {'schema_version': 1, 'suite': 'ble1019-v1', 'round_id': round_id,
              'created_at': datetime.now(timezone.utc).isoformat(), 'hardware_status': 'not_run',
              'releasable': False, 'build': None, 'signoffs': {s: None for s in SIGNOFFS},
              'deliverables': {d: None for d in DELIVERABLES}})
    write_new(root / 'matrix.json', matrix())
    write_new(root / 'source-snapshot.json', snapshot())
    (root / 'matrix.md').write_text(matrix_markdown(), encoding='utf-8')
    write_new(root / 'build.template.json', {'apk': None, 'package_id': None, 'version_name': None,
               'version_code': None, 'git_commit': None, 'source_fingerprint': None, 'build_id': None,
               'metadata_evidence': None})
    return root


def new_run(root, case_id, phone, iteration, kind):
    root = Path(root).resolve()
    require(root.is_relative_to(REPO) and (root / 'runs').resolve().is_relative_to(root), 'round_must_be_inside_workspace')
    require(read(root / 'round.json').get('suite') == 'ble1019-v1', 'wrong_suite')
    require(case_id in CASE and phone in CASE[case_id][3], 'case_phone_mismatch')
    require(type(iteration) is int and 1 <= iteration <= CASE[case_id][4], 'iteration_out_of_range')
    require(kind in ('real_phone_real_board', 'virtual_peripheral', 'offline_fixture'), 'invalid_evidence_kind')
    run_id = f'{case_id}-{phone}-{iteration:02}'
    destination = Path(root) / 'runs' / run_id
    destination.mkdir(exist_ok=False)
    write_new(destination / 'evidence.json', {
        'schema_version': 1, 'round_id': read(Path(root) / 'round.json')['round_id'],
        'run_id': run_id, 'case_id': case_id, 'phone': phone, 'iteration': iteration,
        'evidence_kind': kind, 'status': 'not_run',
        'artifacts': {'diagnostic': None, 'operator': None, 'board': None, 'board_log': None}})
    write_new(destination / 'operator.template.json', {
        'run_id': run_id, 'observer_alias': None, 'observed_at': None, 'phone_model': PHONES[phone],
        'phone_sdk_int': None, 'phone_alias': None, 'prepared_scenario_verified': None,
        'phone_native_bond_state': None, 'board_paired_before': None, 'board_bonded_before': None,
        'final_ui': None, 'final_ui_error_code': None, 'first_operation_succeeded': None,
        'user_actions': [], 'preflight_dialogs': None, 'wifi_state': None, 'both_sides_forget_required': None,
        'assertions': {s: None for s in ['no_auto_repeat_pairing', 'other_peers_preserved',
            'no_early_bonding', 'first_error_preserved', 'single_flight', 'late_callbacks_isolated',
            'release_before_new_connect', 'native_gatt_sync_checked', 'device_id_revalidated',
            'expected_disconnect_not_reported_as_failure']}})
    write_new(destination / 'board.template.json', {'run_id': run_id, 'observer_alias': None,
        'observed_at': None, 'source_log_sha256': None, 'other_peers_preserved': None,
        'paired_before': None, 'bonded_before': None, 'phone_alias': None,
        'advertising_recovered': None, 'ack_before_removal': None, 'same_peer_prepare_confirm': None})
    return destination


def action_of(event):
    if event.get('result_code') in ('none', 'reset_required', 'remove_scheduled'):
        return event['result_code']
    return None


def check_release_completions(events):
    pending = set()
    for event in events:
        if event.get('source') != 'dart':
            continue
        kind = event.get('event_type')
        if kind not in ('gatt_release_requested', 'gatt_release_confirmed', 'gatt_release_recovered'):
            continue
        scope = event.get('flow_id') or event.get('trace_id')
        generation = event.get('connection_generation')
        instance = event.get('gatt_instance_id', event.get('gatt_generation'))
        require(isinstance(scope, str) and scope and type(generation) is int and generation > 0
                and type(instance) is int and instance > 0, 'release_owner_missing')
        owner = (scope, generation, instance)
        if kind == 'gatt_release_requested':
            pending.add(owner)
        elif ((kind == 'gatt_release_confirmed' and event.get('result_code') == 'native_disconnect_and_close_confirmed')
              or (kind == 'gatt_release_recovered' and event.get('result_code') == 'adapter_disabled_and_native_absent')):
            pending.discard(owner)
    # Native teardown_completed is emitted at barrier start. Neither that nor
    # an idempotent success can close a pending Dart release in the evidence.
    require(not pending, 'release_completion_unconfirmed')


def check_run(root, path):
    evidence = read(path)
    require(isinstance(evidence, dict), 'evidence_object_required')
    privacy(evidence)
    case_id, phone = evidence.get('case_id'), evidence.get('phone')
    require(case_id in CASE and phone in CASE[case_id][3], 'case_phone_mismatch')
    case = CASE[case_id]
    iteration = evidence.get('iteration')
    require(type(iteration) is int and 1 <= iteration <= case[4], 'iteration_out_of_range')
    require(evidence.get('run_id') == f'{case_id}-{phone}-{iteration:02}', 'run_identity_mismatch')
    round_record = read(Path(root) / 'round.json')
    require(isinstance(round_record, dict), 'round_object_required')
    privacy(round_record)
    require(evidence.get('round_id') == round_record['round_id'], 'wrong_round')
    require(evidence.get('status') == 'observed', 'run_not_observed')
    require(evidence.get('evidence_kind') == 'real_phone_real_board', 'nonphysical_evidence_not_acceptance')
    refs = evidence['artifacts']
    full, received = trace(root, refs['diagnostic'])
    operator = artifact(root, refs['operator'])
    board = artifact(root, refs['board'])
    require(isinstance(operator, dict) and isinstance(board, dict), 'observation_object_required')
    board_log = artifact(root, refs['board_log'], json_file=False)
    require(board_log.stat().st_size <= 4 * 1024 * 1024, 'board_log_too_large')
    privacy(board_log.read_text(encoding='utf-8-sig'))
    require(board_log.stat().st_size > 0 and board.get('source_log_sha256') == sha(board_log), 'board_log_provenance_missing')
    for record in (operator, board):
        require(record.get('run_id') == evidence['run_id'], 'observation_run_mismatch')
        require(isinstance(record.get('observer_alias'), str) and record['observer_alias'].strip(), 'human_observer_missing')
        require(datetime.fromisoformat(record['observed_at']).tzinfo is not None, 'observation_timezone_required')
    require(operator.get('phone_model') == PHONES[phone], 'required_phone_model_mismatch')
    require(type(operator.get('phone_sdk_int')) is int and operator['phone_sdk_int'] >= 23, 'phone_sdk_missing')
    require(isinstance(operator.get('phone_alias'), str) and operator['phone_alias'].strip(), 'physical_phone_alias_missing')
    require(board.get('phone_alias') == operator['phone_alias'], 'board_phone_provenance_mismatch')
    require(operator.get('prepared_scenario_verified') is True, 'scenario_setup_not_verified')
    require(all(type(operator.get(k)) is bool for k in ('board_paired_before', 'board_bonded_before')), 'board_bond_baseline_required')
    require(board.get('paired_before') == operator['board_paired_before'] and board.get('bonded_before') == operator['board_bonded_before'], 'board_baseline_observation_mismatch')
    require(operator.get('both_sides_forget_required') is False, 'manual_double_forget_not_accepted')
    assertions = operator.get('assertions', {})
    for name in ('no_auto_repeat_pairing', 'other_peers_preserved', 'no_early_bonding', 'first_error_preserved', 'single_flight', 'release_before_new_connect'):
        require(assertions.get(name) is True, f'operator_assertion_missing_{name}')
    require(board.get('other_peers_preserved') is True, 'board_other_peer_evidence_missing')
    expected = case[6]
    allowed_ui = ('method_selection', 'manual_phone_forget_guidance') if expected == 'recovered_or_phone_forget_guidance' else (expected,)
    require(operator.get('final_ui') in allowed_ui, 'unexpected_final_ui')
    if case_id in (ASYMMETRIC - {'P06'}) or case_id in NEW_PAIR:
        require(operator.get('first_operation_succeeded') is True, 'second_click_success_not_accepted')
    bond = operator.get('phone_native_bond_state')
    require(bond in ('BOND_NONE', 'BOND_BONDED'), 'real_native_bond_baseline_required')
    if case_id in ASYMMETRIC:
        require(bond == 'BOND_NONE' and operator.get('board_paired_before') is True and operator.get('board_bonded_before') is True, 'asymmetric_baseline_mismatch')
    elif case_id in NEW_PAIR:
        require(bond == 'BOND_NONE' and operator.get('board_paired_before') is False and operator.get('board_bonded_before') is False, 'new_pair_baseline_mismatch')
    elif case_id in ('M07', 'P02'):
        require(bond == 'BOND_BONDED' and operator.get('board_bonded_before') is True, 'bonded_baseline_mismatch')
    elif case_id in ('M05', 'M06'):
        require(bond == 'BOND_BONDED' and operator.get('board_paired_before') is False and operator.get('board_bonded_before') is False, 'reverse_asymmetric_baseline_mismatch')
    if case_id in ('M08', 'M11', 'P05'):
        require(bond == 'BOND_NONE', 'unbound_native_baseline_required')
    actions = operator.get('user_actions')
    require(isinstance(actions, list) and len(actions) == (2 if case_id == 'M11' else 1), 'user_action_observation_missing')
    require(len({a['id'] for a in actions}) == len(actions), 'duplicate_user_action_id')
    if case_id == 'M11':
        require(actions[0].get('outcome') == 'failed' and actions[1].get('kind') == 'manual_retry' and actions[1].get('outcome') == 'succeeded', 'explicit_failed_then_manual_retry_required')
    if case_id == 'M10':
        require(type(actions[0].get('input_taps')) is int and actions[0]['input_taps'] >= 2, 'rapid_taps_not_observed')
    if case_id.startswith('M12-'):
        require(operator.get('wifi_state') == case_id.split('-')[1], 'wifi_environment_not_observed')
    dialogs = [a.get('pairing_dialogs') for a in actions]
    require(all(type(n) is int and n >= 0 for n in dialogs), 'human_dialog_count_required')
    rule = case[5]
    allowed = {'one': {1}, 'zero': {0}, 'zero_or_one': {0, 1}, 'per_action': {0, 1}, 'native_baseline': {0 if bond == 'BOND_BONDED' else 1}}[rule]
    require(all(n in allowed for n in dialogs), 'system_popup_count_mismatch')
    events = full['connection_events']
    check_release_completions(events)
    android = [e for e in events if e.get('source') == 'android']
    require(any(re.fullmatch(r'[a-f0-9]{64}', str(e.get('device_address_hash', ''))) for e in android), 'device_address_hash_missing')
    require(any('system_pairing_interaction' in e for e in android), 'pairing_interaction_fact_missing')
    require(any(e.get('event_type') == 'teardown_started' for e in events) and any(e.get('event_type') == 'teardown_completed' for e in events), 'teardown_timeline_missing')
    native_calls = [e for e in android if e.get('event_type') == 'create_bond_invoked']
    require(len(native_calls) <= len(actions), 'repeated_native_create_bond')
    require(all(type(e.get('create_bond_call_count')) is int and e['create_bond_call_count'] <= len(actions)
                for e in android if 'create_bond_call_count' in e), 'native_create_bond_counter_exceeded')
    require(all(type(e.get('connection_generation')) is int and bool(e.get('attempt_id')) for e in native_calls), 'native_attempt_correlation_missing')
    if rule == 'zero':
        require(not native_calls, 'unexpected_create_bond')
    if rule == 'one':
        require(len(native_calls) == 1, 'unique_create_bond_evidence_missing')
        require(any(e.get('event_type') == 'create_bond_returned' for e in android), 'create_bond_return_fact_missing')
        require(any(e.get('event_type') == 'bond_state_changed' for e in android), 'bond_state_timeline_missing')
        require(any(e.get('event_type') == 'create_bond_returned' and e.get('create_bond_returned') is True for e in android), 'create_bond_not_accepted')
        for event in android:
            if event.get('event_type') in ('create_bond_invoked', 'create_bond_returned', 'bond_state_changed'):
                require(datetime.fromisoformat(event['occurred_at']).tzinfo is not None, 'native_timeline_timestamp_missing')
            if event.get('event_type') == 'bond_state_changed':
                require(event.get('previous_bond_state') and (event.get('actual_bond_state') or event.get('bond_state')), 'bond_state_transition_missing')
    requests = [e for e in events if e.get('event_type') == 'pairing_preflight_request']
    if bond == 'BOND_BONDED':
        require(not requests, 'bonded_reconnect_used_preflight')
    if bond == 'BOND_NONE':
        require(bool(requests), 'public_preflight_evidence_missing')
        ready_indexes = [i for i, e in enumerate(events) if e.get('event_type') == 'pairing_preflight_result' and action_of(e) == 'none']
        first_ready = min(ready_indexes, default=len(events))
        require(not any(e.get('event_type') in ('security_write_api_invoked', 'security_write_begin') for e in events[:first_ready]), 'security_access_before_preflight_ready')
        if rule == 'one':
            ready = [e for e in events if e.get('event_type') == 'pairing_preflight_result' and action_of(e) == 'none']
            require(any(r.get('request_id') == q.get('request_id') for r in ready for q in requests if q.get('command_type') == 'prepare_system_pairing'), 'matching_public_ready_evidence_missing')
            require(any(events.index(r) < events.index(native_calls[0]) for r in ready), 'bonding_before_preflight_ready')
            require(operator.get('preflight_dialogs') == 0, 'early_system_dialog_observed')
        if rule == 'native_baseline':
            require(len(native_calls) == 1 and any(e.get('event_type') == 'pairing_preflight_result' and action_of(e) == 'none' for e in events), 'unbound_foreground_pairing_evidence_missing')
    if case_id in ASYMMETRIC:
        for name in ('device_id_revalidated', 'expected_disconnect_not_reported_as_failure'):
            require(assertions.get(name) is True, f'operator_assertion_missing_{name}')
        require(all(board.get(k) is True for k in ('advertising_recovered', 'ack_before_removal', 'same_peer_prepare_confirm')), 'board_reset_protocol_evidence_missing')
        prepares = [e for e in requests if e.get('command_type') == 'prepare_system_pairing']
        confirms = [e for e in requests if e.get('command_type') == 'confirm_pairing_reset']
        results = [e for e in events if e.get('event_type') == 'pairing_preflight_result']
        require(len(prepares) == 2 and len(confirms) == 1, 'prepare_confirm_fresh_sequence_missing')
        require(prepares[0].get('attempt_id') and len({e.get('attempt_id') for e in prepares + confirms}) == 1, 'preflight_logical_attempt_mismatch')
        require(len({e.get('request_id') for e in prepares + confirms}) == 3, 'preflight_request_ids_not_unique')
        for request, action in [(prepares[0], 'reset_required'), (confirms[0], 'remove_scheduled'), (prepares[1], 'none')]:
            require(any(r.get('request_id') == request.get('request_id') and action_of(r) == action for r in results), 'matching_preflight_response_missing')
        old, fresh = prepares[0].get('connection_generation'), prepares[1].get('connection_generation')
        require(type(old) is int and type(fresh) is int and fresh > old, 'fresh_generation_not_increased')
        require(any(e.get('event_type') == 'pairing_preflight_expected_disconnect' and e.get('connection_generation') == old for e in events), 'expected_disconnect_evidence_missing')
        # The diagnostic result is emitted after its Future resumes; an immediate
        # native disconnect can be logged first. Do not mistake log order for ACK order.
    if case_id in ('M09', 'P04'):
        require(assertions.get('native_gatt_sync_checked') is True, 'native_foreground_sync_unverified')
    if case_id == 'M11':
        require(assertions.get('late_callbacks_isolated') is True, 'old_callback_isolation_unverified')
    if case_id == 'P05':
        require(operator.get('preflight_dialogs') == 0 and not native_calls, 'preflight_disconnect_started_bonding')
    if case_id in ('P05', 'P06'):
        require(not any(e.get('event_type') in ('security_write_api_invoked', 'security_write_begin') for e in events), 'public_segment_accessed_security_write')
    require(operator.get('final_ui_error_code') not in ('StateError', 'invalid_request', 'link_lost'), 'bare_or_secondary_ui_error')
    if operator.get('final_ui_error_code') is not None:
        require(re.fullmatch(r'[A-Z][A-Z0-9_]{2,80}', str(operator['final_ui_error_code'])) is not None, 'stable_ui_error_code_required')
    if full.get('first_terminal_error') is not None:
        require(isinstance(full['first_terminal_error'], dict) and isinstance(full.get('secondary_errors'), list), 'structured_terminal_errors_missing')
        for fact in [full['first_terminal_error'], *full['secondary_errors']]:
            require(isinstance(fact, dict), 'error_fact_object_required')
            if fact.get('runtime_type') == 'StateError':
                require(all(fact.get(k) for k in ('to_string', 'stack_trace', 'trigger_method', 'attempt_id', 'expected_state', 'current_state')), 'state_error_context_missing')
    if operator['final_ui'] in ('cancellation_guidance', 'retryable_preflight_failure'):
        require(isinstance(operator.get('final_ui_error_code'), str) and operator['final_ui_error_code'], 'stable_ui_error_code_missing')
        require(isinstance(full.get('first_terminal_error'), dict), 'saved_first_terminal_error_missing')
        require(full['first_terminal_error'].get('error_code') == operator['final_ui_error_code'], 'ui_first_error_mismatch')
    build = round_record.get('build')
    require(isinstance(build, dict), 'formal_apk_not_registered')
    require(build.get('package_id') == 'deckers.thibault.aves.bird', 'formal_package_required')
    require(re.fullmatch(r'[a-f0-9]{40}', str(build.get('git_commit', ''))) is not None and re.fullmatch(r'[a-f0-9]{64}', str(build.get('source_fingerprint', ''))) is not None, 'frozen_source_identity_required')
    apk = artifact(root, build.get('apk'), json_file=False)
    require(apk.suffix.lower() == '.apk', 'formal_apk_required')
    metadata = artifact(root, build.get('metadata_evidence'), json_file=False).read_text(encoding='utf-8-sig')
    inspected = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", metadata)
    require(inspected is not None and inspected.groups() == (str(build.get('package_id')), str(build.get('version_code')), str(build.get('version_name'))), 'apk_metadata_mismatch')
    require(f'APK_SHA256={build["apk"]["sha256"]}' in metadata, 'apk_inspection_hash_binding_missing')
    observed_build = full.get('build') or {}
    require(isinstance(observed_build, dict), 'diagnostic_build_object_required')
    for key in ('package_id', 'version_name', 'version_code', 'git_commit', 'source_fingerprint', 'build_id'):
        require(build.get(key) is not None and str(build[key]) == str(observed_build.get(key)), f'build_identity_mismatch_{key}')
    return {'run_id': evidence['run_id'], 'case_id': case_id, 'phone': phone, 'phone_alias': operator['phone_alias'], 'iteration': iteration,
            'counts_for_acceptance': True, 'human_dialogs': sum(dialogs), 'native_create_bond_calls': len(native_calls),
            'trace_id': received['trace_id'], 'diagnostic_sha256': refs['diagnostic']['sha256'],
            'scope': 'recorded_human_observations_and_file_checks_require_joint_review'}


def summarize(root):
    root = Path(root).resolve()
    record = read(root / 'round.json')
    require(isinstance(record, dict), 'round_object_required')
    require(isinstance(record.get('deliverables'), dict) and isinstance(record.get('signoffs'), dict), 'delivery_objects_required')
    require(record.get('suite') == 'ble1019-v1', 'wrong_suite')
    reports, rejected, seen, traces, hashes = [], [], set(), set(), set()
    for path in sorted((root / 'runs').glob('*/evidence.json')):
        try:
            report = check_run(root, path)
            identity = (report['case_id'], report['phone'], report['iteration'])
            require(identity not in seen, 'duplicate_trial_identity')
            require(report['trace_id'] not in traces and report['diagnostic_sha256'] not in hashes, 'diagnostic_reused_across_trials')
            require(all(r['phone_alias'] == report['phone_alias'] for r in reports if r['phone'] == report['phone']), 'physical_phone_alias_changed')
            require(all(r['phone_alias'] != report['phone_alias'] for r in reports if r['phone'] != report['phone']), 'physical_phone_reused_for_another_model')
            seen.add(identity)
            traces.add(report['trace_id'])
            hashes.add(report['diagnostic_sha256'])
            reports.append(report)
        except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
            # Do not echo raw JSON, file contents, token-bearing exception text.
            rejected.append({'run_directory': path.parent.name, 'error': safe_error(error)})
    cells = []
    for cell in matrix():
        iterations = sorted(r['iteration'] for r in reports if r['case_id'] == cell['case_id'] and r['phone'] == cell['phone'])
        cells.append({**cell, 'accepted_iterations': iterations, 'status': 'evidence_ready_for_review' if iterations == list(range(1, cell['minimum_runs'] + 1)) else 'pending'})
    missing = []
    for name in DELIVERABLES:
        try:
            require(artifact(root, record.get('deliverables', {}).get(name), json_file=False).stat().st_size > 0, 'empty_deliverable')
        except (ValueError, KeyError, TypeError, OSError):
            missing.append(name)
    unsigned = []
    for name in SIGNOFFS:
        signoff = record.get('signoffs', {}).get(name)
        try:
            require(isinstance(signoff, dict) and signoff.get('confirmed') is True and signoff.get('reviewer_alias'), 'signoff_missing')
            artifact(root, signoff.get('evidence'), json_file=False)
        except (ValueError, KeyError, TypeError, OSError):
            unsigned.append(name)
    ready = all(c['status'] == 'evidence_ready_for_review' for c in cells) and not rejected and not missing and not unsigned
    return {'schema_version': 1, 'round_id': record['round_id'], 'matrix_cells': cells,
            'required_runs': sum(c['minimum_runs'] for c in cells), 'accepted_run_count': len(reports),
            'run_reports': reports, 'rejected_or_pending_runs': rejected, 'missing_deliverables': missing,
            'pending_signoffs': unsigned, 'ready_for_joint_review': ready, 'releasable': False,
            'hardware_status': 'recorded_evidence_pending_joint_review' if reports else 'not_verified',
            'note': '工具不代替双方代码审查、真机复核和最终交付批准；不根据离线测试或单个成功轮次放行。'}


def safe_error(error):
    value = str(error)
    return value if isinstance(error, ValueError) and re.fullmatch(r'[a-z0-9_]+', value) else type(error).__name__


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    init = commands.add_parser('init')
    init.add_argument('--round-id', required=True)
    init.add_argument('--output-root', default=str(REPO / 'outputs' / 'ble22'))
    new = commands.add_parser('new-run')
    new.add_argument('round')
    new.add_argument('--case', required=True, choices=CASE)
    new.add_argument('--phone', required=True, choices=PHONES)
    new.add_argument('--iteration', required=True, type=int)
    new.add_argument('--kind', required=True, choices=('real_phone_real_board', 'virtual_peripheral', 'offline_fixture'))
    check = commands.add_parser('check-run')
    check.add_argument('round')
    check.add_argument('evidence')
    summary = commands.add_parser('summarize')
    summary.add_argument('round')
    summary.add_argument('--require-ready', action='store_true')
    reference = commands.add_parser('reference')
    reference.add_argument('round')
    reference.add_argument('--file', required=True, help='Relative existing path inside this round')
    reference.add_argument('--sha256', required=True, help='Independently obtained expected digest')
    review = commands.add_parser('export-review')
    review.add_argument('round')
    review.add_argument('--label', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'init':
            result = {'created': str(initialize(args.output_root, args.round_id)), 'hardware_executed': False, 'releasable': False}
        elif args.command == 'new-run':
            result = {'created': str(new_run(args.round, args.case, args.phone, args.iteration, args.kind)), 'hardware_executed': False}
        elif args.command == 'check-run':
            result = check_run(args.round, args.evidence)
        elif args.command == 'reference':
            result = {'path': args.file, 'sha256': args.sha256}
            artifact(args.round, result, json_file=False)
        elif args.command == 'export-review':
            result = {'created': str(export_review(args.round, args.label)), 'releasable': False}
        else:
            result = summarize(args.round)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 2 if args.require_ready and not result['ready_for_joint_review'] else 0
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
        print(json.dumps({'ok': False, 'error': safe_error(error), 'releasable': False}))
        return 1


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.exit(main())
