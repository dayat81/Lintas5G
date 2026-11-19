"""ran_mode=sa-oai (OAI gNB + nrUE): config rendering, sim/real ratio, honest throughput, run ordering (DRY_RUN)."""
import json, os, random, subprocess, sys, tempfile, unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SA = os.path.join(ROOT, "infra", "gcp", "sa")
sys.path.insert(0, SA)
import nr_summary, oai_conf  # noqa: E402

BASE = """gNBs = ( {
    tracking_area_code  =  1;
    plmn_list = ({ mcc = 208; mnc = 99; mnc_length = 2; snssaiList = ({ sst = 1, sd = 0xffffff }) });
    min_rxtxtime = 6;
    amf_ip_address = ({ ipv4 = "192.168.71.132"; });
    NETWORK_INTERFACES : {
       GNB_IPV4_ADDRESS_FOR_NG_AMF              = "192.168.71.140";
       GNB_IPV4_ADDRESS_FOR_NGU                 = "192.168.71.140";
    };
} );
RUs = ( { nb_tx          = 1
         nb_rx          = 1 } );
log_config : { f1ap_log_level ="debug"; };
"""
IMG_G = "oaisoftwarealliance/oai-gnb:v3.0.0@sha256:" + "1" * 64
IMG_U = "oaisoftwarealliance/oai-nr-ue:v3.0.0@sha256:" + "2" * 64


class Conf(unittest.TestCase):
    def test_gnb_2x2(self):
        s = oai_conf.render_gnb(BASE, mimo=2)
        self.assertIn("mcc = 001; mnc = 01", s)
        self.assertNotIn("sd = 0xffffff", s)
        self.assertIn('ipv4 = "127.0.0.5"', s)
        self.assertEqual(s.count('"127.0.1.1"'), 2)
        for k in ("pdsch_AntennaPorts_XP = 2", "pusch_AntennaPorts = 2", "do_CSIRS = 1", 'do_SRS = "periodic"', "nb_tx          = 2", "nb_rx          = 2"):
            self.assertIn(k, s)
        self.assertNotIn('"debug"', s)

    def test_gnb_1x1_and_bad(self):
        s = oai_conf.render_gnb(BASE, mimo=1)
        self.assertNotIn("pdsch_AntennaPorts_XP", s)
        self.assertIn("nb_tx          = 1", s)
        with self.assertRaises(ValueError): oai_conf.render_gnb(BASE, mimo=4)
        with self.assertRaises(ValueError): oai_conf.render_gnb("nothing here", mimo=2)

    def test_ue_conf_secrets_from_env_only(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "ue.conf")
            imsi = "00101" + "".join(random.choice("0123456789") for _ in range(10))
            env = dict(os.environ, IMSI=imsi, K="0" * 32, OPC="f" * 32)
            r = subprocess.run([sys.executable, os.path.join(SA, "oai_conf.py"), "ue", "--out", out], env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn(imsi, r.stdout + r.stderr)
            self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)
            self.assertIn('dnn = "internet"', open(out).read())
        with self.assertRaises(ValueError): oai_conf.render_ue("123", "0" * 32, "0" * 32)


class Ratio(unittest.TestCase):
    def test_oai_frame_lines(self):
        # 128 frames (1.28 s sim) every 0.32 s wall -> 4x real time, with SFN wrap 896 -> 0
        lines = [f"{100 + 0.32 * k:.6f} [NR_MAC] I Frame.Slot {(128 * (k + 6)) % 1024}.0" for k in range(10)]
        r = nr_summary.sim_ratio(lines)
        self.assertEqual(r["source"], "oai")
        self.assertAlmostEqual(r["sim_ratio"], 4.0, places=2)

    def test_srsran_sfn_lines(self):
        lines = [f"2026-11-19T06:00:{k:02d}.000000 [SCHED   ] [I] [ {(90 * k) % 1024:5d}.0] Slot decisions" for k in range(20)]
        r = nr_summary.sim_ratio(lines)
        self.assertEqual(r["source"], "srsran")
        self.assertAlmostEqual(r["sim_ratio"], 0.9, places=2)

    def test_none_and_honest(self):
        self.assertIsNone(nr_summary.sim_ratio(["no slots"])["sim_ratio"])
        self.assertEqual(nr_summary.honest(200.0, 4.0), 50.0)
        self.assertEqual(nr_summary.honest(80.0, 0.9), 80.0)
        self.assertEqual(nr_summary.honest(80.0, None), 80.0)

    def test_summary_has_ratio_and_air(self):
        s = {"bits_per_second": 120e6, "retransmits": 0}
        doc = {"intervals": [{"sum": {"bits_per_second": 120e6}}] * 3, "end": {"sum_received": s, "sum_sent": s}}
        with tempfile.TemporaryDirectory() as d:
            for dr in ("dl", "ul"):
                json.dump(doc, open(os.path.join(d, f"pair1_{dr}.json"), "w"))
            json.dump({"sim_ratio": 2.0}, open(os.path.join(d, "ratio_dl.json"), "w"))
            r = nr_summary.summarize(d, 1, 50)
            self.assertEqual(r["dirs"]["dl"]["sim_ratio"], 2.0)
            self.assertEqual(r["dirs"]["dl"]["air_mbps"], 60.0)
            self.assertEqual(r["dirs"]["dl"]["air_per_pair_mbps"][1], 60.0)
            self.assertIsNone(r["dirs"]["ul"]["sim_ratio"])
            self.assertEqual(r["dirs"]["ul"]["air_mbps"], 120.0)


class Health(unittest.TestCase):
    def test_udp_goodput_from_loss_iperf39(self):
        import nr_summary as n
        self.assertAlmostEqual(n.mbps({"end": {"sum": {"bits_per_second": 300e6, "lost_percent": 20.0}}}), 240.0)
        self.assertEqual(n.mbps({"end": {"sum_received": {"bits_per_second": 2e8}, "sum": {"bits_per_second": 3e8}}}), 200.0)
        self.assertEqual(n.mbps({"end": {"sum": {"bits_per_second": 1e8}}}), 100.0)  # TCP

    def test_oai_rlf_patterns(self):
        import tempfile
        d = tempfile.mkdtemp()
        open(f"{d}/oai-gnb.out", "w").write("x [NR_MAC] I Frame.Slot 0.0\nUE 1: Detected UL Failure on PUSCH\n")
        # OAI false positives for the srsRAN patterns: RLC release at shutdown, "cumulated bad DCI"
        open(f"{d}/ue1.out", "w").write("RRC Released RLC entity lc_id=1\nstats sfn: 1.0, cumulated bad DCI 0\n")
        src = open(os.path.join(SA, "nr-health.sh")).read().replace("L=/var/log/lab5g/sa", f"L={d}")
        open(f"{d}/h.sh", "w").write(src)
        out = subprocess.run(["bash", f"{d}/h.sh", "rlf", "1"], capture_output=True, text=True).stdout
        self.assertIn('"rlf_events":1,', out); self.assertIn('"late_underflow_lines":0,', out)


class RunDry(unittest.TestCase):
    def run_sh(self, *args, **env):
        e = dict(os.environ, DRY_RUN="1", NPROC="12", LOG_DIR=tempfile.mkdtemp(), OAI_GNB_IMAGE=IMG_G, OAI_UE_IMAGE=IMG_U)
        e.update(env)
        return subprocess.run(["bash", os.path.join(SA, "oai-run.sh"), *args], env=e, capture_output=True, text=True)

    def test_order_bindsto_rt_digest(self):
        r = self.run_sh("start", "3")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = r.stdout
        g = out.index("--unit=lab5g-oai-gnb"); w = out.index("wait NGSetupResponse")
        u1 = out.index("--unit=lab5g-nr1-ue"); u3 = out.index("--unit=lab5g-nr3-ue")
        self.assertTrue(g < w < u1 < u3)
        self.assertEqual(out.count("BindsTo=lab5g-oai-gnb.service"), 3)
        self.assertNotIn("Restart=on-failure", out)
        self.assertIn("--network host", out)          # native SCTP, no shim
        self.assertNotIn("LD_PRELOAD", out)
        self.assertIn("--cap-add SYS_NICE --ulimit rtprio=99", out)
        self.assertIn("uecap_ports2.xml --ue-nb-ant-rx 2 --ue-nb-ant-tx 2", out)
        self.assertIn(IMG_G, out); self.assertIn(IMG_U, out)
        self.assertIn("--cpuset-cpus 2-11", out)
        self.assertEqual(out.count("ip route replace default dev oaitun_ue1"), 3)

    def test_rejects(self):
        self.assertEqual(self.run_sh("start", "1", OAI_RF="zmq").returncode, 2)
        self.assertEqual(self.run_sh("start", "4").returncode, 2)
        self.assertEqual(self.run_sh("start", "1", OAI_GNB_IMAGE="oai-gnb:latest").returncode, 2)

    def test_vrtsim_and_no_rt(self):
        r = self.run_sh("start", "1", OAI_RF="vrtsim", OAI_TIMESCALE="0.5", OAI_RT="0", OAI_MIMO="1")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--vrtsim.timescale 0.5", r.stdout)
        self.assertIn("--ipc host", r.stdout)
        self.assertNotIn("SYS_NICE", r.stdout)
        self.assertIn("uecap_ports1.xml", r.stdout)

    def test_vrtsim_multi_ue(self):
        # vrtsim v3.0.0: server declares num_ues + per-UE antennas (else assert ue.tx_ant == tx_num_channels), UE gets ue_id
        r = self.run_sh("start", "3", OAI_RF="vrtsim")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--vrtsim.num_ues 3", r.stdout)
        for k in range(3):
            self.assertIn(f"--vrtsim.ue_config.[{k}].antennas 2x2", r.stdout)
            self.assertIn(f"--vrtsim.ue_id {k}", r.stdout)

    def test_keepalive_per_ue(self):
        # keepalive units are created after the UEs; DRY prints them via run()
        r = self.run_sh("start", "2")
        self.assertEqual(r.stdout.count("--unit=lab5g-nr"), 4)  # 2 UE units + 2 keepalives
        self.assertEqual(r.stdout.count("keepalive -p Restart=always"), 2)
        src = open(os.path.join(SA, "oai-run.sh")).read()
        self.assertIn("--unit=lab5g-nr$i-keepalive\" -p Restart=always", src)

    def test_config_dry(self):
        with tempfile.TemporaryDirectory() as d:
            e = dict(os.environ, DRY_RUN="1", OUT_DIR=d, PAIRENV=os.path.join(d, "p.env"), OAI_SRC_DIR=os.path.join(d, "src"))
            r = subprocess.run(["bash", os.path.join(SA, "oai-config.sh"), "3"], env=e, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("fetch ci-scripts/conf_files/gnb.sa.band78.106prb.rfsim.conf", r.stdout)
            r = subprocess.run(["bash", os.path.join(SA, "oai-config.sh"), "4"], env=e, capture_output=True, text=True)
            self.assertEqual(r.returncode, 2)

    def test_upstream_pins(self):
        src = open(os.path.join(SA, "oai-config.sh")).read()
        self.assertIn("OAI_TAG=v3.0.0", src)
        self.assertEqual(src.count(" ") > 0 and len([l for l in src.splitlines() if l.endswith(tuple("0123456789abcdef")) and len(l.split()[-1]) == 64]), 3)


if __name__ == "__main__":
    unittest.main()
