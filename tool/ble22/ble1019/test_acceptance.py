"""Synthetic offline fixtures only; no physical acceptance is executed."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import acceptance as a


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        base = a.REPO / 'build'
        base.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='ble1019-tools-', dir=base)
        self.parent = Path(self.temp.name).resolve()
        assert self.parent.is_relative_to(base.resolve())
        self.root = a.initialize(self.parent, 'ble1019-offline-fixture')
        self.build = {'package_id': 'deckers.thibault.aves.bird', 'version_name': 'test', 'version_code': 1,
                      'git_commit': 'a' * 40, 'source_fingerprint': 'b' * 64, 'build_id': 'SYNTHETIC-ONLY'}

    def tearDown(self):
        assert self.parent.is_relative_to((a.REPO / 'build').resolve()) and self.parent.name.startswith('ble1019-tools-')
        self.temp.cleanup()

    def put(self, name, value, *, raw=False):
        path = self.root / name
        path.write_bytes(value if raw else json.dumps(value).encode())
        return {'path': name, 'sha256': a.sha(path)}

    def save(self, path, value):
        path.write_text(json.dumps(value), encoding='utf-8')

    def fixture(self, case='P03', phone='huawei_mis_al00', iteration=1):
        run = a.new_run(self.root, case, phone, iteration, 'real_phone_real_board')
        evidence = a.read(run / 'evidence.json')
        run_id = evidence['run_id']
        # These values simulate a physical record to exercise validation. The
        # test suite itself never exports them as real evidence.
        common = {'source': 'dart', 'trace_id': 'synthetic-only', 'attempt_id': 'preflight-attempt', 'occurred_at': '2026-10-20T08:00:00+00:00'}
        events = [
            {**common, 'event_type': 'pairing_preflight_request', 'command_type': 'prepare_system_pairing', 'request_id': 'prepare', 'connection_generation': 1},
            {**common, 'event_type': 'pairing_preflight_result', 'request_id': 'prepare', 'result_code': 'reset_required'},
            {**common, 'event_type': 'pairing_preflight_request', 'command_type': 'confirm_pairing_reset', 'request_id': 'confirm', 'connection_generation': 1},
            # Real Dart logs may put the synchronous disconnect before the
            # resumed confirmation result. This ordering must remain valid.
            {**common, 'event_type': 'pairing_preflight_expected_disconnect', 'connection_generation': 1},
            {**common, 'event_type': 'pairing_preflight_result', 'request_id': 'confirm', 'result_code': 'remove_scheduled'},
            {**common, 'event_type': 'pairing_preflight_request', 'command_type': 'prepare_system_pairing', 'request_id': 'fresh', 'connection_generation': 2},
            {**common, 'event_type': 'pairing_preflight_result', 'request_id': 'fresh', 'result_code': 'none'},
            {**common, 'source': 'android', 'event_type': 'create_bond_invoked', 'attempt_id': 'native', 'connection_generation': 2, 'device_address_hash': 'c' * 64, 'system_pairing_interaction': True},
            {**common, 'source': 'android', 'event_type': 'create_bond_returned', 'create_bond_returned': True},
            {**common, 'source': 'android', 'event_type': 'bond_state_changed', 'previous_bond_state': 'not_bonded', 'actual_bond_state': 'bonding'},
            {**common, 'event_type': 'teardown_started'},
            {**common, 'event_type': 'teardown_completed'},
        ]
        if case == 'P06':
            events = [e for e in events if e['event_type'] not in ('create_bond_invoked', 'create_bond_returned', 'bond_state_changed')]
            events.append({**common, 'source': 'android', 'event_type': 'gatt_connection_state_changed', 'device_address_hash': 'c' * 64, 'system_pairing_interaction': False})
        full = {'schema_version': 4, 'trace_id': 'synthetic-only', 'connection_events': events, 'scan_sessions': [],
                'build': self.build, 'retained_records_complete': True, 'raw_history_complete': False,
                'retention': {'connection_events': {'retained': len(events), 'critical_events_missing': False,
                    'critical_history_unknown': False, 'critical_missing_reasons': [], 'critical_observed': len(events),
                    'critical_retained': len(events), 'critical_dropped': 0}}}
        prefix = f'runs/{run_id}/'
        evidence['artifacts']['diagnostic'] = self.put(prefix + 'diagnostic.json', full)
        operator = a.read(run / 'operator.template.json')
        operator.update(observer_alias='OFFLINE-TEST', observed_at='2026-10-20T08:00:00+00:00', phone_sdk_int=30,
                        phone_alias='synthetic-phone', prepared_scenario_verified=True, phone_native_bond_state='BOND_NONE',
                        board_paired_before=True, board_bonded_before=True, final_ui=a.CASE[case][6],
                        first_operation_succeeded=True, both_sides_forget_required=False, preflight_dialogs=0,
                        user_actions=[{'id': 'click-1', 'pairing_dialogs': 0 if case == 'P06' else 1}])
        operator['assertions'] = {k: True for k in operator['assertions']}
        evidence['artifacts']['operator'] = self.put(prefix + 'operator.json', operator)
        log_ref = self.put(prefix + 'board.log', b'OFFLINE SYNTHETIC observation fixture, no hardware\n', raw=True)
        evidence['artifacts']['board_log'] = log_ref
        evidence['artifacts']['board'] = self.put(prefix + 'board.json', {
            'run_id': run_id, 'observer_alias': 'OFFLINE-TEST', 'observed_at': '2026-10-20T08:00:00+00:00',
            'source_log_sha256': log_ref['sha256'], 'other_peers_preserved': True, 'advertising_recovered': True,
            'phone_alias': 'synthetic-phone', 'paired_before': True, 'bonded_before': True,
            'ack_before_removal': True, 'same_peer_prepare_confirm': True})
        evidence['status'] = 'observed'
        self.save(run / 'evidence.json', evidence)
        record = a.read(self.root / 'round.json')
        apk = self.put('artifacts/synthetic.apk', b'SYNTHETIC APK BYTES ONLY', raw=True)
        record['build'] = {**self.build, 'apk': apk,
                           'metadata_evidence': self.put('artifacts/apk-metadata.log', ("SYNTHETIC METADATA ONLY\npackage: name='deckers.thibault.aves.bird' versionCode='1' versionName='test'\nAPK_SHA256=" + apk['sha256']).encode(), raw=True)}
        self.save(self.root / 'round.json', record)
        return run / 'evidence.json', full, evidence

    def mutate_trace(self, path, full, evidence):
        full['retention']['connection_events'].update(retained=len(full['connection_events']), critical_observed=len(full['connection_events']), critical_retained=len(full['connection_events']))
        reference = evidence['artifacts']['diagnostic']
        evidence['artifacts']['diagnostic'] = self.put(reference['path'], full)
        self.save(path, evidence)

    def mutate_operator(self, path, evidence, **changes):
        ref = evidence['artifacts']['operator']
        operator = a.read(self.root / ref['path'])
        operator.update(changes)
        evidence['artifacts']['operator'] = self.put(ref['path'], operator)
        self.save(path, evidence)

    def test_initial_matrix_has_all_requirements_and_never_counts_unrun_hardware(self):
        summary = a.summarize(self.root)
        self.assertEqual({c['requirement'] for c in summary['matrix_cells']},
                         {f'main-6.{i}' for i in range(1, 13)} | {f'increment-8.{i}' for i in range(1, 7)})
        self.assertEqual(summary['required_runs'], 264)
        self.assertEqual(len(summary['matrix_cells']), 51)
        self.assertEqual(summary['accepted_run_count'], 0)
        self.assertFalse(summary['ready_for_joint_review'])
        self.assertFalse(summary['releasable'])

    def test_round_and_run_creation_never_overwrite_existing_evidence(self):
        with self.assertRaises(FileExistsError):
            a.initialize(self.parent, 'ble1019-offline-fixture')
        a.new_run(self.root, 'P03', 'huawei_mis_al00', 1, 'offline_fixture')
        with self.assertRaises(FileExistsError):
            a.new_run(self.root, 'P03', 'huawei_mis_al00', 1, 'offline_fixture')

    def test_review_bundle_includes_untracked_source_and_never_overwrites_a_previous_bundle(self):
        review = a.export_review(self.root, 'synthetic-review')
        manifest = a.read(review / 'manifest.json')
        self.assertEqual(manifest['patch_sha256'], a.sha(review / 'changes.patch'))
        self.assertFalse(manifest['releasable'])
        self.assertFalse(manifest['release_build_fingerprint'])
        self.assertIn('diff --git ', (review / 'changes.patch').read_text(encoding='utf-8'))
        with self.assertRaises(FileExistsError):
            a.export_review(self.root, 'synthetic-review')

    def test_valid_synthetic_protocol_record_is_checkable_but_one_run_never_releases_round(self):
        path, _, _ = self.fixture()
        result = a.check_run(self.root, path)
        self.assertEqual(result['human_dialogs'], 1)
        self.assertEqual(result['native_create_bond_calls'], 1)
        summary = a.summarize(self.root)
        self.assertEqual(summary['accepted_run_count'], 1)
        self.assertFalse(summary['ready_for_joint_review'])
        self.assertFalse(summary['releasable'])

    def test_post_ack_disconnect_segment_has_zero_dialogs_even_before_later_user_pairing(self):
        path, _, _ = self.fixture('P06')
        self.assertEqual(a.check_run(self.root, path)['human_dialogs'], 0)

    def test_virtual_and_offline_evidence_cannot_count_as_real_board_acceptance(self):
        path, _, evidence = self.fixture()
        for kind in ('virtual_peripheral', 'offline_fixture'):
            evidence['evidence_kind'] = kind
            self.save(path, evidence)
            with self.assertRaisesRegex(ValueError, 'nonphysical_evidence'):
                a.check_run(self.root, path)

    def test_system_dialogs_are_not_inferred_from_one_native_call(self):
        path, _, evidence = self.fixture()
        self.mutate_operator(path, evidence, user_actions=[{'id': 'click', 'pairing_dialogs': 2}])
        with self.assertRaisesRegex(ValueError, 'system_popup_count_mismatch'):
            a.check_run(self.root, path)

    def test_second_click_success_is_not_a_first_operation_pass(self):
        path, _, evidence = self.fixture()
        self.mutate_operator(path, evidence, first_operation_succeeded=False)
        with self.assertRaisesRegex(ValueError, 'second_click_success'):
            a.check_run(self.root, path)

    def test_manual_double_forget_and_wrong_phone_model_rejected(self):
        path, _, evidence = self.fixture()
        self.mutate_operator(path, evidence, both_sides_forget_required=True)
        with self.assertRaisesRegex(ValueError, 'manual_double_forget'):
            a.check_run(self.root, path)
        self.mutate_operator(path, evidence, both_sides_forget_required=False, phone_model='FIN-AL60')
        with self.assertRaisesRegex(ValueError, 'phone_model_mismatch'):
            a.check_run(self.root, path)

    def test_hash_tamper_and_external_artifact_reference_rejected(self):
        path, _, evidence = self.fixture()
        outside = self.parent / 'outside.json'
        outside.write_text('{}')
        evidence['artifacts']['operator'] = {'path': '../outside.json', 'sha256': a.sha(outside)}
        self.save(path, evidence)
        with self.assertRaisesRegex(ValueError, 'artifact_outside_round'):
            a.check_run(self.root, path)
        evidence['artifacts']['operator'] = {'path': 'round.json', 'sha256': '0' * 64}
        self.save(path, evidence)
        with self.assertRaisesRegex(ValueError, 'sha256_mismatch'):
            a.check_run(self.root, path)

    def test_secret_field_secret_hash_and_full_mac_fail_without_echoing_values(self):
        for value in ({'reset_token': 'PRIVATE'}, {'reset_token_hash': 'd' * 64}, {'password': 'PRIVATE'}, 'address AA:BB:CC:DD:EE:FF', 'access_token=PRIVATE'):
            with self.assertRaises(ValueError) as raised:
                a.privacy(value)
            self.assertNotIn('PRIVATE', a.safe_error(raised.exception))
        a.privacy({'device_address_hash': 'c' * 64, 'to_string': 'StateError(<redacted>)'})

    def test_truncated_critical_trace_is_rejected(self):
        path, full, evidence = self.fixture()
        retention = full['retention']['connection_events']
        retention.update(critical_events_missing=True, critical_dropped=1, critical_missing_reasons=['critical_event_capacity'], critical_observed=len(full['connection_events']) + 1)
        evidence['artifacts']['diagnostic'] = self.put(evidence['artifacts']['diagnostic']['path'], full)
        self.save(path, evidence)
        with self.assertRaisesRegex(ValueError, 'critical_events_missing'):
            a.check_run(self.root, path)

    def test_request_mismatch_and_unchanged_generation_fail(self):
        path, full, evidence = self.fixture()
        original = copy.deepcopy(full)
        full['connection_events'][4]['request_id'] = 'foreign'
        self.mutate_trace(path, full, evidence)
        with self.assertRaisesRegex(ValueError, 'matching_preflight_response_missing'):
            a.check_run(self.root, path)
        original['connection_events'][5]['connection_generation'] = 1
        self.mutate_trace(path, original, evidence)
        with self.assertRaisesRegex(ValueError, 'fresh_generation_not_increased'):
            a.check_run(self.root, path)

    def test_missing_board_ack_and_native_create_bond_duplicate_fail(self):
        path, full, evidence = self.fixture()
        original = copy.deepcopy(full)
        full['connection_events'].append(copy.deepcopy(full['connection_events'][7]))
        self.mutate_trace(path, full, evidence)
        with self.assertRaisesRegex(ValueError, 'repeated_native_create_bond'):
            a.check_run(self.root, path)
        self.mutate_trace(path, original, evidence)
        ref = evidence['artifacts']['board']
        board = a.read(self.root / ref['path'])
        board['ack_before_removal'] = False
        evidence['artifacts']['board'] = self.put(ref['path'], board)
        self.save(path, evidence)
        with self.assertRaisesRegex(ValueError, 'board_reset_protocol_evidence_missing'):
            a.check_run(self.root, path)

    def test_build_mismatch_and_missing_apk_prevent_acceptance(self):
        path, full, evidence = self.fixture()
        full['build'] = {**full['build'], 'build_id': 'different'}
        self.mutate_trace(path, full, evidence)
        with self.assertRaisesRegex(ValueError, 'build_identity_mismatch_build_id'):
            a.check_run(self.root, path)
        record = a.read(self.root / 'round.json')
        record['build'] = None
        self.save(self.root / 'round.json', record)
        with self.assertRaisesRegex(ValueError, 'formal_apk_not_registered'):
            a.check_run(self.root, path)

    def test_reusing_one_diagnostic_cannot_fill_a_second_iteration(self):
        self.fixture()
        self.fixture(iteration=2)
        summary = a.summarize(self.root)
        self.assertEqual(summary['accepted_run_count'], 1)
        self.assertEqual(summary['rejected_or_pending_runs'][0]['error'], 'diagnostic_reused_across_trials')

    def test_not_started_or_pending_records_never_count(self):
        a.new_run(self.root, 'P03', 'huawei_mis_al00', 1, 'real_phone_real_board')
        summary = a.summarize(self.root)
        self.assertEqual(summary['accepted_run_count'], 0)
        self.assertEqual(summary['rejected_or_pending_runs'][0]['error'], 'run_not_observed')

    def test_incorrect_case_phone_and_out_of_range_iterations_fail_before_creating_run(self):
        with self.assertRaisesRegex(ValueError, 'case_phone_mismatch'):
            a.new_run(self.root, 'M02', 'oppo_pkc110', 1, 'real_phone_real_board')
        with self.assertRaisesRegex(ValueError, 'iteration_out_of_range'):
            a.new_run(self.root, 'P03', 'huawei_mis_al00', 6, 'real_phone_real_board')

    def test_malformed_exception_details_are_never_echoed(self):
        self.assertEqual(a.safe_error(ValueError('reset_token=PRIVATE')), 'ValueError')
        self.assertEqual(a.safe_error(KeyError('PRIVATE')), 'KeyError')

    def test_malformed_evidence_or_observation_json_fails_cleanly(self):
        path, _, evidence = self.fixture()
        ref = evidence['artifacts']['operator']
        evidence['artifacts']['operator'] = self.put(ref['path'], False)
        self.save(path, evidence)
        with self.assertRaisesRegex(ValueError, 'observation_object_required'):
            a.check_run(self.root, path)
        self.save(path, [])
        summary = a.summarize(self.root)
        self.assertEqual(summary['accepted_run_count'], 0)
        self.assertEqual(summary['rejected_or_pending_runs'][0]['error'], 'evidence_object_required')

    def test_early_security_access_and_reported_native_counter_are_not_hidden_by_one_event(self):
        path, full, evidence = self.fixture()
        original = copy.deepcopy(full)
        full['connection_events'].insert(0, {'source': 'android', 'event_type': 'security_write_api_invoked'})
        self.mutate_trace(path, full, evidence)
        with self.assertRaisesRegex(ValueError, 'security_access_before_preflight_ready'):
            a.check_run(self.root, path)
        original['connection_events'][7]['create_bond_call_count'] = 2
        self.mutate_trace(path, original, evidence)
        with self.assertRaisesRegex(ValueError, 'native_create_bond_counter_exceeded'):
            a.check_run(self.root, path)

    def test_json_zip_integrity_uses_existing_receiver_checks(self):
        path, full, evidence = self.fixture()
        ref = evidence['artifacts']['diagnostic']
        payload = (self.root / ref['path']).read_bytes()
        zipped = self.root / ref['path'].replace('.json', '.zip')
        with zipfile.ZipFile(zipped, 'w') as archive:
            archive.writestr('full_trace.json', payload)
            archive.writestr('summary.json', json.dumps({'export_kind': 'summary', 'full_record_included': False,
                'trace_id': full['trace_id'], 'build': full['build'], 'retention': full['retention'], 'retained_event_count': len(full['connection_events'])}))
            archive.writestr('README.txt', a.sha(self.root / ref['path']))
        evidence['artifacts']['diagnostic'] = {'path': str(zipped.relative_to(self.root)), 'sha256': a.sha(zipped)}
        self.save(path, evidence)
        self.assertTrue(a.check_run(self.root, path)['counts_for_acceptance'])


if __name__ == '__main__':
    unittest.main()
