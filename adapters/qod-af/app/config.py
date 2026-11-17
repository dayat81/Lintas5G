"""Konfigurasi dari environment (lihat .env.example di root repo). SKELETON."""
import os
from pathlib import Path

import yaml

PCF_URL = os.environ.get("QOD_PCF_URL", "http://127.0.0.1:7777")
BACKEND = os.environ.get("QOD_BACKEND", "n5")          # n5 | rx | dry-run
API_TOKEN = os.environ.get("QOD_API_TOKEN", "")        # wajib di-set; kosong = semua request ditolak
NOTIF_URI = os.environ.get("QOD_NOTIF_URI", "http://127.0.0.1:8080/notify")
PROFILES_FILE = Path(os.environ.get("QOD_PROFILES", Path(__file__).resolve().parent.parent / "profiles.yaml"))


def load_profiles(path: Path = PROFILES_FILE) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)["profiles"]
