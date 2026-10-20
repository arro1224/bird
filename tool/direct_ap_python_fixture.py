"""Local HTTP acceptance fixture. Requires BIRDBOX_BACKEND_ROOT; never deploy.

Uses the real Python API and pairing database, but not real BLE/WLAN hardware.
All generated state is isolated in a new temporary directory.
"""
import os
import sys
import tempfile
from pathlib import Path

backend = Path(os.environ["BIRDBOX_BACKEND_ROOT"]).resolve()
sys.path.insert(0, str(backend))
sys.path.insert(0, str(backend / "tests"))
import uvicorn
from fastapi.testclient import TestClient
from birdbox_backend.main import create_app
from test_rc4_backend import _settings, DEVICE_ID

root = Path(tempfile.mkdtemp(prefix="birdbox-direct-ap-acceptance-"))
settings = _settings(root, network_mode="direct_ap")
app = create_app(settings)
client_id = "a870bcb1-d423-4d66-96f7-f809ce786543"
with TestClient(app):
    pass


@app.get("/local-direct-ap-fixture")
def fixture():
    pairing = app.state.pairing_service
    pairing.open_pairing(device_id=DEVICE_ID, client_id=client_id)
    authorization = pairing.authorize_pairing(device_id=DEVICE_ID, client_id=client_id, pairing_code="123456")
    return {"device_id": DEVICE_ID, "client_id": client_id, **authorization}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=18096, log_level="warning")
