#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Loader PoC latency: VM pktlat.log (waktu nyata, QUIC) + hasil offline TCP.
Kompatibel Python 3.6. Tidak menyentuh container Zeek/emulator; hanya baca berkas log.
Parser toleran: JSON, TSV Zeek, CSV; alias field (fid/flow_id, seg/tap, hash/payload_hash,
proto, one_way/ow_s1u|ow_s5s8|ow_sgi, len, run_id).
"""
from __future__ import print_function

import csv
import io
import json
import os
import stat
import subprocess
import sys
import time
import traceback

try:
    from urllib.parse import urlencode
    from urllib.request import Request, urlopen
    from urllib.error import HTTPError, URLError
except ImportError:
    from urllib import urlencode
    from urllib2 import Request, urlopen, HTTPError, URLError

DASH = os.path.expanduser(os.environ.get("DASH", "~/lintas5g/loader"))
STATE_DIR = os.path.join(DASH, "state")
STATE_FILE = os.path.join(STATE_DIR, "offsets.json")
RESULTS = os.path.expanduser(os.environ.get("RESULTS", "~/lintas5g/results"))
ZLOG = os.environ.get("ZLOG", "/var/log/lab5g/zeek")
CH_URL = os.environ.get("CH_URL", "http://127.0.0.1:8123")
CH_USER = os.environ.get("CLICKHOUSE_USER", "poc")
CH_PASSWORD = os.environ.get("CLICKHOUSE_PASSWORD", "")
CH_DB = os.environ.get("CLICKHOUSE_DB", "poc_latency")
VM = os.environ.get("VM", "")  # wajib: host Zeek (mis. vm-core-ran internal IP)
SSH_KEY = os.environ.get("SSH_KEY", os.path.expanduser("~/.ssh/id_ed25519"))
SSH_KNOWN = os.environ.get("SSH_KNOWN", os.path.expanduser("~/.ssh/known_hosts"))
INTERVAL = int(os.environ.get("LOADER_INTERVAL", "15"))
LIVE_RUN_ID = os.environ.get("LIVE_RUN_ID", "live")

SEG_MAP = {
    "s1u": "s1u", "s1u(gtp)": "s1u", "s1-u": "s1u", "s1_u": "s1u",
    "sgi": "sgi", "s5s8": "s5s8", "s5s8(gtp)": "s5s8", "s5/s8": "s5s8",
    "s5-s8": "s5s8", "s5_s8": "s5s8", "bridge": "bridge", "emu-br": "bridge",
    "emu_br": "bridge", "app-br": "bridge", "app": "app",
}
OW_KEYS = (
    ("ow_s1u", "s1u"), ("ow_s5s8", "s5s8"), ("ow_sgi", "sgi"),
    ("one_way_s1u", "s1u"), ("one_way_s5s8", "s5s8"), ("one_way_sgi", "sgi"),
    ("lat_s1u", "s1u"), ("lat_s5s8", "s5s8"), ("lat_sgi", "sgi"),
    ("ow_s1u_ms", "s1u"), ("ow_s5s8_ms", "s5s8"), ("ow_sgi_ms", "sgi"),
)
# raw per-paket TCP (pktlat.zeek) — bukan hasil korelasi; jangan dimuat sebagai latency
RAW_HINTS = ("rseq", "rack", "fl")
STATS_INT = (
    "flows", "segs", "mapped", "pending", "probes", "probe_bytes", "probe_dup",
    "crc_bad", "recs", "rec_dup", "rec_resend_used", "ul_ok", "ul_miss",
    "dl_ok", "dl_miss", "dl_unmatched_evicted", "nomap", "flow_drop",
    "evicted", "seg_drop",
)


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    sys.stdout.write("%s %s\n" % (ts, msg))
    sys.stdout.flush()


def load_dotenv():
    path = os.path.join(DASH, ".env")
    if not os.path.isfile(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip("'").strip('"')
            if k and k not in os.environ:
                os.environ[k] = v
    global CH_USER, CH_PASSWORD, CH_DB, CH_URL
    CH_USER = os.environ.get("CLICKHOUSE_USER", CH_USER)
    CH_PASSWORD = os.environ.get("CLICKHOUSE_PASSWORD", CH_PASSWORD)
    CH_DB = os.environ.get("CLICKHOUSE_DB", CH_DB)
    if os.environ.get("CH_URL"):
        CH_URL = os.environ["CH_URL"]
    elif os.environ.get("CH_HTTP_PORT"):
        CH_URL = "http://127.0.0.1:%s" % os.environ["CH_HTTP_PORT"]


def first(d, keys, default=None):
    for k in keys:
        if k in d and d[k] not in (None, ""):
            return d[k]
        # case-insensitive
        for kk in d:
            if kk.lower() == k.lower() and d[kk] not in (None, ""):
                return d[kk]
    return default


def to_float(v):
    if v is None or v == "" or v is False:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def to_int(v, default=0):
    if v is None or v == "" or v is False:
        return default
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def to_ts(v):
    """Unix seconds (float/int/str) or ISO -> float seconds."""
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    try:
        return float(s)
    except ValueError:
        pass
    # 2026-11-17T16:49:00Z or with space
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ",
                "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return time.mktime(time.strptime(s.replace("Z", ""), fmt.replace("Z", "").replace("T", " ") if "T" in fmt else fmt))
        except ValueError:
            continue
    return None


def norm_dir(v):
    if v is None:
        return ""
    s = str(v).strip().upper()
    if s in ("UL", "UP", "U", "ORIG", "OUT", "UPLINK"):
        return "UL"
    if s in ("DL", "DOWN", "D", "RESP", "IN", "DOWNLINK"):
        return "DL"
    return s


def norm_seg(v):
    if v is None or v == "":
        return ""
    s = str(v).strip().lower()
    return SEG_MAP.get(s, s.replace("(gtp)", "").replace(" ", ""))


def norm_proto(rec, has_hash, has_off):
    v = first(rec, ("proto", "protocol", "l4", "l7"))
    if v:
        s = str(v).strip().lower()
        if s in ("quic", "udp-quic", "udp_quic"):
            return "quic"
        if s in ("tcp", "tcp4", "tcp6"):
            return "tcp"
        if s in ("udp",) and has_hash:
            return "quic"
        return s
    if has_hash:
        return "quic"
    return "tcp"


def norm_source(explicit, proto):
    if explicit:
        return str(explicit)
    if proto == "quic":
        return "rt"
    return "offline-tcp"


def looks_raw_tcp(rec):
    if any(k in rec for k in ("ow_s1u", "ow_s5s8", "ow_sgi", "one_way", "one_way_ms", "one_way_corr_ms")):
        return False
    return all(k in rec for k in RAW_HINTS)


def ts_iso(sec):
    if sec is None:
        return None
    # ClickHouse DateTime64 accepts 'YYYY-MM-DD HH:MM:SS.ffffff'
    try:
        sec = float(sec)
    except (TypeError, ValueError):
        return None
    if sec > 1e12:  # ns or ms
        if sec > 1e15:
            sec = sec / 1e9
        else:
            sec = sec / 1e3
    # sanity: 2020..2100
    if sec < 1577836800 or sec > 4102444800:
        return None
    whole = int(sec)
    frac = sec - whole
    # use UTC
    t = time.gmtime(whole)
    return time.strftime("%Y-%m-%d %H:%M:%S", t) + (".%06d" % int(round(frac * 1e6)))[:7] if False else (
        time.strftime("%Y-%m-%d %H:%M:%S", t) + ".%06d" % int((sec - whole) * 1e6)
    )


def emit_pkt_rows(rec, run_id, source_default):
    """Yield dicts for pkt_latency from one parsed record. Toleran format v2/v2.1."""
    if not isinstance(rec, dict) or looks_raw_tcp(rec):
        return
    flow = first(rec, ("flow_id", "fid", "flow", "id"))
    if flow is None:
        flow = ""
    flow = str(flow)
    direction = norm_dir(first(rec, ("dir", "direction")))
    ts = to_ts(first(rec, ("ts", "ts_zeek", "ts_tap", "timestamp", "time")))
    if ts is None:
        return
    ts_s = ts_iso(ts)
    if not ts_s:
        return
    h = first(rec, ("hash", "payload_hash", "pkt_hash", "qhash", "digest", "payloadhash"))
    h = "" if h is None else str(h)
    off = to_int(first(rec, ("off", "offset", "rel_off", "seq_rel", "byte_off")), 0)
    ln = to_int(first(rec, ("len", "length", "payload_len", "size")), 0)
    proto = norm_proto(rec, bool(h), off != 0)
    src = first(rec, ("source",))
    source = str(src) if src else source_default
    if not source:
        source = "rt" if proto == "quic" else "offline-tcp"
    # Probe per paket sekarang hanya QUIC; TCP (termasuk log lama) = baseline
    if proto == "tcp" and source == "rt":
        source = "offline-tcp"
    if proto == "quic" and not source:
        source = "rt"
    status = first(rec, ("status", "miss")) or ""
    status = str(status)
    wire = first(rec, ("wire", "tuple", "five_tuple")) or ""
    kind = first(rec, ("kind", "evt", "event")) or ""
    rid = first(rec, ("run_id", "run", "runid")) or run_id
    rid = str(rid)
    base = {
        "run_id": rid,
        "ts": ts_s,
        "flow": flow,
        "dir": direction or "UL",
        "proto": proto,
        "hash": h,
        "off": off,
        "len": ln,
        "source": source,
        "status": status,
        "wire": str(wire),
        "kind": str(kind),
    }
    pivoted = False
    for key, seg in OW_KEYS:
        if key in rec and rec[key] not in (None, ""):
            row = dict(base)
            row["seg"] = seg
            row["one_way_ms"] = to_float(rec[key])
            yield row
            pivoted = True
    if pivoted:
        return
    # satu baris per record: seg + one_way
    seg = norm_seg(first(rec, ("seg", "tap", "segment", "iface", "point")))
    ow = first(rec, (
        "one_way_ms", "one_way", "one_way_corr_ms", "ow", "lat_ms",
        "lat_last_ms", "lat_read_ms", "latency_ms", "ow_ms",
    ))
    # lat_first_ms as fallback
    if ow is None:
        ow = first(rec, ("lat_first_ms", "lat_tun_ms"))
    row = dict(base)
    row["seg"] = seg or "unknown"
    row["one_way_ms"] = to_float(ow)
    yield row


def emit_stats(rec, run_id, source="rt"):
    if not isinstance(rec, dict):
        return None
    ts = to_ts(first(rec, ("ts", "timestamp", "time")))
    if ts is None:
        return None
    ts_s = ts_iso(ts)
    if not ts_s:
        return None
    out = {
        "run_id": str(first(rec, ("run_id", "run")) or run_id),
        "ts": ts_s,
        "source": str(first(rec, ("source",)) or source),
    }
    for k in STATS_INT:
        out[k] = to_int(first(rec, (k,)), 0)
    if not out.get("dl_miss") and rec.get("dl_unmatched_evicted"):
        out["dl_miss"] = to_int(rec.get("dl_unmatched_evicted"), 0)
    out["mem_mb"] = to_float(first(rec, ("mem_mb", "memory_mb", "rss_mb"))) or 0
    # sisa field tak dikenal disimpan sebagai JSON (tanpa merusak skema)
    known = set(STATS_INT) | {"ts", "timestamp", "time", "run_id", "run", "source", "mem_mb", "memory_mb", "rss_mb", "dl_miss"}
    extra = {}
    for k, v in rec.items():
        if k not in known:
            extra[k] = v
    out["extra"] = json.dumps(extra, separators=(",", ":")) if extra else ""
    return out


def emit_mglt(rec, run_id, source="offline-tcp"):
    if not isinstance(rec, dict):
        return None
    if looks_raw_tcp(rec):
        return None
    flow = first(rec, ("flow_id", "fid", "flow"))
    if flow is None:
        return None
    ts = to_ts(first(rec, ("ts", "ts_zeek", "timestamp")))
    tue = to_ts(first(rec, ("t_ue", "tue", "ts_ue")))
    if ts is None:
        return None
    ts_s = ts_iso(ts)
    tue_s = ts_iso(tue) if tue is not None else ts_s
    if not ts_s:
        return None
    ow = first(rec, ("one_way_corr_ms", "one_way_ms", "one_way", "one_way_raw_s", "one_way_raw"))
    owf = to_float(ow)
    # one_way_raw in seconds (often skew-uncorrected, can be negative ~ -8s)
    key_used = None
    for k in ("one_way_corr_ms", "one_way_ms", "one_way", "one_way_raw_s", "one_way_raw"):
        if first(rec, (k,)) is not None:
            key_used = k
            break
    if key_used in ("one_way_raw_s", "one_way_raw") and owf is not None and abs(owf) < 1000:
        owf = owf * 1000.0
    return {
        "run_id": str(first(rec, ("run_id", "run")) or run_id),
        "ts": ts_s,
        "t_ue": tue_s or ts_s,
        "flow": str(flow),
        "seq": to_int(first(rec, ("seq",)), 0),
        "dir": norm_dir(first(rec, ("dir",))) or "UL",
        "seg": norm_seg(first(rec, ("seg", "tap"))) or "unknown",
        "one_way_ms": owf,
        "evt": str(first(rec, ("evt", "event", "kind")) or ""),
        "orig_dst": str(first(rec, ("orig_dst", "dst")) or ""),
        "orig_dport": to_int(first(rec, ("orig_dport", "dport")), 0),
        "teid": to_int(first(rec, ("teid",)), 0),
        "source": str(first(rec, ("source",)) or source),
    }


def parse_zeek_tsv_chunk(text, leftover):
    text = leftover + text
    lines = text.splitlines(True)
    leftover = ""
    if lines and not lines[-1].endswith("\n"):
        leftover = lines.pop()
    fields = None
    sep = "\t"
    recs = []
    buf_header_mode = False
    for line in lines:
        raw = line.rstrip("\n")
        if raw.startswith("#separator"):
            # #separator \x09
            val = raw.split(None, 1)[-1].strip() if " " in raw else "\\x09"
            if val in ("\\x09", "tab"):
                sep = "\t"
            else:
                try:
                    sep = val.encode("utf-8").decode("unicode_escape")
                except Exception:
                    sep = "\t"
            continue
        if raw.startswith("#fields"):
            fields = raw.split(sep)[1:] if sep in raw else raw.split()[1:]
            continue
        if raw.startswith("#"):
            continue
        if not raw:
            continue
        if fields:
            cols = raw.split(sep)
            rec = {}
            for i, name in enumerate(fields):
                rec[name] = cols[i] if i < len(cols) else ""
            recs.append(rec)
    return recs, leftover, fields, sep


def iter_records(text, leftover, kind_hint="auto"):
    """Parse a text chunk. Returns (records, leftover, mode)."""
    text = leftover + text
    if not text:
        return [], "", kind_hint
    # keep incomplete last line
    nl = text.rfind("\n")
    if nl == -1:
        return [], text, kind_hint
    body, leftover2 = text[:nl + 1], text[nl + 1:]
    mode = kind_hint
    sample = body.lstrip()
    if mode == "auto":
        if sample.startswith("{") or sample.startswith("["):
            mode = "json"
        elif sample.startswith("#fields") or sample.startswith("#separator") or sample.startswith("#ts"):
            mode = "zeek"
        elif "," in sample.split("\n", 1)[0] and not sample.startswith("{"):
            mode = "csv"
        else:
            # try json line
            first_line = sample.split("\n", 1)[0].strip()
            if first_line.startswith("{"):
                mode = "json"
            else:
                mode = "zeek"
    recs = []
    if mode == "json":
        for line in body.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                recs.append(obj)
    elif mode == "csv":
        try:
            reader = csv.DictReader(io.StringIO(body))
            for rec in reader:
                recs.append(dict(rec))
        except Exception:
            pass
    else:
        recs, leftover_z, _f, _s = parse_zeek_tsv_chunk(body, "")
        leftover2 = leftover_z + leftover2
    return recs, leftover2, mode


def ssh_vm(cmd, data=None):
    args = [
        "ssh",
        "-i", SSH_KEY,
        "-o", "UserKnownHostsFile=" + SSH_KNOWN,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=20",
        "-o", "LogLevel=ERROR",
        "lab@%s" % VM,
        cmd,
    ]
    try:
        p = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            stdin=subprocess.PIPE if data is not None else None,
        )
        out, err = p.communicate(data)
        if p.returncode != 0:
            err_s = err.decode("utf-8", "replace").strip() if err else ""
            raise RuntimeError("ssh exit %s: %s" % (p.returncode, err_s[:300]))
        return out
    except Exception:
        raise


def ch_request(query, body=None, timeout=60):
    # auth via header, jangan taruh password di query string log
    url = CH_URL.rstrip("/") + "/?" + urlencode({"query": query})
    data = None
    if body is not None:
        if not isinstance(body, bytes):
            data = body.encode("utf-8")
        else:
            data = body
    req = Request(url, data=data)
    import base64
    token = base64.b64encode(("%s:%s" % (CH_USER, CH_PASSWORD)).encode("utf-8")).decode("ascii")
    req.add_header("Authorization", "Basic %s" % token)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        resp = urlopen(req, timeout=timeout)
        return resp.read().decode("utf-8", "replace")
    except HTTPError as e:
        err = e.read().decode("utf-8", "replace") if e.fp else str(e)
        raise RuntimeError("clickhouse HTTP %s: %s" % (e.code, err[:500]))
    except URLError as e:
        raise RuntimeError("clickhouse unreachable: %s" % e.reason)


def ch_insert(table, rows):
    if not rows:
        return 0
    # drop keys with None for optional numeric? ClickHouse JSONEachRow accepts null
    buf = io.StringIO()
    for r in rows:
        buf.write(json.dumps(r, default=str, separators=(",", ":")))
        buf.write("\n")
    payload = buf.getvalue()
    q = "INSERT INTO %s.%s FORMAT JSONEachRow" % (CH_DB, table)
    ch_request(q, payload)
    return len(rows)


def ch_ping():
    return ch_request("SELECT 1").strip() == "1"


def load_state():
    if not os.path.isfile(STATE_FILE):
        return {"files": {}, "hist_done": []}
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"files": {}, "hist_done": []}


def save_state(st):
    if not os.path.isdir(STATE_DIR):
        os.makedirs(STATE_DIR)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, indent=0, sort_keys=True)
    os.rename(tmp, STATE_FILE)


def classify_name(name):
    base = os.path.basename(name).lower()
    if "pktraw" in base:
        return "skip"
    if "pktlat_stats" in base or "pktlat-stats" in base or base.startswith("pktlat_stats"):
        return "stats"
    if "pktlat" in base and base.endswith(".log"):
        return "pktlat"
    if base in ("zeek-pktlat-rt.log",) or "pktlat-rt" in base:
        return "pktlat"
    if base in ("zeek-pktlat.log",):
        # bisa raw atau rt; parser akan men-skip raw
        return "pktlat"
    if "mglt-joined" in base:
        return "mglt_csv"
    if base.endswith("mglt.log") or "zeek-mglt" in base or base.startswith("mglt."):
        return "mglt"
    if base == "pkt-ul.csv" or base.endswith("/pkt-ul.csv"):
        return "pkt_ul"
    if base == "pkt-dl.csv" or base.endswith("/pkt-dl.csv"):
        return "pkt_dl"
    return "unknown"


def apply_records(kind, recs, run_id, source_default):
    n_pkt = n_st = n_mg = 0
    if kind == "pktlat":
        rows = []
        for rec in recs:
            for row in emit_pkt_rows(rec, run_id, source_default):
                rows.append(row)
        n_pkt = ch_insert("pkt_latency", rows)
    elif kind == "stats":
        rows = []
        for rec in recs:
            r = emit_stats(rec, run_id, "rt" if source_default == "rt" else source_default)
            if r:
                rows.append(r)
        n_st = ch_insert("pktlat_stats", rows)
    elif kind in ("mglt", "mglt_csv"):
        rows = []
        for rec in recs:
            r = emit_mglt(rec, run_id, "offline-tcp")
            if r:
                rows.append(r)
        n_mg = ch_insert("mglt_markers", rows)
    elif kind in ("pkt_ul", "pkt_dl"):
        rows = []
        direction = "UL" if kind == "pkt_ul" else "DL"
        for rec in recs:
            rec = dict(rec)
            rec.setdefault("dir", direction)
            rec.setdefault("proto", "tcp")
            rec.setdefault("source", "offline-tcp")
            # pilih one_way
            if direction == "UL":
                if rec.get("lat_last_ms") in (None, "") and rec.get("lat_first_ms") not in (None, ""):
                    rec["one_way_ms"] = rec.get("lat_first_ms")
                else:
                    rec["one_way_ms"] = rec.get("lat_last_ms") or rec.get("lat_first_ms")
            else:
                rec["one_way_ms"] = rec.get("lat_read_ms") or rec.get("lat_tun_ms")
            rec["ts"] = rec.get("ts_tap") or rec.get("ts")
            rec["flow"] = rec.get("fid") or rec.get("flow_id") or rec.get("flow")
            rec["seg"] = rec.get("tap") or rec.get("seg")
            for row in emit_pkt_rows(rec, run_id, "offline-tcp"):
                row["source"] = "offline-tcp"
                row["proto"] = "tcp"
                row["dir"] = direction
                rows.append(row)
        n_pkt = ch_insert("pkt_latency", rows)
    return n_pkt, n_st, n_mg


def process_text(kind, text, leftover, run_id, source_default, mode="auto"):
    recs, leftover2, mode = iter_records(text, leftover, mode)
    n = apply_records(kind, recs, run_id, source_default)
    return leftover2, mode, n, len(recs)


def ingest_file_bytes(kind, data, leftover, run_id, source_default, mode="auto"):
    if isinstance(data, bytes):
        text = data.decode("utf-8", "replace")
    else:
        text = data
    return process_text(kind, text, leftover, run_id, source_default, mode)


def hist_run_id(path):
    # .../run-20261117-154824/pkt-ul.csv -> run-20261117-154824
    parts = os.path.abspath(path).split(os.sep)
    for p in reversed(parts[:-1]):
        if p.startswith("run-") or p.startswith("p2b-") or p.startswith("p3-") or p.startswith("p2-"):
            return p
    return os.path.basename(os.path.dirname(path)) or "hist"


INTERESTING = (
    "pkt-ul.csv", "pkt-dl.csv", "mglt-joined.csv", "mglt.log",
    "zeek-mglt.log", "zeek-pktlat-rt.log", "zeek-pktlat-stats.log",
    "pktlat.log", "pktlat_stats.log",
)


def extract_tgz_member(tgz, dest, names):
    import tarfile
    out = []
    try:
        tf = tarfile.open(tgz, "r:gz")
    except Exception as e:
        log("skip tgz %s: %s" % (tgz, e))
        return out
    try:
        for m in tf.getmembers():
            base = os.path.basename(m.name)
            if not m.isfile() or base not in names:
                continue
            if m.size > 50 * 1024 * 1024:
                continue
            target = os.path.join(dest, base)
            src = tf.extractfile(m)
            if src is None:
                continue
            if not os.path.isdir(dest):
                os.makedirs(dest)
            with open(target, "wb") as f:
                f.write(src.read())
            out.append(target)
    finally:
        tf.close()
    return out


def load_historical(st):
    if not os.path.isdir(RESULTS):
        log("hasil historis tidak ada: %s" % RESULTS)
        return
    done = set(st.get("hist_done") or [])
    # extracted dirs
    paths = []
    try:
        entries = os.listdir(RESULTS)
    except OSError as e:
        log("tidak bisa baca %s: %s" % (RESULTS, e))
        return
    for name in sorted(entries):
        p = os.path.join(RESULTS, name)
        if os.path.isdir(p):
            for fn in INTERESTING:
                fp = os.path.join(p, fn)
                if os.path.isfile(fp):
                    paths.append(fp)
        elif name.endswith(".tgz") or name.endswith(".tar.gz"):
            key = "tgz:" + name
            if key in done:
                continue
            dest = os.path.join(STATE_DIR, "hist", os.path.splitext(name)[0])
            extracted = extract_tgz_member(p, dest, INTERESTING)
            for fp in extracted:
                paths.append(fp)
            done.add(key)
    ntot = [0, 0, 0]
    for fp in paths:
        key = "hist:" + os.path.abspath(fp)
        if key in done:
            continue
        kind = classify_name(fp)
        if kind in ("unknown", "skip"):
            done.add(key)
            continue
        run_id = hist_run_id(fp)
        # historis hasil 2/2b/p3 TCP -> offline-tcp, kecuali nama rt + nanti proto=quic
        src_default = "offline-tcp"
        try:
            with open(fp, "rb") as f:
                data = f.read()
            leftover, mode, n, nrec = ingest_file_bytes(kind, data, "", run_id, src_default, "auto")
            ntot[0] += n[0]
            ntot[1] += n[1]
            ntot[2] += n[2]
            log("hist %s run=%s kind=%s rec=%s insert pkt=%s stats=%s mglt=%s" % (
                os.path.basename(fp), run_id, kind, nrec, n[0], n[1], n[2]))
            done.add(key)
        except Exception as e:
            log("GAGAL hist %s: %s" % (fp, e))
            traceback.print_exc()
    st["hist_done"] = sorted(done)
    save_state(st)
    log("historis selesai: pkt=%s stats=%s mglt=%s" % tuple(ntot))


def list_vm_logs():
    script = (
        "cd %s 2>/dev/null && "
        "for f in pktlat*.log mglt*.log; do "
        "  [ -f \"$f\" ] || continue; "
        "  case \"$f\" in *pktraw*) continue;; esac; "
        "  stat -c '%%n %%i %%s' \"$f\"; "
        "done" % ZLOG
    )
    out = ssh_vm(script)
    rows = []
    for line in out.decode("utf-8", "replace").splitlines():
        parts = line.split()
        if len(parts) >= 3:
            rows.append((parts[0], parts[1], int(parts[2])))
    return rows


def fetch_vm_bytes(name, offset, length=None):
    path = "%s/%s" % (ZLOG, name)
    # tail -c +N is 1-based
    cmd = "tail -c +%s %s" % (offset + 1, path)
    if length is not None:
        cmd = "dd if=%s bs=1 skip=%s count=%s 2>/dev/null" % (path, offset, length)
    return ssh_vm(cmd)


def load_live(st):
    files = st.setdefault("files", {})
    try:
        listing = list_vm_logs()
    except Exception as e:
        log("GAGAL list log VM (read-only ssh): %s" % e)
        return
    ntot = [0, 0, 0]
    for name, inode, size in listing:
        kind = classify_name(name)
        if kind in ("unknown", "skip"):
            continue
        key = name
        meta = files.get(key) or {"inode": None, "offset": 0, "leftover": "", "mode": "auto"}
        if str(meta.get("inode")) != str(inode) or int(meta.get("offset") or 0) > size:
            # berkas baru / dirotasi / dipotong
            meta = {"inode": str(inode), "offset": 0, "leftover": "", "mode": "auto"}
        off = int(meta.get("offset") or 0)
        if off >= size:
            files[key] = meta
            continue
        try:
            data = fetch_vm_bytes(name, off)
        except Exception as e:
            log("GAGAL baca %s: %s" % (name, e))
            continue
        leftover, mode, n, nrec = ingest_file_bytes(
            kind, data, meta.get("leftover") or "", LIVE_RUN_ID, "rt", meta.get("mode") or "auto"
        )
        meta["inode"] = str(inode)
        meta["offset"] = off + len(data)
        meta["leftover"] = leftover
        meta["mode"] = mode
        files[key] = meta
        ntot[0] += n[0]
        ntot[1] += n[1]
        ntot[2] += n[2]
        if nrec or n[0] or n[1] or n[2]:
            log("live %s +%sB rec=%s insert pkt=%s stats=%s mglt=%s" % (
                name, len(data), nrec, n[0], n[1], n[2]))
    save_state(st)
    return ntot


def loop(once=False, hist=True):
    load_dotenv()
    if not os.path.isdir(STATE_DIR):
        os.makedirs(STATE_DIR)
    if not ch_ping():
        raise SystemExit("ClickHouse tidak merespons di %s" % CH_URL)
    st = load_state()
    if hist:
        load_historical(st)
    while True:
        try:
            load_live(st)
        except Exception as e:
            log("error cycle live: %s" % e)
            traceback.print_exc()
        if once:
            break
        time.sleep(INTERVAL)


def main():
    once = "--once" in sys.argv or os.environ.get("ONCE") == "1"
    nohist = "--no-hist" in sys.argv
    onlyhist = "--hist-only" in sys.argv
    load_dotenv()
    if onlyhist:
        if not ch_ping():
            raise SystemExit("ClickHouse tidak merespons")
        st = load_state()
        load_historical(st)
        return
    loop(once=once, hist=not nohist)


if __name__ == "__main__":
    main()
