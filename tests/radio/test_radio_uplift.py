import json, os, subprocess, sys, tempfile, unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SA = os.path.join(ROOT, "infra", "gcp", "sa")
sys.path.insert(0, SA)
import nr_cpu_plan, nr_summary, core_load_plan  # noqa: E402


class CpuPlan(unittest.TestCase):
    def cpus(self, p):
        out = set(p["core"].split(","))
        seen = list(p["core"].split(","))
        for v in p["pairs"].values():
            for k in ("gnb", "ue"):
                seen += v[k].split(",")
        return seen

    def test_no_overlap_and_full_cover(self):
        for n in (1, 2, 3, 4):
            p = nr_cpu_plan.plan(12, n)
            seen = self.cpus(p)
            self.assertEqual(len(seen), len(set(seen)), n)
            self.assertEqual(sorted(map(int, seen)), list(range(12)), n)

    def test_three_pairs_12vcpu(self):
        p = nr_cpu_plan.plan(12, 3)
        self.assertEqual(p["pairs"][1], {"gnb": "2,3", "ue": "4"})
        self.assertEqual(p["core"], "0,1,11")  # leftover CPU goes to the core side

    def test_gnb_gets_more_by_default(self):
        p = nr_cpu_plan.plan(12, 2)
        for v in p["pairs"].values():
            self.assertGreaterEqual(len(v["gnb"].split(",")), len(v["ue"].split(",")))
        p = nr_cpu_plan.plan(12, 2, heavy="ue")
        for v in p["pairs"].values():
            self.assertGreaterEqual(len(v["ue"].split(",")), len(v["gnb"].split(",")))

    def test_too_small_and_bad_pairs(self):
        with self.assertRaises(ValueError): nr_cpu_plan.plan(6, 3)
        with self.assertRaises(ValueError): nr_cpu_plan.plan(12, 5)

    def test_four_pairs_12vcpu(self):
        p = nr_cpu_plan.plan(12, 4)
        self.assertEqual(p["pairs"][4], {"gnb": "8", "ue": "9"})
        self.assertEqual(p["core"], "0,1,10,11")


def fake_iperf(mbps, n=3, udp=False):
    s = {"bits_per_second": mbps * 1e6, "retransmits": 0}
    return {"intervals": [{"sum": {"bits_per_second": mbps * 1e6}} for _ in range(n)],
            "end": {"sum": s} if udp else {"sum_received": s, "sum_sent": s}}


class Summary(unittest.TestCase):
    def write(self, d, name, doc):
        with open(os.path.join(d, name), "w") as f: json.dump(doc, f)

    def test_four_pairs_threshold(self):
        with tempfile.TemporaryDirectory() as d:
            for i in (1, 2, 3, 4):
                self.write(d, f"pair{i}_dl.json", fake_iperf(26)); self.write(d, f"pair{i}_ul.json", fake_iperf(26))
            self.write(d, "cpu_dl.json", {"mean_busy_pct": 70.0})
            r = nr_summary.summarize(d, 4, 20)
            self.assertEqual(r["dirs"]["dl"]["aggregate_mbps"], 104.0)
            self.assertIn("dl aggregate 104.0 < 170.0", r["reasons"])

    def test_pass_three_pairs(self):
        with tempfile.TemporaryDirectory() as d:
            for i in (1, 2, 3):
                self.write(d, f"pair{i}_dl.json", fake_iperf(55)); self.write(d, f"pair{i}_ul.json", fake_iperf(60))
            self.write(d, "cpu_dl.json", {"mean_busy_pct": 70.0})
            r = nr_summary.summarize(d, 3, 50)
            self.assertEqual(r["verdict"], "PASS", r["reasons"])
            self.assertEqual(r["dirs"]["dl"]["aggregate_mbps"], 165.0)

    def test_fail_slow_pair_and_aggregate(self):
        with tempfile.TemporaryDirectory() as d:
            self.write(d, "pair1_dl.json", fake_iperf(55)); self.write(d, "pair2_dl.json", fake_iperf(30))
            r = nr_summary.summarize(d, 2, 50)
            self.assertEqual(r["verdict"], "FAIL")
            self.assertTrue(any("pair2" in x for x in r["reasons"]))
            self.assertTrue(any("aggregate" in x for x in r["reasons"]))

    def test_fail_missing_and_cpu(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(nr_summary.summarize(d, 1, 50)["verdict"], "FAIL")
            self.write(d, "pair1_dl.json", fake_iperf(55)); self.write(d, "cpu_dl.json", {"mean_busy_pct": 90.0})
            r = nr_summary.summarize(d, 1, 50)
            self.assertEqual(r["verdict"], "FAIL"); self.assertTrue(any("cpu" in x for x in r["reasons"]))

    def test_cpu_sample(self):
        seq = iter([{"cpu0": (100, 50)}, {"cpu0": (200, 100)}, {"cpu0": (300, 100)}])
        r = nr_summary.cpu_sample(2, reader=lambda: next(seq), sleep=lambda s: None, procs=None)
        self.assertEqual(r["mean_busy_pct"], 75.0)  # 50% then 100%
        self.assertEqual(r["max_sec_busy_pct"], 100.0)


class ProcCpu(unittest.TestCase):
    def test_proc_cpu(self):
        self.assertEqual(nr_summary.proc_cpu({"gnb1": 0, "x": 0}, {"gnb1": 200, "x": 1}, 2), {"gnb1": 100.0})

    def test_live_procs_runs(self):
        self.assertIsInstance(nr_summary._procs(), dict)


class Render(unittest.TestCase):
    def test_pairs_render_dry(self):
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, DRY_RUN="1", OUT_DIR=d)
            r = subprocess.run(["bash", os.path.join(SA, "nr-pairs-config.sh"), "4"], env=env, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            ports, binds, pcis, imsis = set(), set(), set(), set()
            for i in (1, 2, 3, 4):
                g = open(f"{d}/pair{i}/gnb.yaml").read(); u = open(f"{d}/pair{i}/ue.conf").read()
                self.assertNotIn("__", g + u)
                self.assertEqual(oct(os.stat(f"{d}/pair{i}/ue.conf").st_mode & 0o777), "0o600")
                ports.add(g.split("tx_port=tcp://127.0.0.1:")[1].split(",")[0])
                binds.add(g.split("bind_addr: ")[1].split()[0]); pcis.add(g.split("pci: ")[1].split()[0])
                imsis.add([l for l in u.splitlines() if l.startswith("imsi")][0])
                self.assertIn(f"netns = ue{i}", u)
                # UE tx = gNB rx and vice versa
                tx = g.split("tx_port=tcp://127.0.0.1:")[1].split(",")[0]; rx = g.split("rx_port=tcp://127.0.0.1:")[1].split(",")[0]
                self.assertIn(f"tx_port=tcp://127.0.0.1:{rx},rx_port=tcp://127.0.0.1:{tx}", u)
            self.assertEqual((len(ports), len(binds), len(pcis), len(imsis)), (4, 4, 4, 4))
            self.assertIn("2030", open(f"{d}/pair4/gnb.yaml").read())
            self.assertIn("tun_srsue\n", open(f"{d}/pair1/ue.conf").read() + "\n")  # legacy tap name kept
            self.assertIn("2000", open(f"{d}/pair1/gnb.yaml").read())

    def test_bad_n(self):
        r = subprocess.run(["bash", os.path.join(SA, "nr-pairs-config.sh"), "5"], env=dict(os.environ, DRY_RUN="1"), capture_output=True)
        self.assertNotEqual(r.returncode, 0)

    def test_run_renders_missing_pair_configs(self):
        # bootstrap gap (GCP 19 Nov): nr_pairs=1 boot never rendered pair<i>/ -> "start N" must render them first
        with tempfile.TemporaryDirectory() as d:
            r = subprocess.run(["bash", os.path.join(SA, "nr-pairs-run.sh"), "start", "4"],
                               env=dict(os.environ, DRY_RUN="1", NPROC="12", CONF_DIR=d), capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("pair1 config missing -> nr-pairs-config.sh 4", r.stdout)
            self.assertLess(r.stdout.index("nr-pairs-config.sh 4"), r.stdout.index("--unit=lab5g-nr1-gnb"))
            self.assertIn("--unit=lab5g-nr4-ue", r.stdout); self.assertIn("tcp :2030 listening", r.stdout)
            os.makedirs(f"{d}/pair1"); open(f"{d}/pair1/gnb.yaml", "w").write("x"); open(f"{d}/pair1/ue.conf", "w").write("x")
            r = subprocess.run(["bash", os.path.join(SA, "nr-pairs-run.sh"), "start", "1"],
                               env=dict(os.environ, DRY_RUN="1", NPROC="12", CONF_DIR=d), capture_output=True, text=True)
            self.assertNotIn("config missing", r.stdout)

    def test_run_dry_commands(self):
        r = subprocess.run(["bash", os.path.join(SA, "nr-pairs-run.sh"), "start", "3"],
                           env=dict(os.environ, DRY_RUN="1", NPROC="12"), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.count("lab5g-nr"), r.stdout.count("lab5g-nr"))
        for i in (1, 2, 3):
            self.assertIn(f"--unit=lab5g-nr{i}-gnb", r.stdout); self.assertIn(f"--unit=lab5g-nr{i}-ue", r.stdout)
        self.assertIn("taskset -c 2,3,4,5,6,7,8,9,10 /opt/srsran/bin/gnb", r.stdout)  # default NR_PIN=0: shared RAN CPUs
        r1 = subprocess.run(["bash", os.path.join(SA, "nr-pairs-run.sh"), "start", "3"],
                            env=dict(os.environ, DRY_RUN="1", NPROC="12", NR_PIN="1"), capture_output=True, text=True)
        self.assertIn("taskset -c 2,3 /opt/srsran/bin/gnb", r1.stdout)
        # ZMQ REQ/REP lock-step: gNB before UE, UE BindsTo gNB, no per-process auto restart (19 Nov offline fix)
        for i in (1, 2, 3):
            g = r.stdout.index(f"--unit=lab5g-nr{i}-gnb"); u = r.stdout.index(f"--unit=lab5g-nr{i}-ue")
            self.assertLess(g, r.stdout.index(f"wait 'gNB started' in /var/log/lab5g/sa/gnb{i}.out"))
            self.assertLess(g, u); self.assertIn(f"BindsTo=lab5g-nr{i}-gnb.service", r.stdout)
        self.assertNotIn("Restart=on-failure", r.stdout)
        self.assertIn("tcp :2020 listening", r.stdout)

    def test_static_pcc_opt_in(self):
        for f in ("sa-config.sh", "nr-pairs-config.sh"):
            t = open(os.path.join(SA, f)).read()
            self.assertIn("SA_STATIC_PCC:-0", t); self.assertNotIn("pcc_rule:[pcc]", t)
        for f in ("sa-run.sh", "nr-pairs-run.sh"):
            self.assertIn("zmq_pair_up", open(os.path.join(SA, f)).read())


class CoreLoad(unittest.TestCase):
    def test_render(self):
        with tempfile.TemporaryDirectory() as d:
            lay = core_load_plan.render(4, d, "a" * 32, "b" * 32)
            self.assertEqual(len({x["bind"] for x in lay}), 4)
            self.assertEqual(len({x["gnb_cpu"] for x in lay} | {x["ue_cpu"] for x in lay}), 8)
            self.assertEqual(oct(os.stat(f"{d}/ue1.yaml").st_mode & 0o777), "0o600")
            self.assertIn("127.0.2.3", open(f"{d}/gnb3.yaml").read())
            with self.assertRaises(ValueError): core_load_plan.render(7, d, "a", "b")

    def test_dry_runner(self):
        r = subprocess.run(["bash", os.path.join(SA, "core-load-ueransim.sh"), "2", tempfile.mkdtemp()],
                           env=dict(os.environ, DRY_RUN="1"), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr); self.assertIn("lab5g-cl2-ue", r.stdout)


class ZeekBpf(unittest.TestCase):
    def test_n3_bpf_multi_host(self):
        src = open(os.path.join(ROOT, "infra", "gcp", "sesi-d", "zeek-taps.sh")).read()
        self.assertIn("N3_EXCLUDE_ZMQ", src); self.assertIn("udp port 2152 and ($N3_H)", src)
        self.assertNotIn('"udp port 2152 and host $ENB"', src)


if __name__ == "__main__":
    unittest.main()
