"""Backend kebijakan. SKELETON: N5 dan Rx masih TODO, dry-run untuk test.

- N5: Npcf_PolicyAuthorization (TS 29.514) ke PCF Open5GS, AF tepercaya (tanpa NEF).
- Rx: AAR/STR Diameter ke PCRF (TS 29.214) untuk varian EPC 4G.
"""
import uuid
from typing import Protocol

import httpx

from .models import SessionInfo


class PolicyBackend(Protocol):
    def create(self, s: SessionInfo, profile: dict) -> str: ...
    def delete(self, ref: str) -> None: ...


class DryRunBackend:
    """Tidak memanggil jaringan; mengembalikan ref palsu. Untuk unit test dan demo API."""

    def __init__(self):
        self.active: dict[str, dict] = {}

    def create(self, s: SessionInfo, profile: dict) -> str:
        ref = f"dry-run/{uuid.uuid4()}"
        self.active[ref] = {"session": s.sessionId, "profile": profile}
        return ref

    def delete(self, ref: str) -> None:
        self.active.pop(ref, None)


def build_app_session_context(s: SessionInfo, profile: dict, notif_uri: str) -> dict:
    """Bentuk AppSessionContext minimal (TS 29.514). Dipakai juga oleh tests/qod."""
    ue = (s.device.ipv4Address.privateAddress or s.device.ipv4Address.publicAddress) if s.device.ipv4Address else None
    ports = (s.applicationServerPorts.ports if s.applicationServerPorts else []) or [443]
    fdesc = []
    for p in ports:
        fdesc.append(f"permit out 17 from {s.applicationServer.ipv4Address} {p} to {ue}")
        fdesc.append(f"permit out 17 from {ue} to {s.applicationServer.ipv4Address} {p}")
    mc = {
        "medCompN": 1,
        "medType": "VIDEO",
        "fStatus": "ENABLED",
        "marBwDl": f"{profile['mbr_dl_kbps']} Kbps",
        "marBwUl": f"{profile['mbr_ul_kbps']} Kbps",
        "medSubComps": {"0": {"fNum": 0, "fDescs": fdesc}},
    }
    if profile.get("gbr_dl_kbps"):
        mc["mirBwDl"] = f"{profile['gbr_dl_kbps']} Kbps"
        mc["mirBwUl"] = f"{profile['gbr_ul_kbps']} Kbps"
    return {"ascReqData": {"afAppId": "lintas5g-qod", "ueIpv4": ue, "notifUri": notif_uri,
                           "suppFeat": "0", "medComponents": {"1": mc}}}


class N5Backend:
    """TODO: validasi terhadap PCF Open5GS 2.8.x (HTTP/2 prior knowledge, path /npcf-policyauthorization/v1)."""

    def __init__(self, pcf_url: str, notif_uri: str):
        self.pcf_url = pcf_url.rstrip("/")
        self.notif_uri = notif_uri

    def create(self, s: SessionInfo, profile: dict) -> str:
        body = build_app_session_context(s, profile, self.notif_uri)
        # TODO: httpx.Client(http2=True) butuh paket h2; tangani 4xx/5xx, retry, dan notifikasi (eventsSubscReqData).
        with httpx.Client(timeout=5.0) as c:
            r = c.post(f"{self.pcf_url}/npcf-policyauthorization/v1/app-sessions", json=body)
            r.raise_for_status()
            return r.headers["location"]

    def delete(self, ref: str) -> None:
        with httpx.Client(timeout=5.0) as c:
            c.post(f"{ref}/delete", json={}).raise_for_status()


class RxBackend:
    """TODO: klien Diameter Rx (AAR/STR) ke PCRF; belum diimplementasikan."""

    def create(self, s: SessionInfo, profile: dict) -> str:
        raise NotImplementedError("Rx AAR belum diimplementasikan (lihat tests/qod/aar-rx.template)")

    def delete(self, ref: str) -> None:
        raise NotImplementedError("Rx STR belum diimplementasikan")
