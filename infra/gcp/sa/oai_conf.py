#!/usr/bin/env python3
"""OAI (ran_mode=sa-oai) config rendering. No secrets on argv: UE IMSI/K/OPC come from env (IMSI, K, OPC).

  oai_conf.py gnb --base <upstream gnb.sa.band78.106prb.rfsim.conf> --out <gnb.conf> [--mimo 2] [--amf 127.0.0.5] [--bind 127.0.1.1]
  IMSI=.. K=.. OPC=.. oai_conf.py ue --out <ue.conf> [--dnn internet] [--sst 1]

Base = OAI v3.0.0 rfsim config (n78 TDD 30 kHz 106 PRB = 40 MHz), fetched at a pinned tag + sha256 by oai-config.sh
(not vendored). Changes: PLMN 001/01 + SST 1 (no SD) like the lab Open5GS, AMF + N2/N3 bind, log levels, and
(mimo=2) pdsch_AntennaPorts_XP/pusch_AntennaPorts 2, nb_tx/nb_rx 2, CSI-RS + periodic SRS (RI/PMI, UL rank 2).
256QAM needs no gNB change (default on); the UE enables it via --uecap_file (FAKTA offline 19 Nov 2026).
"""
import argparse
import os
import re
import sys

PLMN = 'plmn_list = ({ mcc = 001; mnc = 01; mnc_length = 2; snssaiList = ({ sst = 1 }) });'


def _sub(pat, repl, s, count=0):
    out, n = re.subn(pat, repl, s, count=count)
    if n == 0:
        raise ValueError(f"pattern not found in base config: {pat}")
    return out


def render_gnb(base, mimo=2, amf="127.0.0.5", bind="127.0.1.1", tac=1):
    s = _sub(r"plmn_list\s*=\s*\(\{.*?\}\);", PLMN, base, 1)
    s = _sub(r"tracking_area_code\s*=\s*\d+;", f"tracking_area_code  =  {tac};", s, 1)
    s = _sub(r'amf_ip_address\s*=\s*\(\{\s*ipv4\s*=\s*"[^"]*";\s*\}\);', f'amf_ip_address = ({{ ipv4 = "{amf}"; }});', s, 1)
    s = _sub(r'(GNB_IPV4_ADDRESS_FOR_NG_AMF\s*=\s*)"[^"]*"', rf'\1"{bind}"', s, 1)
    s = _sub(r'(GNB_IPV4_ADDRESS_FOR_NGU\s*=\s*)"[^"]*"', rf'\1"{bind}"', s, 1)
    s = re.sub(r'(f1ap_log_level\s*=\s*)"debug"', r'\1"info"', s)
    if mimo == 2:
        s = _sub(r"(\n\s*min_rxtxtime\s*=\s*\d+;)", r'\1\n    pdsch_AntennaPorts_XP = 2;\n    pusch_AntennaPorts = 2;\n'
                 r'    do_CSIRS = 1;\n    do_SRS = "periodic";', s, 1)
        s = _sub(r"nb_tx\s*=\s*1", "nb_tx          = 2", s, 1)
        s = _sub(r"nb_rx\s*=\s*1", "nb_rx          = 2", s, 1)
    elif mimo != 1:
        raise ValueError("mimo must be 1 or 2")
    return s


def render_ue(imsi, k, opc, dnn="internet", sst=1):
    for name, v, n in (("IMSI", imsi, 15), ("K", k, 32), ("OPC", opc, 32)):
        if not v or len(v) != n or not re.fullmatch(r"[0-9a-fA-F]+", v):
            raise ValueError(f"{name} missing or malformed")
    return (f'uicc0 = {{\n  imsi = "{imsi}";\n  key = "{k}";\n  opc= "{opc}";\n'
            f'  pdu_sessions = ({{ dnn = "{dnn}"; nssai_sst = {sst}; }});\n}}\n')


def main(argv=None):
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    g = sp.add_parser("gnb"); g.add_argument("--base", required=True); g.add_argument("--out", required=True)
    g.add_argument("--mimo", type=int, default=2); g.add_argument("--amf", default="127.0.0.5"); g.add_argument("--bind", default="127.0.1.1")
    u = sp.add_parser("ue"); u.add_argument("--out", required=True); u.add_argument("--dnn", default="internet"); u.add_argument("--sst", type=int, default=1)
    a = ap.parse_args(argv)
    if a.cmd == "gnb":
        txt = render_gnb(open(a.base).read(), a.mimo, a.amf, a.bind)
        mode = 0o644
    else:
        txt = render_ue(os.environ.get("IMSI", ""), os.environ.get("K", ""), os.environ.get("OPC", ""), a.dnn, a.sst)
        mode = 0o600
    fd = os.open(a.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(txt)
    os.chmod(a.out, mode)
    print(f"{a.cmd} config written: {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
