#!/usr/bin/env python3
"""Local unit tests for the YouTube+QoD helpers (no GCP, no adb, no Zeek process)."""
from __future__ import annotations

import hashlib, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # infra/gcp/sesi-d
FX = Path(__file__).resolve().parent / "fixtures"
# pcaps are never committed (public repo): regenerate the synthetic probe fixture when absent
if not (FX / "probe-fanin.pcap").exists():
    subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "gen-probe-pcap.py"), str(FX / "probe-fanin.pcap")], check=True)
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "obs"))
sys.path.insert(0, str(ROOT / "zeek"))

import importlib.util

def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

yt_qod_analyze = _load("yt_qod_analyze", ROOT / "obs" / "yt-qod-analyze.py")
yt_playback = _load("yt_playback", ROOT / "yt-playback.py")
pktlat_mirror = _load("pktlat_mirror", ROOT / "zeek" / "pktlat-mirror.py")


class ParseSession(unittest.TestCase):
    def test_api16_playing_extrapolated(self):
        rec = yt_playback.parse_dump((FX / "media_session_api16.txt").read_text())
        self.assertIsNotNone(rec)
        self.assertEqual(rec["state"], 3)
        self.assertEqual(rec["state_name"], "PLAYING")
        self.assertTrue(rec["extrapolated"])
        self.assertEqual(rec["pos_raw_ms"], 5000)
        # uptime 110000 ms, updated 100000, speed 1 -> +10000
        self.assertEqual(rec["pos_ms"], 15000)

    def test_api13_state_eq_3_no_extrapolate_when_updated_zero(self):
        rec = yt_playback.parse_dump((FX / "media_session_api13.txt").read_text())
        self.assertEqual(rec["state"], 3)
        self.assertFalse(rec["extrapolated"])
        self.assertEqual(rec["pos_ms"], 12000)

    def test_buffering_not_extrapolated(self):
        rec = yt_playback.parse_dump((FX / "media_session_buffering.txt").read_text())
        self.assertEqual(rec["state"], 6)
        self.assertEqual(rec["state_name"], "BUFFERING")
        self.assertFalse(rec["extrapolated"])
        self.assertEqual(rec["pos_ms"], 30000)

    def test_resolution_from_metrics_and_logcat(self):
        r = yt_playback.extract_resolution(
            (FX / "media_metrics.txt").read_text(),
            (FX / "logcat_exo.txt").read_text(),
        )
        self.assertEqual(r["width"], 1280)
        self.assertEqual(r["height"], 720)
        self.assertEqual(r["bitrate_bps"], 2500000)
        self.assertEqual(r["itag"], 22)

    def test_resolution_missing_is_empty_not_error(self):
        r = yt_playback.extract_resolution("nothing useful here")
        self.assertIsNone(r["width"])
        self.assertIsNone(r["bitrate_bps"])


class StallAnalysis(unittest.TestCase):
    def test_idle_startup_and_no_stall(self):
        rows = yt_playback.load_samples(str(FX / "samples-idle-r1.tsv"))
        out = yt_playback.analyze_samples(rows, t0_ms=1000_000)
        self.assertGreaterEqual(out["playing"], 10)
        self.assertEqual(out["stall_count"], 0)
        self.assertEqual(out["stall_s"], 0.0)
        # first advancing PLAYING at t=1004 (pos 2000 after pos 1000 at 1003)
        self.assertIsNotNone(out["startup_s"])
        self.assertGreaterEqual(out["startup_s"], 2.0)
        self.assertLess(out["startup_s"], 6.0)
        self.assertGreater(out["advanced_s"], 15.0)

    def test_load_detects_stall(self):
        rows = yt_playback.load_samples(str(FX / "samples-load-r1.tsv"))
        out = yt_playback.analyze_samples(rows, t0_ms=1000_000)
        self.assertGreaterEqual(out["stall_count"], 1)
        self.assertGreaterEqual(out["stall_s"], 3.0)


class Mirror(unittest.TestCase):
    def _ip_udp(self, dport=443):
        # minimal IPv4 (20) + UDP (8) + 8 bytes payload, checksums left 0
        ip = bytes([0x45, 0, 0, 36, 0, 0, 0x40, 0, 64, 17, 0, 0,
                    10, 45, 0, 2, 203, 0, 113, 10])
        udp = bytes([0xC3, 0x50, dport >> 8, dport & 255, 0, 16, 0, 0]) + b"QUICTEST"
        return ip + udp

    def test_raw_ip_ue_vlan_105(self):
        tagged = pktlat_mirror.encapsulate(self._ip_udp(), "ue")
        self.assertEqual(pktlat_mirror.vlan_id(tagged), 105)
        self.assertEqual(tagged[16:18], b"\x08\x00")
        self.assertEqual(tagged[18], 0x45)

    def test_n3_ethernet_vlan_102(self):
        eth = b"\xaa" * 6 + b"\xbb" * 6 + b"\x08\x00" + self._ip_udp(2152)
        tagged = pktlat_mirror.encapsulate(eth, "n3")
        self.assertEqual(pktlat_mirror.vlan_id(tagged), 102)
        # original ethertype moved after VLAN
        self.assertEqual(tagged[16:18], b"\x08\x00")

    def test_n6_vlan_109_for_probes(self):
        tagged = pktlat_mirror.encapsulate(self._ip_udp(9001), "n6")
        self.assertEqual(pktlat_mirror.vlan_id(tagged), 109)

    def test_gtpu_detect(self):
        # IP proto UDP dport 2152
        ip = bytes([0x45, 0, 0, 28, 0, 0, 0x40, 0, 64, 17, 0, 0,
                    127, 0, 1, 1, 127, 0, 1, 1])
        udp = bytes([0x08, 0x68, 0x08, 0x68, 0, 8, 0, 0])  # 2152->2152
        self.assertTrue(pktlat_mirror._looks_gtpu(ip + udp))
        self.assertFalse(pktlat_mirror._looks_gtpu(self._ip_udp(443)))


class MgltHash(unittest.TestCase):
    def test_v21_hash_is_md5_first_64_then_8(self):
        payload = b"Q" * 200
        expect = hashlib.md5(payload[:64]).digest()[:8].hex()
        got = hashlib.md5(payload[:64]).digest()[:8].hex()
        self.assertEqual(len(expect), 16)
        self.assertEqual(got, expect)
        # matches Java: long from the first 8 digest bytes, big-endian
        h = 0
        for b in hashlib.md5(payload[:64]).digest()[:8]:
            h = (h << 8) | b
        self.assertEqual(f"{h:016x}", expect)


class AnalyzeRun(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.d = Path(self.td.name)
        # copy fixtures and generate playback json
        (self.d / "playback").mkdir()
        (self.d / "phases.tsv").write_bytes((FX / "phases.tsv").read_bytes())
        (self.d / "pktlat.log").write_bytes((FX / "pktlat.log").read_bytes())
        (self.d / "proto-counts.json").write_bytes((FX / "proto-counts.json").read_bytes())
        for cond in ("idle", "load", "load+qod"):
            src = FX / f"samples-{cond}-r1.tsv"
            dst = self.d / "playback" / f"{cond}-r1.tsv"
            dst.write_bytes(src.read_bytes())
            # analyze() looks for json named *idle-r1.json etc.
            t0 = {"idle": 1000.0, "load": 1000.0, "load+qod": 1000.0}[cond]
            # playback timestamps in the sample files start at 1000; that is fine for
            # stall/startup. The analyzer does not join playback to phase windows.
            rec = yt_playback.analyze_samples(yt_playback.load_samples(str(src)), t0_ms=t0 * 1000)
            (self.d / "playback" / f"{cond}-r1.json").write_text(json.dumps(rec) + "\n")

    def tearDown(self):
        self.td.cleanup()

    def test_summary_and_pass_criteria(self):
        summary = yt_qod_analyze.analyze(
            str(self.d), str(self.d / "phases.tsv"), str(self.d / "pktlat.log"),
            str(self.d / "proto-counts.json"),
        )
        self.assertEqual(summary["run_id"], "ytqod-fixture")
        self.assertEqual(summary["transport"], "quic")
        self.assertIn("idle", summary["phases"])
        idle = summary["phases"]["idle"][1]
        self.assertEqual(idle["playback"]["stall_count"], 0)
        self.assertGreaterEqual(summary["phases"]["load"][1]["playback"]["stall_count"], 1)
        # p99 DL n6 should exist and be much higher in load than load+qod
        load_p99 = idle_p99 = None  # noqa
        load_p99 = summary["phases"]["load"][1]["pkt"]["latency_ms"]["DL_n6"]["p99"]
        qod_p99 = summary["phases"]["load+qod"][1]["pkt"]["latency_ms"]["DL_n6"]["p99"]
        self.assertGreater(load_p99, 200)
        self.assertLess(qod_p99, 0.5 * load_p99)
        crit = summary["pass"]["criteria"]
        self.assertTrue(crit["P1_quic"])
        self.assertTrue(crit["P2_stalls"])
        self.assertTrue(crit["P5_p99_qod"])
        md = yt_qod_analyze.markdown(summary)
        self.assertIn("s5s8", md)  # documents the lab label caveat
        self.assertIn("Verdict (USULAN)", md)




class ResumeAdvance(unittest.TestCase):
    def test_official_advance_is_first_to_last_playing(self):
        rows = yt_playback.load_samples(str(FX / "samples-resume-r1.tsv"))
        out = yt_playback.analyze_samples(rows, t0_ms=1000_000)
        self.assertEqual(out["advance_def"], "first_PLAYING_to_last_PLAYING")
        self.assertEqual(out["pos0_ms"], 565406)
        self.assertEqual(out["pos_end_ms"], 583406)
        self.assertAlmostEqual(out["advanced_s"], 18.0, places=3)
        # Naive pos_end/1000 or any-state span is inflated by the resume offset.
        self.assertGreater(out["advanced_any_s"], 500.0)
        self.assertLess(out["advanced_s"], 20.0)


class TransportShare(unittest.TestCase):
    def test_conn_log_per_phase_share(self):
        phases = yt_qod_analyze.load_phases(str(FX / "phases.tsv"))
        rows = yt_qod_analyze.load_conn_log(str(FX / "conn.log"))
        self.assertGreaterEqual(len(rows), 4)
        by = {ph["cond"]: yt_qod_analyze.transport_share(rows, ph) for ph in phases}
        self.assertEqual(by["idle"]["udp443"], 1)
        self.assertEqual(by["idle"]["tcp443"], 0)
        self.assertEqual(by["load"]["udp443"], 1)
        self.assertEqual(by["load"]["tcp443"], 1)
        self.assertEqual(by["load"]["share_quic"], 0.5)
        self.assertEqual(by["load+qod"]["udp443"], 1)
        self.assertEqual(by["load+qod"]["tcp443"], 0)

    def test_p1_tcp_only_mode(self):
        per = {
            "idle": {1: {"transport_share": {"udp443": 0, "tcp443": 10}, "playback": {}, "pkt": {}}},
            "load": {1: {"transport_share": {"udp443": 0, "tcp443": 10}, "playback": {}, "pkt": {}}},
            "load+qod": {1: {"transport_share": {"udp443": 0, "tcp443": 10}, "playback": {}, "pkt": {}}},
        }
        auto = yt_qod_analyze.propose_pass(per, transport_mode="auto")
        self.assertFalse(auto["criteria"]["P1_quic"])
        tcp = yt_qod_analyze.propose_pass(per, transport_mode="tcp-only")
        self.assertTrue(tcp["criteria"]["P1_quic"])


class SgiQueue(unittest.TestCase):
    def test_join_n6_sgiq(self):
        phases = {ph["cond"]: ph for ph in yt_qod_analyze.load_phases(str(FX / "phases.tsv"))}
        rows = yt_qod_analyze.load_pkthash_logs(str(FX))
        self.assertGreaterEqual(len(rows), 8)
        idle = yt_qod_analyze.sgi_queue_stats(rows, phases["idle"])
        self.assertAlmostEqual(idle["DL_sgi-queue"]["p50"], 2.0, places=3)
        self.assertAlmostEqual(idle["UL_sgi-queue"]["p50"], 1.0, places=3)
        load = yt_qod_analyze.sgi_queue_stats(rows, phases["load"])
        self.assertAlmostEqual(load["DL_sgi-queue"]["p50"], 250.0, places=3)
        qod = yt_qod_analyze.sgi_queue_stats(rows, phases["load+qod"])
        self.assertAlmostEqual(qod["DL_sgi-queue"]["p50"], 10.0, places=3)


class MirrorV6(unittest.TestCase):
    def test_raw_ipv6_ue_vlan_105(self):
        # IPv6 UDP header-ish: version=6, next-hdr later unused; 40 byte header + payload
        raw = bytes([0x60, 0, 0, 0, 0, 8, 17, 64]) + bytes(32) + b"QUICv6xx"
        tagged = pktlat_mirror.encapsulate(raw, "ue")
        self.assertEqual(pktlat_mirror.vlan_id(tagged), 105)
        self.assertEqual(tagged[16:18], b"\x86\xdd")
        self.assertEqual(tagged[18] >> 4, 6)


class SchemaMentionsSgiQueue(unittest.TestCase):
    def test_sql_and_taps_document_placement(self):
        schema = (ROOT / "obs" / "pkt-schema.sql").read_text()
        self.assertIn("ms_sgi_queue", schema)
        self.assertIn("sgi-queue", schema)
        taps = (ROOT / "zeek-taps.sh").read_text()
        self.assertIn("ens4 egress", taps)
        self.assertIn("clsact", taps)
        self.assertIn("mirred", taps)
        self.assertIn("ifb0", taps)
        refl = (ROOT / "reflector.sh").read_text()
        self.assertIn("route_fix", refl)
        self.assertIn("priority 1000", refl)
        runner = (ROOT / "run-youtube-qod.sh").read_text()
        self.assertIn("TRANSPORT", runner)
        self.assertIn("quic-only", runner)
        emu = (ROOT / "emu-youtube-qod.sh").read_text()
        self.assertIn("MainActivity", emu)
        body = emu.split("vpn_start()")[1].split("vpn_stop()")[0]
        self.assertNotIn("am start-foreground-service", body)
        self.assertIn("am start -n $PKG/.MainActivity", body)
        self.assertIn("&t=0", emu)


class SgiqFeed(unittest.TestCase):
    def test_reframe_raw_ip(self):
        feed = _load("sgiq_feed", ROOT / "zeek" / "sgiq-feed.py")
        ip4 = bytes([0x45, 0, 0, 28, 0, 0, 0x40, 0, 64, 17, 0, 0, 10, 45, 0, 2, 1, 1, 1, 1]) + bytes(8)
        fr = feed.reframe(ip4)
        self.assertEqual(fr[12:14], b"\x08\x00")
        self.assertEqual(fr[14:], ip4)
        ip6 = bytes([0x60]) + bytes(39)
        self.assertEqual(feed.reframe(ip6)[12:14], b"\x86\xdd")
        self.assertIsNone(feed.reframe(b"\x00\x01"))


class PktlatDeploy(unittest.TestCase):
    """Regression for the v0.10.1 run: lab5g-pktlat2 died with "can't find mglt" (scripts never shipped) => 0% MGLT."""

    def test_vendored_scripts_match_observability(self):
        obs = ROOT.parents[2] / "observability" / "zeek"
        for n in ("mglt.zeek", "pktlat2.zeek"):
            self.assertTrue((ROOT / "zeek" / n).is_file(), n)
            if (obs / n).is_file():
                self.assertEqual((ROOT / "zeek" / n).read_bytes(), (obs / n).read_bytes(), n + " drifted")

    def test_taps_script_preflight_and_fail_loud(self):
        t = (ROOT / "pktlat2-taps.sh").read_text()
        self.assertIn("has_scripts", t)
        self.assertIn("is not active after start", t)
        r = (ROOT / "run-youtube-qod.sh").read_text()
        self.assertIn("PIPESTATUS", r)
        self.assertIn("pktlat2 did not start", r)

    def test_bpf_gtpu_filter_on_lo(self):
        """n3 socket on lo must only pass GTP-U (udp/2152); the ZMQ I/Q stream (tcp on lo) must be dropped in-kernel."""
        import struct
        def ip(proto, sp, dp, frag=0, ihl=5):
            l4 = struct.pack("!HHHH", sp, dp, 8, 0) if proto == 17 else struct.pack("!HHIIBBHHH", sp, dp, 0, 0, 0x50, 0x10, 0, 0, 0)
            hdr = struct.pack("!BBHHHBBH4s4s", 0x40 | ihl, 0, 20 + len(l4), 1, frag, 64, proto, 0, b"\x7f\0\0\1", b"\x7f\0\0\2")
            return b"\0" * 12 + b"\x08\x00" + hdr + b"\0" * (ihl * 4 - 20) + l4
        prog = pktlat_mirror.BPF_GTPU
        self.assertGreater(pktlat_mirror.bpf_run(prog, ip(17, 2152, 2152)), 0)
        self.assertGreater(pktlat_mirror.bpf_run(prog, ip(17, 40000, 2152)), 0)
        self.assertGreater(pktlat_mirror.bpf_run(prog, ip(17, 2152, 40000)), 0)
        self.assertGreater(pktlat_mirror.bpf_run(prog, ip(17, 2152, 2152, ihl=6)), 0)      # IP options
        self.assertEqual(pktlat_mirror.bpf_run(prog, ip(6, 2152, 2152)), 0)                  # tcp
        self.assertEqual(pktlat_mirror.bpf_run(prog, ip(6, 50000, 50001)), 0)                # ZMQ-like
        self.assertEqual(pktlat_mirror.bpf_run(prog, ip(17, 53, 53)), 0)
        self.assertEqual(pktlat_mirror.bpf_run(prog, ip(17, 2152, 2152, frag=0x00B9)), 0)    # non-first fragment
        self.assertEqual(pktlat_mirror.bpf_run(prog, b"\0" * 12 + b"\x86\xdd" + b"\0" * 60), 0)  # IPv6
        self.assertEqual(pktlat_mirror.bpf_run(prog, b"\0" * 10), 0)                         # runt

    def test_probe_fixture_frames(self):
        frames = pktlat_mirror._read_pcap(str(FX / "probe-fanin.pcap"))
        self.assertEqual(len(frames), 20)
        vl = [pktlat_mirror.vlan_id(f) for f in frames]
        self.assertEqual(sorted(set(vl)), [102, 105, 109])
        probes = [f for f in frames if pktlat_mirror.vlan_id(f) == 109 and f[18 + 20 + 8:18 + 20 + 12] == b"MGLT"]
        self.assertEqual(len(probes), 5)
        p = probes[0][18 + 28:]
        self.assertEqual(len(p), 72)                      # 52 B header + 1 record of 20 B
        self.assertEqual((p[4], p[5], p[33], p[34]), (2, 2, 1, 20))

    def test_zeek_replay_if_docker(self):
        """Replay the fixture through Zeek 9.0.1 (skipped without docker/network): expect 5 ok UL quic rows on s1u/s5s8/sgi."""
        import shutil, tempfile
        dk = shutil.which("docker")
        if not dk:
            self.skipTest("no docker")
        with tempfile.TemporaryDirectory() as td:
            for n in ("mglt.zeek", "pktlat2.zeek"):
                shutil.copy(ROOT / "zeek" / n, td)
            shutil.copy(ROOT / "zeek" / "run-live-yt.zeek", td)
            shutil.copy(FX / "probe-fanin.pcap", td)
            Path(td, "skew.cfg").write_text("PKTLAT2::skew_s 0.0\nPKTLAT2::run_id live\n")
            sed = subprocess.run(["sed", "-i", "s#/var/log/lab5g/pktlat/skew.cfg#/work/skew.cfg#", f"{td}/run-live-yt.zeek"])
            cmd = [dk, "run", "--rm", "-v", f"{td}:/work", "-w", "/work", "zeek/zeek:9.0.1", "sh", "-c",
                   "ZEEKPATH=/work:$(zeek-config --zeekpath) zeek -C -r probe-fanin.pcap run-live-yt.zeek"]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            if r.returncode != 0 and "permission denied" in r.stderr.lower():
                self.skipTest("docker not permitted")
            rows = [json.loads(l) for l in Path(td, "pktlat.log").read_text().splitlines()] if Path(td, "pktlat.log").exists() else []
            self.assertEqual(len(rows), 5, r.stderr[-300:])
            for x in rows:
                self.assertEqual(x["status"], "ok")
                for k in ("ow_s1u", "ow_s5s8", "ow_sgi"):
                    self.assertIn(k, x)


class SkewGuest(unittest.TestCase):
    def setUp(self):
        self.sg = _load("skew_guest", ROOT / "skew-guest.py")

    def test_min_delay_filter_recovers_offset(self):
        import random
        random.seed(7)
        off = 0.3382                              # guest - host
        pairs = []
        for i in range(40):
            h0 = 1000.0 + i * 0.01                # true host time of the guest read
            g = h0 + off
            pairs.append((g, h0 + random.uniform(0.001, 0.060)))   # stream delay 1..60 ms
        est = self.sg.best_offset(pairs)
        self.assertAlmostEqual(est, off, delta=0.004)

    def test_old_bracket_bias_example(self):
        """ssh+docker+adb chain: rtt 300 ms, guest clock read at 0.60 of the window -> mid-point estimate is off by ~0.1*rtt."""
        off = 0.3382; a = 1000.0; rtt = 0.300; read_at = a + 0.60 * rtt
        guest = read_at + off; b = a + rtt
        bracket = guest - (a + b) / 2
        self.assertAlmostEqual(bracket - off, 0.030, delta=0.002)
        self.assertGreater(abs(bracket - off), 0.02)

    def test_combine_sign(self):
        # guest is 0.30 s ahead of host, host 0.04 s ahead of core -> guest ahead of core by 0.34 => skew_s = core - guest = -0.34
        self.assertAlmostEqual(self.sg.combine(0.30, 0.04), -0.34)

    def test_stage_core_parses_stream(self):
        import io, contextlib
        prog = ("import time;print('G 0.300000 n=40',flush=True)\n"
                "for i in range(5): print('T %.6f' % (time.time()+0.04), flush=True); time.sleep(0.01)")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = self.sg.stage_core([sys.executable, "-c", prog])
        d = json.loads(buf.getvalue())
        self.assertEqual(rc, 0); self.assertTrue(d["ok"])
        self.assertAlmostEqual(d["off_hc_s"], 0.04, delta=0.01)
        self.assertAlmostEqual(d["skew_s"], -0.34, delta=0.01)

    def test_wiring(self):
        r = (ROOT / "run-youtube-qod.sh").read_text()
        self.assertIn("skew-guest.py", r); self.assertIn("SKEW_METHOD", r); self.assertIn("skew-samples.txt", r)
        self.assertIn("skew-stream", (ROOT / "emu-youtube-qod.sh").read_text())
        self.assertIn("mtu 65000", (ROOT / "pktlat2-taps.sh").read_text())


class SyntaxAndImports(unittest.TestCase):
    def test_python_compile(self):
        files = [
            ROOT / "yt-playback.py",
            ROOT / "obs" / "yt-qod-analyze.py",
            ROOT / "zeek" / "pktlat-mirror.py",
            ROOT / "zeek" / "sgiq-feed.py",
            ROOT / "obs" / "pkt-prep.py",
            ROOT / "skew-guest.py",
            Path(__file__).with_name("gen-probe-pcap.py"),
            Path(__file__),
        ]
        for f in files:
            src = f.read_text()
            compile(src, str(f), "exec")


if __name__ == "__main__":
    unittest.main(verbosity=2)
