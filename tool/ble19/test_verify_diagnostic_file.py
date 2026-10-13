import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from verify_diagnostic_file import verify


class ReceiverVerificationTest(unittest.TestCase):
    def setUp(self):
        workspace = Path(__file__).resolve().parents[2]
        temporary_root = workspace / "build" / "ble19" / "receiver-tests"
        temporary_root.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=temporary_root)
        # Check the recursive cleanup target remains within this test's workspace.
        Path(self.directory.name).resolve().relative_to(temporary_root.resolve())
        self.addCleanup(self.directory.cleanup)
        self.full = {
            "schema_version": 4, "trace_id": "synthetic-local", "generated_at": "2026-10-11",
            "build": {"evidence_kind": "synthetic_local_test"}, "exporting_app_build": {},
            "retained_records_complete": True, "raw_history_complete": True,
            "connection_events": [{"event_type": "create_bond_invoked", "source": "synthetic_local_test"}],
            "scan_sessions": [], "retention": {"connection_events": {
                "retained": 1, "critical_events_missing": False, "critical_history_unknown": False,
                "critical_observed": 1, "critical_retained": 1, "critical_dropped": 0, "critical_missing_reasons": [],
            }},
        }

    @staticmethod
    def encode(value):
        return json.dumps(value, ensure_ascii=False).encode("utf-8")

    def file(self, body, extension="json"):
        path = Path(self.directory.name) / f"received.{extension}"
        path.write_bytes(body)
        return path, hashlib.sha256(body).hexdigest()

    def zip(self, full=None, summary_change=None, payload_hash=None, extra=False):
        full = self.full if full is None else full
        payload = self.encode(full)
        summary = {key: copy.deepcopy(full[key]) for key in ("trace_id", "generated_at", "build", "retention", "exporting_app_build")}
        summary.update(export_kind="summary", full_record_included=False, retained_event_count=len(full["connection_events"]))
        if summary_change:
            summary.update(summary_change)
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("full_trace.json", payload)
            archive.writestr("summary.json", self.encode(summary))
            archive.writestr("README.txt", "payload SHA-256: " + (payload_hash or hashlib.sha256(payload).hexdigest()))
            if extra:
                archive.writestr("unexpected.txt", "extra")
        return self.file(output.getvalue(), "zip")

    def test_valid_json_and_zip_have_independent_file_and_payload_hashes(self):
        json_report = verify(*self.file(self.encode(self.full)))
        self.assertEqual(json_report["file_sha256"], json_report["payload_sha256"])
        zip_report = verify(*self.zip())
        self.assertNotEqual(zip_report["file_sha256"], zip_report["payload_sha256"])
        self.assertEqual(["synthetic_local_test"], zip_report["evidence_sources"])

    def test_receiver_rejects_final_file_corruption(self):
        path, digest = self.file(self.encode(self.full))
        path.write_bytes(path.read_bytes() + b" ")
        with self.assertRaisesRegex(ValueError, "file_sha256_mismatch"):
            verify(path, digest)

    def test_receiver_rejects_archive_with_wrong_payload_hash(self):
        with self.assertRaisesRegex(ValueError, "readme_payload_sha256_mismatch"):
            verify(*self.zip(payload_hash="0" * 64))

    def test_receiver_rejects_inconsistent_summary_or_extra_entries(self):
        with self.assertRaisesRegex(ValueError, "summary_identity_mismatch"):
            verify(*self.zip(summary_change={"trace_id": "other"}))
        with self.assertRaisesRegex(ValueError, "summary_count_mismatch"):
            verify(*self.zip(summary_change={"retained_event_count": 20}))
        with self.assertRaisesRegex(ValueError, "invalid_zip_entries"):
            verify(*self.zip(extra=True))

    def test_receiver_reports_critical_loss_and_unknown_history_without_claiming_completeness(self):
        retention = self.full["retention"]["connection_events"]
        retention.update(critical_observed=2, critical_dropped=1, critical_events_missing=True,
                         critical_missing_reasons=["byte_capacity"])
        report = verify(*self.zip())
        self.assertTrue(report["verified"])
        self.assertTrue(report["critical_events_missing"])
        retention.update(critical_history_unknown=True, critical_observed=None)
        self.assertTrue(verify(*self.zip())["critical_events_missing"])

    def test_receiver_rejects_count_or_loss_status_inconsistency(self):
        retention = self.full["retention"]["connection_events"]
        retention["critical_observed"] = 2
        with self.assertRaisesRegex(ValueError, "critical_count_mismatch"):
            verify(*self.file(self.encode(self.full)))
        retention["critical_observed"] = 1
        retention["critical_events_missing"] = True
        with self.assertRaisesRegex(ValueError, "critical_loss_status_mismatch"):
            retention["critical_missing_reasons"] = ["synthetic_invalid_status"]
            verify(*self.file(self.encode(self.full)))

    def test_unknown_critical_history_cannot_claim_intact_or_omit_loss_reason(self):
        retention = self.full["retention"]["connection_events"]
        retention["critical_history_unknown"] = True
        with self.assertRaisesRegex(ValueError, "critical_loss_status_mismatch"):
            verify(*self.file(self.encode(self.full)))
        retention["critical_events_missing"] = True
        with self.assertRaisesRegex(ValueError, "critical_loss_reason_missing"):
            verify(*self.file(self.encode(self.full)))

    def test_receiver_rejects_malformed_retention_and_missing_full_records(self):
        self.full["retention"] = []
        with self.assertRaisesRegex(ValueError, "invalid_retention"):
            verify(*self.file(self.encode(self.full)))
        self.full["retained_records_complete"] = False
        with self.assertRaisesRegex(ValueError, "missing_retained_records"):
            verify(*self.file(self.encode(self.full)))


if __name__ == "__main__":
    unittest.main()
