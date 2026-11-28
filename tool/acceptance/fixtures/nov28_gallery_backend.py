"""Isolated fixture using the actual Python business API, not a Dart server."""
import json
import socket
import sys
from pathlib import Path

backend = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(backend / "src" / "api"))
from birdbox_backend.config import Settings
from birdbox_backend.database import initialize_database, connect
from birdbox_backend.repository import BirdboxRepository
from birdbox_backend.main import create_app
import uvicorn

data = Path(sys.argv[2]).resolve()
settings = Settings(
    birdbox_mode="mock", data_root=data, database_path=data / "test.db",
    thumbnail_root=data / "thumbs", preview_root=data / "previews",
    log_dir=data / "logs", log_export_root=data / "exports",
    copy_target_roots=str(data / "target"),
    auto_import_samples=False, mdns_enabled=False,
)
initialize_database(settings)
repository = BirdboxRepository(settings)
project = repository.create_project("nov28-retained", "fixture-card")["project_id"]
with connect(settings) as db:
    for i in range(48):
        file_id = f"fixture-photo-{i:03d}"
        db.execute("INSERT INTO files(id,project_id,source_key,filename,format,size,analysis_state,captured_at,created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                   (file_id, project, file_id, f"{i:03d}.jpg", "JPEG", 1, "completed", "2026-11-28T00:00:00Z", "2026-11-28T00:00:00Z"))
        db.execute("INSERT INTO user_decisions(file_id,keep_state,updated_at) VALUES (?,?,?)",
                   (file_id, "keep" if i < 45 else "featured" if i < 47 else "discard", "2026-11-28T00:00:00Z"))
    db.commit()
app = create_app(settings)
server = uvicorn.Server(uvicorn.Config(app, log_level="error"))

@app.post("/local-nov28-shutdown")
def shutdown():
    server.should_exit = True
    return {"stopping": True}

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(json.dumps({"port": sock.getsockname()[1], "project_id": project}), flush=True)
server.run(sockets=[sock])
