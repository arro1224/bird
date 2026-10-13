"""Offline file/summary checks. These fixtures are not physical-phone evidence."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from summarize import summarize
from verify_received import verify_round
from verify_pairing_stop import verify_stop


class ToolsTests(unittest.TestCase):
    def setUp(self):
        self.base = (Path(__file__).resolve().parents[2] / 'build').resolve()
        self.temp = tempfile.TemporaryDirectory(prefix='ble22-tools-', dir=self.base)
        self.root = Path(self.temp.name).resolve()
        self.run = self.root / 'run'
        self.run.mkdir()

    def tearDown(self):
        assert self.root.parent == self.base and self.root.name.startswith('ble22-tools-')
        self.temp.cleanup()

    def artifact(self):
        full = {'schema_version': 4, 'trace_id': 'offline-fixture', 'connection_events': [], 'scan_sessions': [],
                'retained_records_complete': True, 'retention': {'connection_events': {'retained': 0,
                'critical_events_missing': False, 'critical_history_unknown': False, 'critical_missing_reasons': [],
                'critical_observed': 0, 'critical_retained': 0, 'critical_dropped': 0}}}
        data = json.dumps(full).encode('utf-8')
        (self.run / 'fixture.json').write_bytes(data)
        sha = hashlib.sha256(data).hexdigest()
        evidence = {'run_id': 'offline-fixture', 'role': 'P2', 'scenario': 'bond_first', 'test_exit_code': 1,
                    'run_status': 'test_failed', 'export': {'file_name': 'fixture.json', 'sha256': sha, 'payload_sha256': sha, 'bytes': len(data)}}
        self.save(evidence)
        return evidence

    def save(self, evidence):
        (self.run / 'evidence.json').write_text(json.dumps(evidence), encoding='utf-8')

    def test_failed_run_file_integrity_is_separate_from_acceptance(self):
        self.artifact()
        result = verify_round(self.root)
        self.assertTrue(result['verified'])
        self.assertEqual(result['reports'][0]['run_status'], 'test_failed')

    def test_no_export_is_not_a_verified_receive(self):
        self.save({'export': None})
        result = verify_round(self.root)
        self.assertFalse(result['verified'])
        self.assertEqual(len(result['skipped']), 1)

    def test_final_file_hash_mismatch(self):
        self.artifact()
        (self.run / 'fixture.json').write_bytes(b'altered')
        self.assertEqual(verify_round(self.root)['failures'][0]['error'], 'file_sha256_mismatch')

    def test_payload_hash_mismatch(self):
        evidence = self.artifact()
        evidence['export']['payload_sha256'] = 'f' * 64
        self.save(evidence)
        self.assertEqual(verify_round(self.root)['failures'][0]['error'], 'app_payload_sha256_mismatch')

    def test_length_mismatch(self):
        evidence = self.artifact()
        evidence['export']['bytes'] += 1
        self.save(evidence)
        self.assertEqual(verify_round(self.root)['failures'][0]['error'], 'app_file_length_mismatch')

    def test_path_escape_rejected(self):
        evidence = self.artifact()
        evidence['export']['file_name'] = '../fixture.json'
        self.save(evidence)
        self.assertEqual(verify_round(self.root)['failures'][0]['error'], 'invalid_export_filename')

    def test_summary_preserves_pause_and_closes_hardware_gate(self):
        result = summarize(self.root, {'acceptance_status': 'paused_by_user', 'handoff_readiness': 'blocked', 'current_round': 'old', 'releasable': True})
        self.assertEqual(result['acceptance_status'], 'paused_by_user')
        self.assertEqual(result['current_round'], 'old')
        self.assertFalse(result['releasable'])
        self.assertEqual(result['hardware_status'], 'pending')

    def test_old_validation_log_cannot_hide_runner_failure(self):
        directory = self.root / 'ble22-fixture'
        directory.mkdir()
        (directory / 'builds.json').write_text('{}', encoding='utf-8')
        self.run.rename(directory / 'run')
        self.run = directory / 'run'
        self.save({'run_id': 'offline', 'role': 'P1', 'scenario': 'bond_first', 'test_exit_code': 0, 'run_status': 'cleanup_failed'})
        (self.run / 'validation.log').write_text('Virtual BirdBox evidence passed', encoding='utf-8')
        self.assertEqual(summarize(self.root)['rounds'][0]['runs'][0]['validation'], 'failed_or_pending')


class PairingStopTests(unittest.TestCase):
    def fixture(self, mode='Cancel'):
        outcome, code, action = ('bond_rejected', 'BLE_PAIRING_REJECTED', 'test_pairing_cancelled') if mode == 'Cancel' else ('bond_timeout', 'BLE_PAIRING_TIMEOUT', 'owned_pairing_intentionally_left_for_timeout')
        events = [dict(event_type='user_start_pairing', bond_state='not_bonded'),
                  dict(event_type='create_bond_invoked'), dict(event_type='create_bond_returned', create_bond_returned=True),
                  dict(event_type='security_write_fact_finalized', terminal_outcome=outcome, cleanup_outcome='complete',
                       create_bond_call_count=1, att_write_call_count=0, command_attempt_count=0,
                       attempt_id='offline-attempt', connection_generation=1, bond_elapsed_ms=30033)]
        for event in events:
            event.update(source='android', request_id='offline-request')
        evidence = dict(run_id='offline-run', scenario='bond_first', pairing_expected_outcome=mode,
                        test_invoked=True, test_exit_code=1, run_status='test_failed', hardware_status='pending',
                        export_received=True, cleanup={'errors': []},
                        phones={'app': {'physical_device_alias': 'app-physical', 'adb_selector_alias': 'app-selector'}, 'box': {'physical_device_alias': 'box-physical'}},
                        builds={'app': {'apk_sha256': 'a'*64, 'installed_verified': True}, 'box': {'installed_verified': True}},
                        app_evidence=dict(scenario='bond_first', initial_bond_state='not_bonded', failure_code=code,
                                          response_type=None, request_id='offline-request', events=events, build={'apk_sha256': 'a'*64}))
        actions = [dict(run_id='offline-run', adb_selector_alias='app-selector', pair_mode=mode,
                        decision={'action': action} if mode == 'Cancel' else {'action': 'none', 'reason': action})]
        return evidence, actions

    def test_cancel_preserves_raw_failure_and_never_counts_normal_success(self):
        evidence, actions = self.fixture()
        result = verify_stop(evidence, actions)
        self.assertEqual(result['status'], 'passed_expected_stop')
        self.assertEqual(evidence['test_exit_code'], 1)
        self.assertEqual(evidence['run_status'], 'test_failed')
        self.assertFalse(result['counts_as_normal_success'])

    def test_timeout_requires_actual_bounded_native_terminal(self):
        evidence, actions = self.fixture('Timeout')
        self.assertEqual(verify_stop(evidence, actions)['status'], 'passed_expected_stop')
        evidence['app_evidence']['events'][-1]['bond_elapsed_ms'] = 2000
        self.assertIn('timeout_not_bounded_near_30_seconds', verify_stop(evidence, actions)['errors'])

    def test_operator_action_from_another_run_is_rejected(self):
        evidence, actions = self.fixture()
        actions[0]['run_id'] = 'old-run'
        self.assertIn('actual_owned_operator_action_missing', verify_stop(evidence, actions)['errors'])

    def test_unknown_ui_blocks_specialized_pass(self):
        evidence, actions = self.fixture()
        actions.append({'run_id': 'offline-run', 'decision': {'action': 'blocked'}})
        self.assertIn('unknown_or_blocked_ui', verify_stop(evidence, actions)['errors'])

    def test_protected_write_or_success_cannot_count_as_pairing_stop(self):
        evidence, actions = self.fixture()
        evidence['app_evidence']['events'].append({'event_type': 'security_write_api_invoked'})
        evidence['app_evidence']['response_type'] = 'pairing_opened'
        self.assertEqual(verify_stop(evidence, actions)['status'], 'failed_or_incomplete')

    def test_interrupted_device_and_missing_export_are_incomplete(self):
        evidence, actions = self.fixture()
        evidence['run_status'] = 'startup_failed'
        evidence['export_received'] = False
        self.assertEqual(verify_stop(evidence, actions)['status'], 'failed_or_incomplete')

    def test_same_physical_phone_and_unverified_build_are_rejected(self):
        evidence, actions = self.fixture()
        evidence['phones']['box']['physical_device_alias'] = 'app-physical'
        evidence['builds']['box']['installed_verified'] = False
        result = verify_stop(evidence, actions)
        self.assertIn('two_physical_phone_identities_required', result['errors'])
        self.assertIn('actual_build_identity_missing', result['errors'])


if __name__ == '__main__':
    unittest.main()
