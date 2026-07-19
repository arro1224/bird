"""拍鸟伴侣盒子端本地模拟服务。

仅使用 Python 标准库；删除整个 mock_box_server 文件夹不会影响 Flutter 前端。
运行：python server.py --host 0.0.0.0 --port 8080
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

BATCH_ID = "batch-demo-001"
JOB_ID = "job-demo-001"
SPECIES = [
    {"species_id": "alcedo-atthis", "name": "普通翠鸟", "english_name": "Common Kingfisher", "latin_name": "Alcedo atthis", "confidence": 1.0},
    {"species_id": "halcyon-pileata", "name": "蓝翡翠", "english_name": "Black-capped Kingfisher", "latin_name": "Halcyon pileata", "confidence": 1.0},
    {"species_id": "halcyon-smyrnensis", "name": "白胸翡翠", "english_name": "White-throated Kingfisher", "latin_name": "Halcyon smyrnensis", "confidence": 1.0},
    {"species_id": "egretta-garzetta", "name": "白鹭", "english_name": "Little Egret", "latin_name": "Egretta garzetta", "confidence": 1.0},
    {"species_id": "ardeola-bacchus", "name": "池鹭", "english_name": "Chinese Pond Heron", "latin_name": "Ardeola bacchus", "confidence": 1.0},
    {"species_id": "nycticorax-nycticorax", "name": "夜鹭", "english_name": "Black-crowned Night Heron", "latin_name": "Nycticorax nycticorax", "confidence": 1.0},
]
jobs = [{"job_id": JOB_ID, "job_type": "analysis", "job_state": "running", "progress": 0.5, "total_count": 1200, "finished_count": 600, "failed_count": 0, "current_file": "DSC_0600.NEF"}]
photos = [
    {"file_id": f"photo-demo-{index:03d}", "filename": f"DSC_{index:04d}.NEF", "format": "RAW", "captured_at": f"2026-07-12T06:{index % 60:02d}:{index % 60:02d}Z", "analysis_state": "completed" if index % 5 else "low_confidence", "thumb_ref": f"__MOCK_ORIGIN__/mock-media/thumb/{index}.bmp", "preview_ref": f"__MOCK_ORIGIN__/mock-media/preview/{index}.bmp", "width": 6000, "height": 4000,
     "group_id": "group-demo-001" if index < 5 else "group-demo-002", "scene_id": f"scene-demo-{((index - 1) % 4) + 1:03d}",
     "clarity_state": "blurred" if index % 9 == 0 else ("average" if index % 5 == 0 else "clear"), "is_recommended": index % 7 == 1,
     "recognition": {"species_topn": [{"species_id": "egretta-garzetta" if index % 2 else "alcedo-atthis", "name": "白鹭" if index % 2 else "普通翠鸟", "confidence": 0.93 if index % 5 else 0.52}, {"species_id": "ardeola-bacchus", "name": "池鹭", "confidence": 0.08}, {"species_id": "nycticorax-nycticorax", "name": "夜鹭", "confidence": 0.03}], "low_confidence": index % 5 == 0, "model_version": "bird-demo-1.1"},
     "rating": {"total_score": round(min(5.0, 3.5 + (index % 16) / 10), 1), "quality_score": round(min(10.0, 7.2 + (index % 12) / 5), 1), "eye_score": round(min(10.0, 7.0 + (index % 10) / 4), 1), "composition_score": round(min(10.0, 7.4 + (index % 11) / 4), 1), "reason_tags": ["主体清晰", "眼部清晰", "背景干净"]}}
    for index in range(1, 10001)
]
decisions: dict[str, dict] = {}
history: dict[str, list[dict]] = {photo["file_id"]: [{"version": 1, "source": "box", "updated_at": "2026-07-10T06:00:00Z", "summary": "盒子端自动识别完成"}] for photo in photos}
copy_job_counter = 0
SCENARIO = "normal"


def mock_bird_bmp(index: int, preview: bool) -> bytes:
    """Generate deterministic local mock media without shipping large assets."""
    width, height = ((720, 480) if preview else (240, 180))
    row_size = (width * 3 + 3) & ~3
    pixels = bytearray(row_size * height)
    palettes = [((76, 92, 55), (188, 174, 128)), ((51, 79, 68), (126, 154, 146)), ((91, 75, 52), (184, 151, 96))]
    dark, light = palettes[index % len(palettes)]
    for y in range(height):
        for x in range(width):
            wave = (math.sin((x + index * 17) / 27) + math.cos((y + index * 11) / 23)) * 8
            mix = y / max(1, height - 1)
            rgb = [int(dark[c] * (1 - mix) + light[c] * mix + wave) for c in range(3)]
            # A lightweight bird silhouette: body ellipse, head and beak.
            nx, ny = x / width, y / height
            body = ((nx - .53) / .24) ** 2 + ((ny - .50) / .18) ** 2 < 1
            head = ((nx - .71) / .09) ** 2 + ((ny - .42) / .10) ** 2 < 1
            beak = .78 < nx < .91 and abs(ny - .42) < (.91 - nx) * .32
            if body or head or beak:
                rgb = [225 + (index % 3) * 6, 219 + (index % 4) * 4, 197]
            offset = (height - 1 - y) * row_size + x * 3
            pixels[offset:offset + 3] = bytes((max(0, min(255, rgb[2])), max(0, min(255, rgb[1])), max(0, min(255, rgb[0]))))
    file_size = 54 + len(pixels)
    header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    dib = struct.pack("<IIIHHIIIIII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return header + dib + pixels


def resolve_media_origin(value, origin: str):
    """Resolve mock media against the address used by this particular client."""
    if isinstance(value, dict):
        return {key: resolve_media_origin(item, origin) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve_media_origin(item, origin) for item in value]
    if isinstance(value, str):
        return value.replace("__MOCK_ORIGIN__", origin)
    return value


# A handful of deterministic variants is enough for UI testing. Precomputing
# them once avoids doing millions of Python pixel operations while the gallery
# requests its first 60 thumbnails in parallel.
MOCK_MEDIA = {
    (preview, index): mock_bird_bmp(index, preview)
    for preview in (False, True)
    for index in range(6)
}


def output_photo(photo: dict) -> dict:
    """Merge review state into every list/detail response, just as the box API does."""
    decision = decisions.get(photo["file_id"], {})
    return {**photo, "keep_state": decision.get("keep_state", "pending"), "user_tags": decision.get("user_tags", [])}


def current_job() -> dict | None:
    """Prefer the newest active task so dashboard and task-center agree."""
    active = [job for job in jobs if job.get("job_state") in {"running", "paused"}]
    return active[-1] if active else (jobs[-1] if jobs else None)


def read_page(query: dict):
    filtered = photos[:]
    search = query.get("search", [""])[0].strip().lower()
    if search:
        filtered = [photo for photo in filtered if search in photo["filename"].lower() or search in photo["recognition"]["species_topn"][0]["name"].lower() or any(search in tag.lower() for tag in decisions.get(photo["file_id"], {}).get("user_tags", []))]
    species = query.get("species", [""])[0].strip()
    if species: filtered = [photo for photo in filtered if species in photo["recognition"]["species_topn"][0]["name"]]
    if query.get("analysis_state"): filtered = [photo for photo in filtered if photo["analysis_state"] == query["analysis_state"][0]]
    if query.get("clarity_state"): filtered = [photo for photo in filtered if photo["clarity_state"] == query["clarity_state"][0]]
    if query.get("scene_id"): filtered = [photo for photo in filtered if photo["scene_id"] == query["scene_id"][0]]
    if query.get("recognition_state"):
        state = query["recognition_state"][0]
        if state == "recognized": filtered = [photo for photo in filtered if not photo["recognition"].get("low_confidence", False)]
        elif state == "needs_review": filtered = [photo for photo in filtered if photo["recognition"].get("low_confidence", False)]
        elif state == "unknown": filtered = [photo for photo in filtered if not photo["recognition"].get("species_topn")]
    if query.get("recommended_only", ["false"])[0].lower() == "true":
        filtered = [photo for photo in filtered if photo["is_recommended"]]
    if query.get("min_score"):
        filtered = [photo for photo in filtered if photo["rating"]["total_score"] >= float(query["min_score"][0])]
    if query.get("min_confidence"):
        filtered = [photo for photo in filtered if photo["recognition"]["species_topn"][0]["confidence"] >= float(query["min_confidence"][0])]
    if query.get("group_id"): filtered = [photo for photo in filtered if photo["group_id"] == query["group_id"][0]]
    if query.get("tags"):
        required_tags = {tag.strip().lower() for tag in query["tags"][0].split(",") if tag.strip()}
        filtered = [photo for photo in filtered if required_tags.issubset({tag.lower() for tag in decisions.get(photo["file_id"], {}).get("user_tags", [])})]
    if query.get("keep_state"):
        filtered = [photo for photo in filtered if decisions.get(photo["file_id"], {}).get("keep_state", "pending") == query["keep_state"][0]]
    sort = query.get("sort", ["captured_at_desc"])[0]
    if sort == "score_desc":
        filtered.sort(key=lambda photo: photo["rating"]["total_score"], reverse=True)
    elif sort == "confidence_desc":
        filtered.sort(key=lambda photo: photo["recognition"]["species_topn"][0]["confidence"], reverse=True)
    elif sort == "recommended_desc":
        filtered.sort(key=lambda photo: (photo["is_recommended"], photo["rating"]["total_score"]), reverse=True)
    elif sort == "captured_at_desc":
        filtered.sort(key=lambda photo: photo["captured_at"], reverse=True)
    page_size = int(query.get("page_size", ["60"])[0]); offset = int(query.get("cursor", ["0"])[0] or 0)
    current = filtered[offset:offset + page_size]; next_cursor = str(offset + page_size) if offset + page_size < len(filtered) else None
    return {"items": [output_photo(photo) for photo in current], "has_more": next_cursor is not None, "next_cursor": next_cursor}


def payload(path: str, method: str, query: dict, body: dict):
    if path == "/api/v1/device/status":
        storage_free = 2_000_000_000 if SCENARIO == "storage-full" else 600_000_000_000
        return {"device_id": "birdbox-demo-01", "device_name": "模拟拍鸟盒子", "network_mode": "lan", "api_version": "v1", "battery_percent": 82, "temperature": 43.5, "storage_total": 1000000000000, "storage_free": storage_free, "card_inserted": True, "card_readable": True, "software_version": "mock-1.1", "model_version": "bird-demo-1.0", "current_task": current_job()}
    if path == "/api/v1/projects/current": return {"project_id": BATCH_ID, "name": "2026.07.16 崇明东滩", "created_at": "2026-07-16T06:00:00Z", "total_files": len(photos), "analyzed_count": len(photos), "pending_review_count": 18, "review_count": 18, "keep_count": 9, "discard_count": 4, "featured_count": 2, "pending_copy_count": 9, "copy_state": "pending", "scene_count": 4, "burst_group_count": 64, "cover": {"thumb_ref": "__MOCK_ORIGIN__/mock-media/thumb/1.bmp", "preview_ref": "__MOCK_ORIGIN__/mock-media/preview/1.bmp"}}
    if path == "/api/v1/projects": return {"items": [payload("/api/v1/projects/current", "GET", {}, {})], "has_more": False, "next_cursor": None}
    if path == f"/api/v1/projects/{BATCH_ID}/resume" and method == "POST": return {"accepted": True, "project_id": BATCH_ID}
    if path == f"/api/v1/projects/{BATCH_ID}/files": return read_page(query)
    if path == f"/api/v1/projects/{BATCH_ID}/files/actions" and method == "POST":
        ids = body.get("file_ids", []); failed = [{"file_id": item, "reason": "模拟：文件正在分析，稍后重试"} for item in ids if item.endswith("005")]
        succeeded = [item for item in ids if not item.endswith("005")]
        operation = body.get("operation", "pending")
        for file_id in succeeded:
            previous = decisions.get(file_id, {})
            if operation in {"pending", "keep", "discard", "featured"}:
                decisions[file_id] = {**previous, "file_id": file_id, "keep_state": operation, "user_tags": previous.get("user_tags", [])}
            elif operation == "add_tags":
                tags = [str(tag) for tag in body.get("value", [])]
                decisions[file_id] = {**previous, "file_id": file_id, "keep_state": previous.get("keep_state", "pending"), "user_tags": list(dict.fromkeys([*previous.get("user_tags", []), *tags]))}
            elif operation == "remove_tags":
                tags = {str(tag) for tag in body.get("value", [])}
                decisions[file_id] = {**previous, "file_id": file_id, "keep_state": previous.get("keep_state", "pending"), "user_tags": [tag for tag in previous.get("user_tags", []) if tag not in tags]}
            history.setdefault(file_id, []).append({"version": len(history.get(file_id, [])) + 1, "source": "app", "updated_at": "2026-07-12T00:00:00Z", "summary": f"批量操作：{operation}"})
        return {"succeeded_ids": succeeded, "failed": failed}
    if path == f"/api/v1/projects/{BATCH_ID}/groups":
        definitions = [
            ("group-demo-001", "burst", ["photo-demo-001", "photo-demo-002", "photo-demo-003", "photo-demo-004"], ["photo-demo-001", "photo-demo-003", "photo-demo-002", "photo-demo-004"], ["主体清晰", "眼部锐利", "姿态自然"]),
            ("group-demo-002", "scene", ["photo-demo-006", "photo-demo-007", "photo-demo-008"], ["photo-demo-006", "photo-demo-007", "photo-demo-008"], ["构图完整", "背景干净"]),
        ]
        items = []
        for group_id, group_type, member_ids, ranking, reasons in definitions:
            members = [output_photo(photo) for photo in photos if photo["file_id"] in member_ids]
            scene_id = members[0].get("scene_id") if members else None
            items.append({"group_id": group_id, "group_type": group_type, "representative_file_id": ranking[0], "member_file_ids": member_ids, "rank_order": ranking, "members": members, "recommendation_reasons": reasons, "scene_id": scene_id, "captured_from": "2026-07-10T06:00:00Z", "captured_to": "2026-07-10T06:00:03Z"})
        scene_id = query.get("scene_id", [None])[0]
        return {"items": [item for item in items if scene_id is None or item["scene_id"] == scene_id]}
    if path == f"/api/v1/projects/{BATCH_ID}/scenes":
        definitions = [("清晨芦苇荡", 6, 12), ("潮滩水面", 7, 18), ("林缘枝头", 9, 14), ("返程沿线", 10, 10)]
        return {"items": [{"scene_id": f"scene-demo-{index:03d}", "project_id": BATCH_ID, "name": name, "captured_from": f"2026-07-16T0{hour}:12:00Z", "captured_to": f"2026-07-16T0{hour}:48:00Z", "photo_count": sum(1 for photo in photos if photo["scene_id"] == f"scene-demo-{index:03d}"), "burst_group_count": group_count, "cover": {"thumb_ref": f"__MOCK_ORIGIN__/mock-media/thumb/{index}.bmp", "preview_ref": f"__MOCK_ORIGIN__/mock-media/preview/{index}.bmp"}} for index, (name, hour, group_count) in enumerate(definitions, 1)]}
    if path == "/api/v1/species":
        search = query.get("search", [""])[0].strip().lower()
        items = [item for item in SPECIES if search in item["name"].lower() or search in item["english_name"].lower() or search in item["latin_name"].lower()]
        return {"items": items[:int(query.get("page_size", ["20"])[0])]}
    if path.startswith("/api/v1/files/"):
        file_id = path.split("/")[4]
        photo = next((value for value in photos if value["file_id"] == file_id), None)
        if path.endswith("/history"): return {"items": history.get(file_id, [])}
        if path.endswith("/decision") and method == "POST":
            if SCENARIO == "conflict": return {"error_code": "VERSION_CONFLICT", "message": "模拟版本冲突"}
            version = len(history.setdefault(file_id, [])) + 1; body["version"] = version; decisions[file_id] = body; history[file_id].append({"version": version, "source": "app", "updated_at": "2026-07-11T00:00:00Z", "summary": "人工审阅已更新"}); return {"accepted": True, "version": version, "decision": body}
        if photo: return {"file": output_photo(photo), "subjects": [{"bbox": {"x": 0.30, "y": 0.20, "width": 0.30, "height": 0.40}, "confidence": 0.95}], "tags": [{"tag_id": "tag-1", "tag_name": "水鸟", "source": "model", "editable": True}], "decision": decisions.get(file_id), "exif": {"ISO": 1600, "焦距": "600mm", "快门": "1/2000s"}}
    if path == "/api/v1/jobs": return {"items": jobs}
    if path.startswith("/api/v1/jobs/"):
        job_id = path.split("/")[4]
        job = next((item for item in jobs if item["job_id"] == job_id), None)
        if path.endswith("/failures"): return {"items": [{"file_id": "photo-demo-005", "error_code": "ANALYSIS_TIMEOUT", "reason": "模拟：分析服务响应超时", "retryable": True}] if job and job.get("failed_count", 0) else []}
        if path.endswith("/actions") and method == "POST" and job:
            action = body.get("action")
            states = {"pause": "paused", "resume": "running", "restore": "running", "retry": "running", "cancel": "cancelled"}
            if action in states: job["job_state"] = states[action]
            return job
        if job: return job
    if path == "/api/v1/logs/export" and method == "POST": return {"download_url": "/mock-download/bird-companion-log.txt", "state": "ready"}
    if path == f"/api/v1/projects/{BATCH_ID}/copy/estimate": return {"file_count": 9, "required_bytes": 120000000000, "pending_count": 2, "targets": [{"id": "disk-demo", "name": "模拟移动硬盘", "free_bytes": 800000000000, "total_bytes": 1000000000000, "online": True}]}
    if path == f"/api/v1/projects/{BATCH_ID}/copy" and method == "POST":
        global copy_job_counter
        copy_job_counter += 1
        jobs.append({"job_id": f"job-copy-{copy_job_counter:03d}", "job_type": "copy", "job_state": "running", "progress": 0.0, "total_count": 9, "finished_count": 0, "failed_count": 0, "current_file": "", "xmp_enabled": bool(body.get("xmp_enabled", True))}); return jobs[-1]
    return {"message": "mock endpoint not found", "path": path}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, value):
        host = self.headers.get("Host", "127.0.0.1:8080")
        value = resolve_media_origin(value, f"http://{host}")
        data = json.dumps(value, ensure_ascii=False).encode("utf-8"); self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8"); self.send_header("Access-Control-Allow-Origin", "*"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_OPTIONS(self): self._send(HTTPStatus.NO_CONTENT, {})
    def do_GET(self):
        parsed = urlparse(self.path)
        if SCENARIO == "slow": time.sleep(1.2)
        if parsed.path.startswith("/mock-media/"):
            parts = parsed.path.split("/")
            try: index = int(parts[-1].split(".")[0])
            except ValueError: index = 1
            preview = "preview" in parts
            data = MOCK_MEDIA[(preview, index % 6)]
            self.send_response(HTTPStatus.OK); self.send_header("Content-Type", "image/bmp"); self.send_header("Cache-Control", "public, max-age=86400"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data); return
        if parsed.path == "/mock-download/bird-companion-log.txt":
            data = "Bird Companion mock diagnostic log\nstatus=ok\n".encode("utf-8")
            self.send_response(HTTPStatus.OK); self.send_header("Content-Type", "text/plain; charset=utf-8"); self.send_header("Content-Disposition", "attachment; filename=bird-companion-log.txt"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data); return
        self._send(HTTPStatus.OK, payload(parsed.path, "GET", parse_qs(parsed.query), {}))
    def do_POST(self):
        if SCENARIO == "slow": time.sleep(1.2)
        parsed = urlparse(self.path); length = int(self.headers.get("Content-Length", "0")); raw = self.rfile.read(length) if length else b"{}"
        try: body = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError: body = {}
        if SCENARIO == "conflict" and parsed.path.startswith("/api/v1/files/") and parsed.path.endswith("/decision"):
            self._send(HTTPStatus.CONFLICT, {"error_code": "VERSION_CONFLICT", "message": "模拟版本冲突"}); return
        self._send(HTTPStatus.OK, payload(parsed.path, "POST", parse_qs(parsed.query), body))
    def do_DELETE(self):
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/v1/jobs/"):
            job_id = parsed.path.split("/")[4]
            global jobs
            job = next((item for item in jobs if item["job_id"] == job_id), None)
            if job is None:
                self._send(HTTPStatus.NOT_FOUND, {"message": "job not found"}); return
            if job.get("job_state") in {"running", "paused"}:
                self._send(HTTPStatus.CONFLICT, {"message": "cancel the task before deleting it"}); return
            jobs = [item for item in jobs if item["job_id"] != job_id]
            self._send(HTTPStatus.OK, {"deleted": True, "job_id": job_id}); return
        self._send(HTTPStatus.NOT_FOUND, {"message": "mock endpoint not found", "path": parsed.path})
    def log_message(self, *_): pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--host", default="0.0.0.0"); parser.add_argument("--port", type=int, default=8080); parser.add_argument("--scenario", choices=["normal", "slow", "conflict", "storage-full"], default="normal"); args = parser.parse_args()
    SCENARIO = args.scenario
    print(f"Mock Bird Box ({SCENARIO}): http://{args.host}:{args.port}")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
