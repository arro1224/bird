"""Receiver-side BLE JSON/ZIP verification. Uses Python's standard library only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

MAX_PAYLOAD_BYTES = 32 * 1024 * 1024


def verify(path, expected_sha256):
    path = Path(path)
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected_sha256):
        raise ValueError("invalid_expected_file_sha256")
    if path.stat().st_size > MAX_PAYLOAD_BYTES + 64 * 1024:
        raise ValueError("file_too_large")
    received = path.read_bytes()
    file_sha = hashlib.sha256(received).hexdigest()
    if file_sha != expected_sha256.lower():
        raise ValueError("file_sha256_mismatch")
    summary = None
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != 3 or set(names) != {"summary.json", "full_trace.json", "README.txt"}:
                raise ValueError("invalid_zip_entries")
            limits = {"full_trace.json": MAX_PAYLOAD_BYTES, "summary.json": 16 * 1024, "README.txt": 16 * 1024}
            for name, limit in limits.items():
                if archive.getinfo(name).flag_bits & 1:
                    raise ValueError("encrypted_zip_entry")
                if archive.getinfo(name).file_size > limit:
                    raise ValueError("zip_entry_too_large")
            payload = archive.read("full_trace.json")
            summary = json.loads(archive.read("summary.json").decode("utf-8"))
            readme = archive.read("README.txt").decode("utf-8")
        payload_sha = hashlib.sha256(payload).hexdigest()
        if re.findall(r"[a-fA-F0-9]{64}", readme) != [payload_sha]:
            raise ValueError("readme_payload_sha256_mismatch")
    elif path.suffix.lower() == ".json":
        payload = received
        payload_sha = file_sha
    else:
        raise ValueError("unsupported_file_type")
    full = json.loads(payload.decode("utf-8"))
    if not isinstance(full, dict) or full.get("schema_version") != 4 or not isinstance(full.get("trace_id"), str):
        raise ValueError("invalid_full_trace")
    events, scans = full.get("connection_events"), full.get("scan_sessions")
    if not isinstance(events, list) or not isinstance(scans, list) or full.get("retained_records_complete") is not True:
        raise ValueError("missing_retained_records")
    if not all(isinstance(record, dict) for record in events + scans):
        raise ValueError("invalid_record")
    if summary is not None:
        if not isinstance(summary, dict) or summary.get("export_kind") != "summary" or summary.get("full_record_included") is not False:
            raise ValueError("invalid_summary")
        for key in ("trace_id", "generated_at", "build", "retention", "exporting_app_build"):
            if summary.get(key) != full.get(key):
                raise ValueError("summary_identity_mismatch")
        if summary.get("retained_event_count") != len(events):
            raise ValueError("summary_count_mismatch")
    retention_root = full.get("retention")
    if not isinstance(retention_root, dict) or not isinstance(retention_root.get("connection_events"), dict):
        raise ValueError("invalid_retention")
    retention = retention_root["connection_events"]
    if retention.get("retained") != len(events):
        raise ValueError("retention_count_mismatch")
    missing = retention.get("critical_events_missing")
    if missing not in (True, False) or not isinstance(missing, bool):
        raise ValueError("critical_history_status_missing")
    unknown = retention.get("critical_history_unknown")
    if not isinstance(unknown, bool):
        raise ValueError("critical_history_status_missing")
    reasons = retention.get("critical_missing_reasons")
    if not isinstance(reasons, list) or not all(isinstance(reason, str) for reason in reasons) or (missing and not reasons):
        raise ValueError("critical_loss_reason_missing")
    if unknown and not missing:
        raise ValueError("critical_loss_status_mismatch")
    observed, kept, dropped = (retention.get(name) for name in ("critical_observed", "critical_retained", "critical_dropped"))
    if not unknown:
        if any(type(value) is not int or value < 0 for value in (observed, kept, dropped)) or observed != kept + dropped or kept > len(events):
            raise ValueError("critical_count_mismatch")
        if missing != (dropped > 0):
            raise ValueError("critical_loss_status_mismatch")
    return {
        "verified": True, "file_name": path.name, "bytes": len(received),
        "file_sha256": file_sha, "payload_sha256": payload_sha,
        "trace_id": full["trace_id"], "retained_events": len(events), "retained_scans": len(scans),
        "critical_events_missing": missing, "critical_missing_reasons": retention.get("critical_missing_reasons", []),
        "critical_history_unknown": unknown,
        "raw_history_complete": full.get("raw_history_complete"),
        "evidence_sources": sorted({record.get("source", "unknown") for record in events}),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", help="Actual file received or saved from the phone")
    parser.add_argument("--sha256", required=True, help="Final file SHA-256 copied independently from the App")
    parser.add_argument("--require-critical-complete", action="store_true")
    args = parser.parse_args()
    try:
        report = verify(args.file, args.sha256)
        print(json.dumps(report, ensure_ascii=False))
        return 2 if args.require_critical_complete and report["critical_events_missing"] else 0
    except (OSError, ValueError, zipfile.BadZipFile, KeyError, TypeError, RuntimeError) as error:
        print(json.dumps({"verified": False, "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
