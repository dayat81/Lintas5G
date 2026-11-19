#!/usr/bin/env python3
"""YouTube playback metrics for Lintas5G Sesi D (headless, no account data).

Parses Android dumpsys media_session (API 13 `state=3` and API 14+ `state=PLAYING(3)`),
extrapolates position while PLAYING using `updated` + /proc/uptime, and derives
startup / stall metrics from a 1 s sample stream.

Obtainable vs not (FAKTA from parser + Sesi D K4 experience):
  Obtainable: playback state, position (ms), position advance, stall count/duration
              (position not advancing while PLAYING or BUFFERING), startup time
              (VIEW/intent t0 -> first PLAYING sample with advancing position).
  Official advanced_s (v0.10.1): last PLAYING pos_ms minus first PLAYING pos_ms.
              Do not use pos from BUFFERING/CONNECTING or assume the video started at 0;
              a resumed session can start at e.g. 9 min and would inflate raw pos_end/1000.
  Best-effort: width/height/bitrate/itag from dumpsys media.metrics or logcat
              (ExoPlayer / YouTube format lines). Often missing on the YouTube
              app; never treat absence as a test failure.
  Not obtainable from media_session: per-chunk HTTP/3 RTT, chosen itag reliably,
              rebuffer reason, CDN, or whether the app used QUIC (use Zeek/MGLT).

usage:
  yt-playback.py parse --dump FILE [--uptime-ms MS]
  yt-playback.py analyze --samples FILE [--t0-ms MS] [--out FILE]
  yt-playback.py collect --dur S --out FILE [--interval 1] [--adb CMD]
"""
from __future__ import annotations

import argparse, json, os, re, subprocess, sys, time
from typing import Any, Optional

# PlaybackState: 0=NONE 1=STOPPED 2=PAUSED 3=PLAYING 4=FF 5=REW 6=BUFFERING 7=ERROR 8=CONNECTING
PLAYING, PAUSED, BUFFERING, CONNECTING = 3, 2, 6, 8
STATE_NAME = {0: "NONE", 1: "STOPPED", 2: "PAUSED", 3: "PLAYING", 4: "FF",
              5: "REW", 6: "BUFFERING", 7: "ERROR", 8: "CONNECTING"}

# PlaybackState fields are parsed independently (order varies by API).
_RE_PLAY = re.compile(r"state=PlaybackState\s*\{([^}]*)\}", re.DOTALL)
_RE_STATE_NUM = re.compile(r"(\d+)")
_RE_POS = re.compile(r"position=([-\d]+)")
_RE_UPD = re.compile(r"updated=([-\d]+)")
_RE_SPD = re.compile(r"speed=([0-9.]+)")
_RE_ST = re.compile(r"(?:^|,\s*)state=([^,]+)")
_RE_WH = re.compile(r"\b(?:width|w)\s*[=:]\s*(\d{2,5}).{0,40}\b(?:height|h)\s*[=:]\s*(\d{2,5})", re.I)
_RE_WH2 = re.compile(r"\b(\d{3,5})\s*[xX]\s*(\d{3,5})\b")
_RE_BR = re.compile(r"\b(?:bitrate|current_bandwidth|bandwidth|format_bitrate)\s*[=:]\s*(\d{3,})", re.I)
_RE_ITAG = re.compile(r"\bitag\s*[=: ]\s*(\d{1,4})\b", re.I)
_RE_EXO = re.compile(r"ExoPlayer.*?(?:Format|video/).*?(\d{3,5})\s*[xX]\s*(\d{3,5})", re.I)


def parse_state_token(tok: str) -> Optional[int]:
    tok = tok.strip()
    m = _RE_STATE_NUM.search(tok)
    return int(m.group(1)) if m else None


def parse_session(text: str, uptime_ms: Optional[float] = None) -> Optional[dict[str, Any]]:
    """Return {state, pos_ms, pos_raw_ms, updated, speed, extrapolated} or None."""
    m = _RE_PLAY.search(text or "")
    if not m:
        return None
    block = m.group(1)
    sm = re.match(r"state=([^,]+)", block.strip()) or _RE_ST.search(block)
    if not sm:
        return None
    st = parse_state_token(sm.group(1))
    if st is None:
        return None
    pm, um, spm = _RE_POS.search(block), _RE_UPD.search(block), _RE_SPD.search(block)
    if not pm:
        return None
    pos_raw = int(pm.group(1))
    updated = int(um.group(1)) if um else 0
    speed = float(spm.group(1)) if spm else 1.0
    pos = pos_raw
    extra = False
    if st == PLAYING and updated > 0 and uptime_ms and uptime_ms > 0:
        pos = int(pos_raw + (uptime_ms - updated) * speed)
        extra = True
    return {
        "state": st,
        "state_name": STATE_NAME.get(st, str(st)),
        "pos_ms": pos,
        "pos_raw_ms": pos_raw,
        "updated": updated,
        "speed": speed,
        "extrapolated": extra,
    }


def parse_uptime_ms(text: str) -> Optional[float]:
    # "UPT=12345.67" (seconds) or a bare /proc/uptime first field
    m = re.search(r"^UPT=([0-9.]+)\s*$", text, re.M)
    if m:
        return float(m.group(1)) * 1000.0
    m = re.search(r"^([0-9.]+)\s+[0-9.]+\s*$", text, re.M)
    if m:
        return float(m.group(1)) * 1000.0
    return None


def parse_dump(text: str) -> Optional[dict[str, Any]]:
    up = parse_uptime_ms(text)
    return parse_session(text, up)


def extract_resolution(*texts: str) -> dict[str, Any]:
    """Best-effort width/height/bitrate/itag. Empty fields mean not obtainable."""
    blob = "\n".join(t for t in texts if t)
    out: dict[str, Any] = {"width": None, "height": None, "bitrate_bps": None, "itag": None, "source": None}
    if not blob:
        return out
    for rx, src in ((_RE_EXO, "logcat-exoplayer"), (_RE_WH, "metrics-wh"),):
        m = rx.search(blob)
        if m:
            out["width"], out["height"], out["source"] = int(m.group(1)), int(m.group(2)), src
            break
    if out["width"] is None:
        m = _RE_WH2.search(blob)
        if m:
            w, h = int(m.group(1)), int(m.group(2))
            if 120 <= w <= 7680 and 80 <= h <= 4320 and w >= h:
                out["width"], out["height"], out["source"] = w, h, "WxH"
    m = _RE_BR.search(blob)
    if m:
        out["bitrate_bps"] = int(m.group(1))
        # YouTube sometimes logs kbps
        if out["bitrate_bps"] < 50000:
            out["bitrate_bps"] *= 1000
    m = _RE_ITAG.search(blob)
    if m:
        out["itag"] = int(m.group(1))
    return out


def load_samples(path: str) -> list[dict[str, Any]]:
    rows = []
    with open(path, errors="replace") as f:
        header = None
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if header is None and parts[0] in ("t_epoch", "ts", "t"):
                header = parts
                continue
            if header:
                rec = dict(zip(header, parts))
            else:
                rec = {"t_epoch": parts[0], "elapsed_s": parts[1] if len(parts) > 1 else "0",
                       "state": parts[2] if len(parts) > 2 else "", "pos_ms": parts[3] if len(parts) > 3 else ""}
            try:
                rec["t_epoch"] = float(rec.get("t_epoch") or rec.get("ts") or 0)
                rec["elapsed_s"] = float(rec.get("elapsed_s") or 0)
                rec["state"] = int(float(rec.get("state") or -1))
                rec["pos_ms"] = int(float(rec.get("pos_ms") or -1))
            except ValueError:
                continue
            rows.append(rec)
    return rows


def analyze_samples(samples: list[dict[str, Any]], t0_ms: Optional[float] = None,
                    stall_min_s: float = 1.0, min_advance_ms: int = 400) -> dict[str, Any]:
    """Compute startup, stalls, advance. stall = pos not advancing while PLAYING or BUFFERING."""
    n = len(samples)
    if n == 0:
        return {"samples": 0, "playing": 0, "buffering": 0, "stall_count": 0, "stall_s": 0.0,
                "startup_s": None, "advanced_s": 0.0, "advance_def": "first_PLAYING_to_last_PLAYING",
                "pos0_ms": None, "pos_end_ms": None, "advanced_any_s": 0.0,
                "pos0_any_ms": None, "pos_end_any_ms": None,
                "dur_s": 0.0, "ok_playing_frac": 0.0}
    t_first = samples[0]["t_epoch"]
    t_last = samples[-1]["t_epoch"]
    t0 = (t0_ms / 1000.0) if t0_ms is not None else t_first
    playing = sum(1 for r in samples if r["state"] == PLAYING)
    buffering = sum(1 for r in samples if r["state"] == BUFFERING)
    # Official metric: first PLAYING -> last PLAYING (ignore pre-PLAYING / resume offset).
    playing_pos = [r for r in samples if r["state"] == PLAYING and r["pos_ms"] >= 0]
    pos0 = playing_pos[0]["pos_ms"] if playing_pos else None
    pos_end = playing_pos[-1]["pos_ms"] if playing_pos else None
    advanced_s = ((pos_end - pos0) / 1000.0) if pos0 is not None and pos_end is not None else 0.0
    any_pos = [r for r in samples if r["pos_ms"] >= 0]
    pos0_any = any_pos[0]["pos_ms"] if any_pos else None
    pos_end_any = any_pos[-1]["pos_ms"] if any_pos else None
    advanced_any_s = ((pos_end_any - pos0_any) / 1000.0) if pos0_any is not None and pos_end_any is not None else 0.0

    startup_s = None
    last_pos = None
    for r in samples:
        if r["state"] == PLAYING and r["pos_ms"] >= 0:
            if last_pos is not None and r["pos_ms"] - last_pos >= min_advance_ms:
                startup_s = max(0.0, r["t_epoch"] - t0)
                break
            last_pos = r["pos_ms"] if last_pos is None else last_pos

    # Stall windows: after playback has started, expected to advance (PLAYING or
    # BUFFERING) but position frozen >= stall_min_s. Initial buffering is startup, not a stall.
    stall_count = 0
    stall_s = 0.0
    i = 0
    while i < n and not (samples[i]["state"] == PLAYING and samples[i]["pos_ms"] >= 0):
        i += 1
    while i < n:
        r = samples[i]
        if r["state"] not in (PLAYING, BUFFERING) or r["pos_ms"] < 0:
            i += 1
            continue
        j = i + 1
        frozen = 0.0
        while j < n and samples[j]["state"] in (PLAYING, BUFFERING) and samples[j]["pos_ms"] >= 0:
            if samples[j]["pos_ms"] - r["pos_ms"] < min_advance_ms:
                frozen = samples[j]["t_epoch"] - r["t_epoch"]
                j += 1
            else:
                break
        if frozen >= stall_min_s:
            stall_count += 1
            stall_s += frozen
            i = j
        else:
            i += 1

    dur_s = max(0.0, t_last - t0)
    return {
        "samples": n,
        "playing": playing,
        "buffering": buffering,
        "stall_count": stall_count,
        "stall_s": round(stall_s, 3),
        "startup_s": None if startup_s is None else round(startup_s, 3),
        "advanced_s": round(advanced_s, 3),
        "advance_def": "first_PLAYING_to_last_PLAYING",
        "pos0_ms": pos0,
        "pos_end_ms": pos_end,
        "advanced_any_s": round(advanced_any_s, 3),
        "pos0_any_ms": pos0_any,
        "pos_end_any_ms": pos_end_any,
        "dur_s": round(dur_s, 3),
        "ok_playing_frac": round(playing / n, 3) if n else 0.0,
        "t_first": t_first,
        "t_last": t_last,
    }


def collect(dur: float, out_path: str, interval: float, adb: str) -> dict[str, Any]:
    """Sample dumpsys media_session every `interval` s for `dur` s. Writes TSV."""
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    t_start = time.time()
    rows = []
    with open(out_path, "w") as fo:
        fo.write("t_epoch\telapsed_s\tstate\tpos_ms\tstate_name\n")
        while True:
            now = time.time()
            elapsed = now - t_start
            if elapsed >= dur:
                break
            cmd = adb + ' dumpsys media_session; echo UPT=$(cut -d" " -f1 /proc/uptime)'
            try:
                blob = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=15, text=True, errors="replace")
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                blob = ""
            rec = parse_dump(blob) or {"state": -1, "pos_ms": -1, "state_name": "NA"}
            fo.write(f"{now:.3f}\t{elapsed:.3f}\t{rec['state']}\t{rec['pos_ms']}\t{rec.get('state_name','')}\n")
            fo.flush()
            rows.append({"t_epoch": now, "elapsed_s": elapsed, "state": rec["state"], "pos_ms": rec["pos_ms"]})
            sleep = interval - (time.time() - now)
            if sleep > 0:
                time.sleep(sleep)
    return analyze_samples(rows, t0_ms=t_start * 1000.0)


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("parse")
    p.add_argument("--dump", required=True)
    p.add_argument("--uptime-ms", type=float)
    a = sub.add_parser("analyze")
    a.add_argument("--samples", required=True)
    a.add_argument("--t0-ms", type=float)
    a.add_argument("--out")
    a.add_argument("--metrics-dump")
    a.add_argument("--logcat")
    c = sub.add_parser("collect")
    c.add_argument("--dur", type=float, required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--interval", type=float, default=1.0)
    c.add_argument("--adb", default=os.environ.get("ADB", 'timeout 20 docker exec android-emu adb shell'))
    args = ap.parse_args(argv)
    if args.cmd == "parse":
        text = open(args.dump, errors="replace").read()
        rec = parse_session(text, args.uptime_ms if args.uptime_ms is not None else parse_uptime_ms(text))
        json.dump(rec or {"error": "no PlaybackState"}, sys.stdout)
        sys.stdout.write("\n")
        return 0 if rec else 1
    if args.cmd == "analyze":
        rows = load_samples(args.samples)
        out = analyze_samples(rows, t0_ms=args.t0_ms)
        texts = []
        if args.metrics_dump:
            texts.append(open(args.metrics_dump, errors="replace").read())
        if args.logcat:
            texts.append(open(args.logcat, errors="replace").read())
        if texts:
            out["resolution"] = extract_resolution(*texts)
        if args.out:
            with open(args.out, "w") as f:
                json.dump(out, f, indent=2)
                f.write("\n")
        json.dump(out, sys.stdout)
        sys.stdout.write("\n")
        return 0
    res = collect(args.dur, args.out, args.interval, args.adb)
    json.dump(res, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
