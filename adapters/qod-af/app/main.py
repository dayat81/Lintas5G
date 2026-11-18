"""Lintas5G QoD AF adapter. SKELETON — bukan untuk produksi.

CAMARA Quality-On-Demand (subset): POST/GET/DELETE /quality-on-demand/v0/sessions
-> backend N5 (PCF Open5GS) / Rx (PCRF) / dry-run.
"""
import datetime as dt
import hmac
import uuid

from fastapi import Depends, FastAPI, Header, HTTPException, status

from . import config
from .backends import DryRunBackend, N5Backend, RxBackend
from .models import CreateSession, SessionInfo

app = FastAPI(title="Lintas5G QoD AF (SKELETON)", version="0.0.1")
PROFILES = config.load_profiles()
SESSIONS: dict[str, SessionInfo] = {}   # TODO: penyimpanan persisten + timer expiry


def make_backend(kind: str):
    if kind == "n5":
        return N5Backend(config.PCF_URL, config.NOTIF_URI)
    if kind == "rx":
        return RxBackend()
    return DryRunBackend()


BACKEND = make_backend(config.BACKEND)


def require_token(authorization: str = Header(default="")):
    """Auth sederhana Bearer token statis (QOD_API_TOKEN). TODO: OAuth2/CAMARA security."""
    expected = config.API_TOKEN
    given = authorization.removeprefix("Bearer ").strip()
    if not expected or not hmac.compare_digest(given, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "UNAUTHENTICATED")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "backend": config.BACKEND, "profiles": sorted(PROFILES)}


@app.post("/quality-on-demand/v0/sessions", status_code=201, dependencies=[Depends(require_token)])
def create_session(req: CreateSession) -> SessionInfo:
    profile = PROFILES.get(req.qosProfile)
    if profile is None:
        raise HTTPException(400, f"qosProfile tidak dikenal: {req.qosProfile}")
    if not (req.device.ipv4Address and (req.device.ipv4Address.privateAddress or req.device.ipv4Address.publicAddress)):
        raise HTTPException(400, "device.ipv4Address wajib di skeleton ini")
    now = dt.datetime.now(dt.timezone.utc)
    s = SessionInfo(**req.model_dump(), sessionId=str(uuid.uuid4()), startedAt=now.isoformat(),
                    expiresAt=(now + dt.timedelta(seconds=req.duration)).isoformat())
    try:
        s.backendRef = BACKEND.create(s, profile)
        s.qosStatus = "AVAILABLE"
    except NotImplementedError as e:
        raise HTTPException(501, str(e))
    SESSIONS[s.sessionId] = s
    return s


@app.get("/quality-on-demand/v0/sessions/{session_id}", dependencies=[Depends(require_token)])
def get_session(session_id: str) -> SessionInfo:
    s = SESSIONS.get(session_id)
    if not s:
        raise HTTPException(404, "NOT_FOUND")
    return s


@app.delete("/quality-on-demand/v0/sessions/{session_id}", status_code=204, dependencies=[Depends(require_token)])
def delete_session(session_id: str):
    s = SESSIONS.pop(session_id, None)
    if not s:
        raise HTTPException(404, "NOT_FOUND")
    if s.backendRef:
        BACKEND.delete(s.backendRef)


@app.post("/notify")
def notify(body: dict):
    """Callback event dari PCF (TODO: mapping ke CAMARA QOS_STATUS_CHANGED dan kirim ke sink)."""
    return {"received": True}
