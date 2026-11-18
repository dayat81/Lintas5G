#!/usr/bin/env python3
"""Box: ubah salinan log lokal Sesi B/C -> CSV untuk batch load ClickHouse (vm-obs).
Usage: obs-prep.py <out_dir> <session>=<dir_nf_logs>[:<dir_zeek>] ...  (dir_nf berisi *-ping.txt, *-http.csv, *-iperf-*.json, adapter.log)
Tidak ada IMSI/KEY di output (log sudah disanitasi di VM)."""
import sys, os, re, csv, json, glob
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W = {k: csv.writer(open(f"{out}/{k}.csv", 'w', newline='')) for k in ['probes', 'adapter', 'iperf', 'zeek_conn', 'zeek_capture_loss', 'zeek_tunnel']}
W['probes'].writerow(['session', 'cond', 'rep', 'metric', 'seq', 'value_ms', 'ok'])
W['adapter'].writerow(['session', 'ts', 'event', 'qod_id', 'source', 'apply_ms', 'remove_ms', 'reserve_ms', 'gbr_kbps'])
W['iperf'].writerow(['session', 'cond', 'rep', 'dir', 't_end_s', 'mbps'])
W['zeek_conn'].writerow(['session', 'ifc', 'ts', 'uid', 'orig_h', 'orig_p', 'resp_h', 'resp_p', 'proto', 'service', 'duration', 'orig_bytes', 'resp_bytes', 'conn_state', 'orig_pkts', 'resp_pkts', 'tunnel_parents'])
W['zeek_capture_loss'].writerow(['session', 'ifc', 'ts', 'ts_delta', 'peer', 'gaps', 'acks', 'percent_lost'])
W['zeek_tunnel'].writerow(['session', 'ifc', 'ts', 'uid', 'orig_h', 'orig_p', 'resp_h', 'resp_p', 'tunnel_type', 'action'])
def split(lbl):
    m = re.match(r'(.+)-r(\d+)$', lbl); return (m.group(1), int(m.group(2))) if m else (lbl, 0)
def zeek(fn):
    f = None
    for line in open(fn, errors='ignore'):
        if line.startswith('#fields'): f = line.rstrip('\n').split('\t')[1:]; continue
        if line.startswith('#') or not f: continue
        yield dict(zip(f, line.rstrip('\n').split('\t')))
z0 = lambda v: '' if v in ('-', '(empty)', None) else v
for arg in sys.argv[2:]:
    sess, rest = arg.split('=', 1); nf, _, zd = rest.partition(':')
    for fn in sorted(glob.glob(f"{nf}/*-ping.txt")):
        lbl = os.path.basename(fn)[:-9]; c, r = split(lbl)
        if lbl.startswith('keepalive'): continue
        for m in re.finditer(r'icmp_seq=(\d+) .*?time=([\d.]+) ms', open(fn).read()):
            W['probes'].writerow([sess, c, r, 'ping_rtt', m.group(1), m.group(2), 1])
    for fn in sorted(glob.glob(f"{nf}/*-http.csv")):
        lbl = os.path.basename(fn)[:-9]; c, r = split(lbl)
        for i, row in enumerate(csv.reader(open(fn))):
            if len(row) < 7: continue
            ok = 1 if row[6] == '200' else 0
            try: W['probes'].writerow([sess, c, r, 'http_ttfb', i, round(float(row[4]) * 1000, 3), ok])
            except ValueError: pass
    for fn in sorted(glob.glob(f"{nf}/*-iperf-*.json")):
        b = os.path.basename(fn)[:-5]; lbl, d = b.rsplit('-iperf-', 1); c, r = split(lbl)
        try: j = json.load(open(fn))
        except Exception: continue
        for iv in j.get('intervals', []):
            s = iv.get('sum', {}); W['iperf'].writerow([sess, c, r, d, round(s.get('end', 0), 1), round(s.get('bits_per_second', 0) / 1e6, 3)])
    ap = f"{nf}/adapter.log"
    if os.path.exists(ap):
        for line in open(ap):
            try: o = json.loads(line)
            except Exception: continue
            W['adapter'].writerow([sess, o.get('ts', '').replace(' ', 'T'), o.get('event'), o.get('id', ''), o.get('source', ''), o.get('apply_ms', ''), o.get('remove_ms', ''), o.get('reserve_ms', ''), o.get('gbr_kbps', '')])
    if zd:
        for ifdir in sorted(glob.glob(f"{zd}/*")):
            ifc = os.path.basename(ifdir)
            if os.path.exists(f"{ifdir}/conn.log"):
                for o in zeek(f"{ifdir}/conn.log"):
                    W['zeek_conn'].writerow([sess, ifc, o['ts'], o['uid'], o['id.orig_h'], o['id.orig_p'], o['id.resp_h'], o['id.resp_p'], o['proto'], z0(o.get('service')), z0(o.get('duration')) or 0,
                                             z0(o.get('orig_bytes')) or 0, z0(o.get('resp_bytes')) or 0, o.get('conn_state', ''), z0(o.get('orig_pkts')) or 0, z0(o.get('resp_pkts')) or 0, z0(o.get('tunnel_parents'))])
            if os.path.exists(f"{ifdir}/capture_loss.log"):
                for o in zeek(f"{ifdir}/capture_loss.log"):
                    W['zeek_capture_loss'].writerow([sess, ifc, o['ts'], o['ts_delta'], o['peer'], o['gaps'], o['acks'], o['percent_lost']])
            if os.path.exists(f"{ifdir}/tunnel.log"):
                for o in zeek(f"{ifdir}/tunnel.log"):
                    W['zeek_tunnel'].writerow([sess, ifc, o['ts'], z0(o.get('uid')), o['id.orig_h'], o['id.orig_p'], o['id.resp_h'], o['id.resp_p'], o.get('tunnel_type', ''), o.get('action', '')])
print("OK", out)
