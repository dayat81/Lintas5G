#!/usr/bin/env python3
"""Box/vm-obs: pkthash.log (one dir per tap: <zeek_dir>/<tap>/pkthash.log) + phases.tsv -> CSV for ClickHouse.
usage: pkt-prep.py <out_dir> <session> <zeek_dir> <phases.tsv>
Output: pkt_tap.csv, pkt_phase.csv, and pkt_conn.csv when a Zeek conn.log is present.
No payload, no subscriber identity (hash + 5-tuple of the UE test flows only)."""
import csv, glob, os, sys
out, sess, zd, phases = sys.argv[1:5]
os.makedirs(out, exist_ok=True)
def zeek(fn):
    f = None
    for line in open(fn, errors='ignore'):
        if line.startswith('#fields'): f = line.rstrip('\n').split('\t')[1:]; continue
        if line.startswith('#') or not f: continue
        yield dict(zip(f, line.rstrip('\n').split('\t')))
n = 0
with open(f"{out}/pkt_tap.csv", 'w', newline='') as fo:
    w = csv.writer(fo); w.writerow(['session', 'run_id', 'tap', 'dir', 'proto', 'flow', 'h', 'len', 'ts', 'teid', 'qfi'])
    for fn in sorted(glob.glob(f"{zd}/*/pkthash*.log") + glob.glob(f"{zd}/pkthash*.log")):
        for o in zeek(fn):
            g = lambda k: '' if o.get(k, '-') in ('-', '(empty)') else o[k]
            w.writerow([sess, o['run_id'], o['tap'], o['dir'], o['proto'], o['flow'], o['h'], o['len'], o['ts'], g('teid'), g('qfi')]); n += 1
with open(f"{out}/pkt_phase.csv", 'w', newline='') as fo:
    w = csv.writer(fo); w.writerow(['session', 'run_id', 'cond', 'rep', 't_start', 't_end'])
    for line in open(phases):
        p = line.rstrip('\n').split('\t')
        if len(p) >= 5: w.writerow([sess] + p[:5])
# Optional conn.log (n6 or run-dir copy) -> pkt_conn.csv
cn = 0
conn_files = sorted(set(glob.glob(f"{zd}/**/conn.log", recursive=True) + glob.glob(f"{zd}/conn.log")))
if conn_files:
    with open(f"{out}/pkt_conn.csv", 'w', newline='') as fo:
        w = csv.writer(fo); w.writerow(['session','run_id','ts','proto','orig_h','orig_p','resp_h','resp_p','duration','orig_bytes','resp_bytes','conn_state'])
        for fn in conn_files:
            for o in zeek(fn):
                def g(k, d='0'):
                    v = o.get(k, o.get(k.replace('.', '.'), '-'))
                    return d if v in ('-', '(empty)', '', None) else v
                w.writerow([sess, g('run_id', ''), g('ts'), g('proto', ''),
                            g('id.orig_h', ''), g('id.orig_p', '0'), g('id.resp_h', ''), g('id.resp_p', '0'),
                            g('duration', '0'), g('orig_bytes', '0'), g('resp_bytes', '0'), g('conn_state', '')])
                cn += 1
print(f"pkt_tap rows={n} pkt_conn rows={cn}", out)
