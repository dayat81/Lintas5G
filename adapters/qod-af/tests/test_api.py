import os

os.environ["QOD_BACKEND"] = "dry-run"
os.environ["QOD_API_TOKEN"] = "test-token-not-secret"

from fastapi.testclient import TestClient  # noqa: E402

from app.backends import build_app_session_context  # noqa: E402
from app.main import PROFILES, app  # noqa: E402
from app.models import SessionInfo  # noqa: E402

c = TestClient(app)
H = {"Authorization": "Bearer test-token-not-secret"}
BODY = {
    "device": {"ipv4Address": {"privateAddress": "10.45.0.2"}},
    "applicationServer": {"ipv4Address": "198.51.100.10"},
    "applicationServerPorts": {"ports": [443]},
    "qosProfile": "QOS_E",
    "duration": 60,
}


def test_auth_required():
    assert c.post("/quality-on-demand/v0/sessions", json=BODY).status_code == 401


def test_lifecycle():
    r = c.post("/quality-on-demand/v0/sessions", json=BODY, headers=H)
    assert r.status_code == 201, r.text
    sid = r.json()["sessionId"]
    assert r.json()["qosStatus"] == "AVAILABLE"
    assert c.get(f"/quality-on-demand/v0/sessions/{sid}", headers=H).status_code == 200
    assert c.delete(f"/quality-on-demand/v0/sessions/{sid}", headers=H).status_code == 204
    assert c.get(f"/quality-on-demand/v0/sessions/{sid}", headers=H).status_code == 404


def test_unknown_profile():
    b = dict(BODY, qosProfile="QOS_X")
    assert c.post("/quality-on-demand/v0/sessions", json=b, headers=H).status_code == 400


def test_profiles_have_required_keys():
    for name, p in PROFILES.items():
        for k in ("5qi", "qci", "mbr_dl_kbps", "mbr_ul_kbps", "gbr_dl_kbps", "gbr_ul_kbps"):
            assert k in p, (name, k)


def test_app_session_context_shape():
    s = SessionInfo(**BODY, sessionId="x")
    ctx = build_app_session_context(s, PROFILES["QOS_M"], "http://127.0.0.1:8080/notify")
    mc = ctx["ascReqData"]["medComponents"]["1"]
    assert ctx["ascReqData"]["ueIpv4"] == "10.45.0.2"
    assert mc["mirBwDl"] == "5000 Kbps"
    assert len(mc["medSubComps"]["0"]["fDescs"]) == 2
