"""Model ringkas CAMARA Quality-On-Demand (subset v0.x). SKELETON, bukan implementasi penuh spec."""
from typing import Optional

from pydantic import BaseModel, Field


class DeviceIpv4Addr(BaseModel):
    publicAddress: Optional[str] = None
    privateAddress: Optional[str] = None


class Device(BaseModel):
    ipv4Address: Optional[DeviceIpv4Addr] = None
    phoneNumber: Optional[str] = None


class ApplicationServer(BaseModel):
    ipv4Address: str


class PortsSpec(BaseModel):
    ports: list[int] = Field(default_factory=list)


class CreateSession(BaseModel):
    device: Device
    applicationServer: ApplicationServer
    applicationServerPorts: Optional[PortsSpec] = None
    qosProfile: str
    duration: int = Field(default=3600, ge=1, le=86400)
    sink: Optional[str] = None


class SessionInfo(CreateSession):
    sessionId: str
    qosStatus: str = "REQUESTED"     # REQUESTED | AVAILABLE | UNAVAILABLE
    startedAt: Optional[str] = None
    expiresAt: Optional[str] = None
    backendRef: Optional[str] = None  # Location app-session PCF / Session-Id Rx
