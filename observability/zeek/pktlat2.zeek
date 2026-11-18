##! poc-phase3: latency per paket ASLI secara waktu nyata.
##! - Ring buffer per flow kabel (UE 10.45.0.0/16 -> :443) per arah: segmen (off byte stream, len, ts pertama per tap s1u/s5s8/sgi, teid).
##! - Probe MGLT v2 (UDP -> sink :9001) dari app v0.9 berisi record per write (UL) / read (DL) app; diproses sekali di tap SGi.
##! - Pemasangan per byte -> pktlat.log (one_way per paket per tap, ms, skew dikoreksi option skew_s), dedupe kiriman ulang,
##!   miss dicatat; pktlat_stats.log tiap 10 s (memori/counter).
##! one_way UL = ts_tap - t_ue - skew_s ; DL = t_ue(read) - ts_tap + skew_s ; skew_s = off_vm - off_emu (55-skew, file Config).

module PKTLAT2;

export {
    redef enum Log::ID += { LOG, STATS };
    ## off_vm - off_emu (detik), diperbarui live lewat Config framework (file skew.cfg, ditulis 70/72)
    option skew_s: double = 0.0;
    ## id run (mis. p3-run-YYYYmmdd-HHMMSS), diperbarui live lewat file Config yg sama (ditulis 72/73); kosong = "live"
    option run_id: string = "live";
    const probe_ports: set[port] = { 9001/udp } &redef;
    const ue_net: set[subnet] = { 10.45.0.0/16 } &redef;
    const ports: set[port] = { 443/tcp } &redef;
    const probe_vlan = 109 &redef;          ##< probe diproses di salinan SGi (tap terakhir UL)
    const ring_ttl = 10sec &redef;          ##< segmen lebih tua dari ini dibuang
    const ring_max = 8192 &redef;           ##< maks segmen per flow per arah
    const max_total_segs = 200000 &redef;   ##< batas global segmen di semua ring (~ < 100 MiB); lewat batas -> seg_drop
    const max_flows = 4096 &redef;
    const flow_idle = 60sec &redef;
    const recheck_after = 1sec &redef;      ##< UL record yg belum terlihat di semua tap dicek ulang sekali
    const map_window = 2.0 &redef;
    const map_delay = 300msec &redef;       ##< tunda pemasangan fid baru (kumpulkan fid lain ke dst sama)          ##< detik: SYN kabel harus dalam [t_conn+skew-0.05, +map_window]
    const stats_every = 10sec &redef;
    ## --- v2.1 QUIC (UDP/443): kunci per paket = hash md5(payload UDP[0:qhash_n])[0:8 B]; payload QUIC tidak berubah lewat slirp/SNAT/GTP
    const tcp_on = F &redef;                ##< v2.1: TCP tidak dibuffer per paket (probe per paket hanya QUIC)
    const quic_ports: set[port] = { 443/udp } &redef;
    const cgn_net: set[subnet] = { 100.64.0.0/10 } &redef;  ##< alamat publik-semu CGNAT (salinan egress di tap SGi)
    const qhash_n = 64 &redef;
    const q_ttl = 10sec &redef;             ##< umur entri ring QUIC
    const q_max = 200000 &redef;            ##< batas global entri (lewat -> q_drop)

    type Info: record {
        ts:       time   &log;            ##< waktu diproses (jam VM)
        fid:      string &log;
        wire:     string &log &optional;  ##< o>r flow kabel (setelah SNAT UE)
        dir:      string &log;            ##< UL / DL
        kind:     string &log;            ##< UL: write (record app) ; DL: seg (segmen kabel)
        off:      count  &log;
        len:      count  &log;
        t_ue:     time   &log;            ##< UL: waktu write app ; DL: waktu read app (jam emulator)
        ow_s1u:   double &log &optional;  ##< ms, terkoreksi; UL = byte terakhir write ; DL = byte terakhir segmen
        ow_s5s8:  double &log &optional;
        ow_sgi:   double &log &optional;
        ow_s1u_first: double &log &optional; ##< UL: byte pertama write di S1-U
        aux_ms:   double &log &optional;  ##< UL: durasi write ; DL: read -> tulis ke tun0 (Chrome)
        teid:     count  &log &optional;  ##< TEID S1-U
        status:   string &log;            ##< ok | miss:<tap..> | nomap | expired
        resend:   bool   &log;            ##< record dipakai dari kiriman ulang (asli hilang)
        pseq:     count  &log;
        skew:     double &log;
        ## --- v2.1 (skema stabil utk dashboard ClickHouse/Grafana; field lama tidak diubah) ---
        run_id:   string &log &default="live";
        flow:     string &log &optional;  ##< "<dst ip:port>#<fid>" (fallback fid)
        seg:      string &log &optional;  ##< tap tempat one_way diukur: sgi (default) | s5s8 | s1u (fallback bila tap lebih jauh miss)
        one_way:  double &log &optional;  ##< ms, skew dikoreksi; UL = app->tap ; DL = tap->app (= ow_<seg>)
        proto:    string &log &default="tcp"; ##< tcp | quic
        flow_id:  string &log &optional;  ##< = fid (id flow app)
        qhash:    string &log &optional;  ##< QUIC: hash 64-bit payload (hex)
        ow_cgnat: double &log &optional;  ##< QUIC: app -> egress CGNAT (100.64.x, tap SGi setelah SNAT) / sebaliknya DL
    };
    type Stats: record {
        ts: time &log; flows: count &log; segs: count &log; mapped: count &log; pending: count &log;
        probes: count &log; probe_bytes: count &log; probe_dup: count &log; crc_bad: count &log;
        recs: count &log; rec_dup: count &log; rec_resend_used: count &log;
        ul_ok: count &log; ul_miss: count &log; ul_retry: count &log; dl_ok: count &log;
        dl_unmatched_evicted: count &log; nomap: count &log; flow_drop: count &log; evicted: count &log;
        seg_drop: count &log; mem_mb: count &log;
        q_pkts: count &log &default=0; q_idx: count &log &default=0; q_ul_ok: count &log &default=0; q_dl_ok: count &log &default=0;
        q_miss: count &log &default=0; q_drop: count &log &default=0; q_flows: count &log &default=0;
    };
}

redef udp_content_delivery_ports_orig += { [9001/udp] = T, [443/udp] = T };
redef udp_content_delivery_ports_resp += { [443/udp] = T };

type Seg: record {
    off: count; len: count; t0: time;
    t1: time &optional; t5: time &optional; t9: time &optional;
    teid: count &optional; done: bool &default=F;
};
type WFlow: record {
    o: string; r: string;
    isn_ul: count &optional; isn_dl: count &optional; syn_ts: time &optional;
    ul: vector of Seg; dl: vector of Seg; ins: count &default=0;
    fid: string &optional;
};
type Rec: record { typ: count; flags: count; len: count; off: count; t: time; aux: count; };

global st: table[string] of count &default=0;
global nseg = 0;
global wflows: table[string] of WFlow &read_expire=60sec &expire_func=function(t: table[string] of WFlow, k: string): interval
    {
    local w = t[k];
    nseg = nseg >= |w$ul| + |w$dl| ? nseg - |w$ul| - |w$dl| : 0;
    if ( w?$fid )
        for ( i in w$dl ) if ( ! w$dl[i]$done && w$dl[i]?$t9 ) ++st["dl_unmatched_evicted"];
    return 0secs;
    };
global by_dst: table[string] of set[string] &read_expire=120sec;
global fmap: table[string] of string &read_expire=120sec;          # fid -> kunci flow kabel
global seen_probe: set[string, count] &create_expire=30sec;
global seen_rec: set[string, count, count] &create_expire=30sec;   # fid, typ, off
global pend: table[string] of vector of string &create_expire=10sec; # fid -> probe belum terpasang
global pend_try: table[string] of count &default=0 &create_expire=10sec;

global ul_retry: event(fid: string, r: Rec, resend: bool, pseq: count);
global map_retry: event(fid: string);

function u(s: string, off: count, len: count): count { return bytestring_to_count(s[off:off+len], F); }
function ns2t(tns: count): time { return double_to_time((tns / 1000000000) * 1.0 + (tns % 1000000000) / 1e9); }

event zeek_init() &priority=5
    {
    Log::create_stream(PKTLAT2::LOG, [$columns=Info, $path="pktlat"]);
    Log::create_stream(PKTLAT2::STATS, [$columns=Stats, $path="pktlat_stats"]);
    }

# ---------------------------------------------------------------- frame mentah
type PF: record { vlan: int &default=-1; teid: count &optional; aseq: count &optional; };
function parse_frame(): PF
    {
    local r = PF();
    local d = get_current_packet()$data;
    local n = |d|;
    if ( n < 34 ) return r;
    local et = u(d, 12, 2);
    local off = 14;
    if ( et == 0x8100 || et == 0x88a8 ) { r$vlan = u(d, 14, 2) % 4096; et = u(d, 16, 2); off = 18; }
    if ( et != 0x0800 || n < off + 40 ) return r;
    if ( u(d, off + 6, 2) % 8192 != 0 ) return r;   # fragmen lanjutan: tanpa header GTP/TCP
    local l4 = off + (u(d, off, 1) % 16) * 4;
    local ipo = off;
    if ( u(d, off + 9, 1) == 17 && n >= l4 + 16 && u(d, l4 + 2, 2) == 2152 )
        {
        local g = l4 + 8;
        r$teid = u(d, g + 4, 4);
        local gi = g + 8;
        if ( u(d, g, 1) % 8 != 0 )
            {
            local nxt = u(d, g + 11, 1);
            gi = g + 12;
            while ( nxt != 0 && gi < n )
                {
                local el = u(d, gi, 1) * 4;
                if ( el == 0 ) break;
                nxt = u(d, gi + el - 1, 1);
                gi += el;
                }
            }
        ipo = gi;
        }
    if ( n >= ipo + 20 && u(d, ipo + 9, 1) == 6 )
        {
        local th = ipo + (u(d, ipo, 1) % 16) * 4;
        if ( n >= th + 8 ) r$aseq = u(d, th + 4, 4);
        }
    return r;
    }

function tapcode(vlan: int): count
    {
    if ( vlan == 102 ) return 1;
    if ( vlan == 105 ) return 5;
    if ( vlan == 109 ) return 9;
    return 0;
    }

# ---------------------------------------------------------------- ring buffer
## indeks terbesar i dgn v[i]$off <= b, atau -1
function idx_le(v: vector of Seg, b: count): int
    {
    local lo: int = 0; local hi: int = |v|;      # cari pertama off > b
    while ( lo < hi )
        {
        local mid = (lo + hi) / 2;
        if ( v[mid]$off <= b ) lo = mid + 1; else hi = mid;
        }
    return lo - 1;
    }
function find(v: vector of Seg, b: count): int
    {
    local i = idx_le(v, b);
    if ( i >= 0 && v[i]$off + v[i]$len > b ) return i;
    return -1;
    }
function set_tap(s: Seg, tap: count, ts: time, teid: count, has_teid: bool)
    {
    if ( tap == 1 ) { if ( ! s?$t1 || ts < s$t1 ) s$t1 = ts; if ( has_teid ) s$teid = teid; }
    else if ( tap == 5 ) { if ( ! s?$t5 || ts < s$t5 ) s$t5 = ts; }
    else if ( tap == 9 ) { if ( ! s?$t9 || ts < s$t9 ) s$t9 = ts; }
    }
function ring_add(v: vector of Seg, off: count, len: count, tap: count, ts: time, pf: PF)
    {
    local n = |v|;
    local has = pf?$teid;
    local te = has ? pf$teid : 0;
    if ( n == 0 || off > v[n - 1]$off )
        {
        if ( nseg >= max_total_segs ) { ++st["seg_drop"]; return; }
        ++nseg;
        local s = Seg($off=off, $len=len, $t0=ts);
        set_tap(s, tap, ts, te, has);
        v += s;
        return;
        }
    local i = idx_le(v, off);
    if ( i >= 0 && v[i]$off == off )
        {
        if ( len > v[i]$len ) v[i]$len = len;
        set_tap(v[i], tap, ts, te, has);
        return;
        }
    # sisip di tengah (jarang: out-of-order antar tap): append lalu geser
    if ( nseg >= max_total_segs ) { ++st["seg_drop"]; return; }
    ++nseg;
    local s2 = Seg($off=off, $len=len, $t0=ts);
    set_tap(s2, tap, ts, te, has);
    v += s2;
    local j: int = |v| - 1;
    while ( j > 0 && v[j - 1]$off > off )
        {
        local tmp = v[j - 1]; v[j - 1] = v[j]; v[j] = tmp;
        --j;
        }
    }
function evict(w: WFlow)
    {
    local lim = network_time() - ring_ttl;
    for ( dd in set("ul", "dl") )
        {
        local v = dd == "ul" ? w$ul : w$dl;
        local k = 0;
        while ( k < |v| && v[k]$t0 < lim ) ++k;
        if ( |v| > k + ring_max ) k = |v| - ring_max;
        if ( k == 0 ) next;
        local i = 0;
        if ( dd == "dl" && w?$fid )
            while ( i < k ) { if ( ! v[i]$done && v[i]?$t9 ) ++st["dl_unmatched_evicted"]; ++i; }
        st["evicted"] += k;
        nseg = nseg >= k ? nseg - k : 0;
        if ( dd == "ul" ) w$ul = v[k:|v|]; else w$dl = v[k:|v|];
        }
    }

event tcp_packet(c: connection, is_orig: bool, flags: string, seq: count, ack: count, len: count, payload: string)
    {
    if ( ! tcp_on || c$id$resp_p !in ports || c$id$orig_h !in ue_net )
        return;
    local syn = /S/ in flags;
    if ( len == 0 && ! syn ) return;
    local pf = parse_frame();
    local tap = tapcode(pf$vlan);
    if ( tap == 0 ) return;
    local o = fmt("%s:%d", c$id$orig_h, port_to_count(c$id$orig_p));
    local r = fmt("%s:%d", c$id$resp_h, port_to_count(c$id$resp_p));
    local k = o + ">" + r;
    if ( k !in wflows )
        {
        if ( |wflows| >= max_flows ) { ++st["flow_drop"]; return; }
        local ve: vector of Seg = vector();
        local ve2: vector of Seg = vector();
        wflows[k] = WFlow($o=o, $r=r, $ul=ve, $dl=ve2);
        if ( r !in by_dst ) by_dst[r] = set();
        add by_dst[r][k];
        }
    local w = wflows[k];
    local now = network_time();
    if ( syn )
        {
        if ( pf?$aseq )
            {
            if ( is_orig && /A/ !in flags ) { if ( ! w?$isn_ul ) w$isn_ul = pf$aseq; }
            else if ( ! is_orig ) { if ( ! w?$isn_dl ) w$isn_dl = pf$aseq; }
            }
        if ( is_orig && /A/ !in flags && tap == 1 && ! w?$syn_ts ) w$syn_ts = now;
        if ( len == 0 ) return;
        }
    local off = seq - 1;
    if ( pf?$aseq )
        {
        if ( is_orig && w?$isn_ul ) off = (pf$aseq + 4294967296 - w$isn_ul - 1) % 4294967296;
        else if ( ! is_orig && w?$isn_dl ) off = (pf$aseq + 4294967296 - w$isn_dl - 1) % 4294967296;
        }
    if ( is_orig ) ring_add(w$ul, off, len, tap, now, pf); else ring_add(w$dl, off, len, tap, now, pf);
    w$ins += 1;
    if ( w$ins % 256 == 0 ) evict(w);
    }

# ---------------------------------------------------------------- probe
global fid_dst: table[string] of string &read_expire=120sec;
function wlog(x: Info)
    {
    x$run_id = run_id; x$flow_id = x$fid;
    x$flow = x$fid in fid_dst ? fid_dst[x$fid] + "#" + x$fid : x$fid;
    if ( x?$ow_sgi ) { x$seg = "sgi"; x$one_way = x$ow_sgi; }
    else if ( x?$ow_s5s8 ) { x$seg = "s5s8"; x$one_way = x$ow_s5s8; }
    else if ( x?$ow_s1u ) { x$seg = "s1u"; x$one_way = x$ow_s1u; }
    Log::write(PKTLAT2::LOG, x);
    }

function ow_ul(ts: time, t: time): double { return (interval_to_double(ts - t) - skew_s) * 1000.0; }
function ow_dl(ts: time, t: time): double { return (interval_to_double(t - ts) + skew_s) * 1000.0; }

function do_ul(fid: string, w: WFlow, r: Rec, resend: bool, pseq: count, final: bool): bool
    {
    local v = w$ul;
    local last = r$off + (r$len > 0 ? r$len - 1 : 0);
    local i1 = find(v, r$off);
    local i2 = find(v, last);
    local miss = "";
    local x = Info($ts=network_time(), $fid=fid, $wire=w$o + ">" + w$r, $dir="UL", $kind="write", $off=r$off, $len=r$len,
                   $t_ue=r$t, $aux_ms=r$aux / 1000.0, $status="ok", $resend=resend, $pseq=pseq, $skew=skew_s);
    if ( i1 < 0 || i2 < 0 ) miss = "s1u,s5s8,sgi";
    else
        {
        local a = v[i1]; local b = v[i2];
        if ( b?$t1 ) x$ow_s1u = ow_ul(b$t1, r$t); else miss += "s1u,";
        if ( b?$t5 ) x$ow_s5s8 = ow_ul(b$t5, r$t); else miss += "s5s8,";
        if ( b?$t9 ) x$ow_sgi = ow_ul(b$t9, r$t); else miss += "sgi,";
        if ( a?$t1 ) x$ow_s1u_first = ow_ul(a$t1, r$t);
        if ( b?$teid ) x$teid = b$teid;
        }
    if ( miss != "" && ! final ) return F;
    if ( miss != "" ) { x$status = "miss:" + miss; ++st["ul_miss"]; } else ++st["ul_ok"];
    wlog(x);
    return T;
    }

event ul_retry(fid: string, r: Rec, resend: bool, pseq: count)
    {
    if ( fid !in fmap || fmap[fid] !in wflows )
        {
        wlog(Info($ts=network_time(), $fid=fid, $dir="UL", $kind="write", $off=r$off, $len=r$len, $t_ue=r$t,
                   $status="expired", $resend=resend, $pseq=pseq, $skew=skew_s));
        return;
        }
    do_ul(fid, wflows[fmap[fid]], r, resend, pseq, T);
    }

function do_dl(fid: string, w: WFlow, r: Rec, resend: bool, pseq: count)
    {
    local v = w$dl;
    if ( |v| == 0 || r$len == 0 ) return;
    local end = r$off + r$len - 1;
    local j = find(v, r$off);
    if ( j < 0 ) j = idx_le(v, r$off) + 1;
    while ( j < |v| && v[j]$off + v[j]$len - 1 <= end )
        {
        local s = v[j];
        if ( ! s$done && s$off + s$len - 1 >= r$off )
            {
            s$done = T;
            local x = Info($ts=network_time(), $fid=fid, $wire=w$o + ">" + w$r, $dir="DL", $kind="seg", $off=s$off, $len=s$len,
                           $t_ue=r$t, $aux_ms=r$aux / 1000.0, $status="ok", $resend=resend, $pseq=pseq, $skew=skew_s);
            local miss = "";
            if ( s?$t1 ) x$ow_s1u = ow_dl(s$t1, r$t); else miss += "s1u,";
            if ( s?$t5 ) x$ow_s5s8 = ow_dl(s$t5, r$t); else miss += "s5s8,";
            if ( s?$t9 ) x$ow_sgi = ow_dl(s$t9, r$t); else miss += "sgi,";
            if ( s?$teid ) x$teid = s$teid;
            if ( miss != "" ) x$status = "miss:" + miss;
            ++st["dl_ok"];
            wlog(x);
            }
        ++j;
        }
    }

function parse_recs(p: string): vector of Rec
    {
    local res: vector of Rec = vector();
    local nrec = u(p, 33, 1);
    local rl = u(p, 34, 1);
    local i = 0;
    while ( i < nrec )
        {
        local o = 52 + i * rl;
        if ( |p| < o + 20 ) break;
        res += Rec($typ=u(p, o, 1), $flags=u(p, o + 1, 1), $len=u(p, o + 2, 2), $off=u(p, o + 4, 4), $t=ns2t(u(p, o + 8, 8)), $aux=u(p, o + 16, 4));
        ++i;
        }
    return res;
    }

## Pemasangan fid app <-> flow kabel (dst sama), dijalankan map_delay setelah probe pertama supaya fid lain yg connect hampir
## bersamaan ke dst yg sama ikut dipertimbangkan. Urutan dijaga: fid diurutkan t_conn, flow kabel diurutkan SYN di S1-U
## (SYN dari app lewat bearer FIFO yg sama -> urutan connect() == urutan SYN kabel). Flow kabel dipilih bila SYN dalam jendela
## [t_conn+skew-0.05 s, +map_window] dan (bila fid punya record UL) minimal 1 record UL (off,len) cocok di S1-U dgn latensi
## [-20 ms, 500 ms] -> flow app lain di luar VPN (non-Chrome) dilewati.
type PMeta: record { dst: string; tconn: time; };
global pend_meta: table[string] of PMeta &create_expire=15sec;
function ul_score(w: WFlow, fid: string): count
    {
    local score = 0;
    for ( qi in pend[fid] )
        {
        local recs = parse_recs(pend[fid][qi]);
        for ( i in recs )
            {
            local r = recs[i];
            if ( r$typ != 1 ) next;
            local j = find(w$ul, r$off);
            if ( j < 0 || ! w$ul[j]?$t1 || w$ul[j]$off != r$off ) next;
            local l = interval_to_double(w$ul[j]$t1 - r$t) - skew_s;
            if ( l > -0.02 && l < 0.5 ) ++score;
            }
        }
    return score;
    }
function has_ul(fid: string): bool
    {
    for ( qi in pend[fid] )
        {
        local recs = parse_recs(pend[fid][qi]);
        for ( i in recs ) if ( recs[i]$typ == 1 ) return T;
        }
    return F;
    }
function cmp_fid(a: string, b: string): int
    {
    local x = pend_meta[a]$tconn; local y = pend_meta[b]$tconn;
    return x < y ? -1 : (x > y ? 1 : 0);
    }
function cmp_wire(a: string, b: string): int
    {
    local x = wflows[a]$syn_ts; local y = wflows[b]$syn_ts;
    return x < y ? -1 : (x > y ? 1 : 0);
    }
function resolve_dst(dst: string)
    {
    if ( dst !in by_dst ) return;
    local fids: vector of string = vector();
    for ( pf in pend_meta ) if ( pf !in fmap && pf in pend && pend_meta[pf]$dst == dst ) fids += pf;
    local wires: vector of string = vector();
    for ( k in by_dst[dst] ) if ( k in wflows && ! wflows[k]?$fid && wflows[k]?$syn_ts ) wires += k;
    if ( |fids| == 0 || |wires| == 0 ) return;
    sort(fids, cmp_fid);
    sort(wires, cmp_wire);
    local wi = 0;
    for ( fi in fids )
        {
        local ff = fids[fi];
        local texp = pend_meta[ff]$tconn + double_to_interval(skew_s);
        local need = has_ul(ff);
        local j = wi;
        while ( j < |wires| )
            {
            local w = wflows[wires[j]];
            local dt = interval_to_double(w$syn_ts - texp);
            if ( dt > map_window ) break;
            if ( dt >= -0.05 && ( ! need || ul_score(w, ff) > 0 ) )
                {
                fmap[ff] = wires[j]; w$fid = ff; wi = j + 1;
                break;
                }
            ++j;
            }
        }
    }

function process(fid: string, p: string)
    {
    local w = wflows[fmap[fid]];
    local pseq = u(p, 12, 4);
    local recs = parse_recs(p);
    for ( i in recs )
        {
        local r = recs[i];
        local resend = r$flags % 2 == 1;
        if ( [fid, r$typ, r$off] in seen_rec ) { if ( resend ) ++st["rec_dup"]; next; }
        add seen_rec[fid, r$typ, r$off];
        ++st["recs"];
        if ( resend ) ++st["rec_resend_used"];
        if ( r$typ == 1 )
            {
            if ( ! do_ul(fid, w, r, resend, pseq, F) ) { ++st["ul_retry"]; schedule recheck_after { PKTLAT2::ul_retry(fid, r, resend, pseq) }; }
            }
        else if ( r$typ == 2 )
            do_dl(fid, w, r, resend, pseq);
        }
    }

function flush_pend(fid: string)
    {
    if ( fid !in pend || fid !in fmap ) return;
    if ( fmap[fid] in wflows )
        for ( i in pend[fid] ) process(fid, pend[fid][i]);
    delete pend[fid];
    }

event map_retry(fid: string)
    {
    if ( fid !in pend ) return;
    if ( fid !in fmap && fid in pend_meta )
        {
        local dst = pend_meta[fid]$dst;
        resolve_dst(dst);
        for ( mf in pend_meta ) if ( pend_meta[mf]$dst == dst && mf in fmap && mf in pend ) flush_pend(mf);
        }
    if ( fid in fmap ) { flush_pend(fid); return; }
    pend_try[fid] += 1;
    if ( pend_try[fid] >= 5 )
        {
        for ( i in pend[fid] ) st["nomap"] += |parse_recs(pend[fid][i])|;
        delete pend[fid];
        return;
        }
    schedule 1sec { PKTLAT2::map_retry(fid) };
    }

# ---------------------------------------------------------------- v2.1 QUIC (hash payload)
## Ring per flow UDP/443 UE: diimplementasikan sbg indeks global hash -> QSeg (TTL q_ttl, batas q_max) + hitungan per flow (qflows).
type QSeg: record { flow: string; len: count; t0: time; t1: time &optional; t5: time &optional; t9: time &optional;
                    tc: time &optional; teid: count &optional; ue: bool &default=F; };
global qidx: table[string] of QSeg &create_expire=q_ttl;          # key = "U|D" + hash16
global qflows: table[string] of count &default=0 &read_expire=60sec;
global seen_qrec: set[string, count, string] &create_expire=30sec;  # fid, typ, hash
global q_retry: event(fid: string, typ: count, h: string, len: count, t: time, resend: bool, pseq: count, dst: string);
function qhash(p: string): string { return md5_hash(|p| > qhash_n ? p[0:qhash_n] : p)[0:16]; }

event udp_contents(c: connection, is_orig: bool, contents: string)
    {
    if ( c$id$resp_p !in quic_ports ) return;
    local o = c$id$orig_h;
    local cg = o in cgn_net;
    if ( o !in ue_net && ! cg ) return;
    local pf = parse_frame();
    local tap = tapcode(pf$vlan);
    if ( tap == 0 || ( cg && tap != 9 ) ) return;
    ++st["q_pkts"];
    local k = (is_orig ? "U" : "D") + qhash(contents);
    local ts = network_time();
    if ( k !in qidx )
        {
        if ( |qidx| >= q_max ) { ++st["q_drop"]; return; }
        local fl = fmt("%s:%d>%s:%d", o, port_to_count(c$id$orig_p), c$id$resp_h, port_to_count(c$id$resp_p));
        qidx[k] = QSeg($flow=fl, $len=|contents|, $t0=ts);
        }
    local s = qidx[k];
    if ( cg ) { if ( ! s?$tc ) s$tc = ts; return; }
    if ( ! s$ue )   # entri dibuat dari salinan CGNAT (DL tiba di egress dulu) -> label flow pakai 5-tuple UE
        {
        s$ue = T;
        s$flow = fmt("%s:%d>%s:%d", o, port_to_count(c$id$orig_p), c$id$resp_h, port_to_count(c$id$resp_p));
        ++qflows[s$flow];
        }
    if ( tap == 1 ) { if ( ! s?$t1 ) s$t1 = ts; if ( pf?$teid ) s$teid = pf$teid; }
    else if ( tap == 5 ) { if ( ! s?$t5 ) s$t5 = ts; }
    else if ( tap == 9 ) { if ( ! s?$t9 ) s$t9 = ts; }
    }

function do_q(fid: string, typ: count, h: string, len: count, t: time, resend: bool, pseq: count, dst: string, final: bool): bool
    {
    local ul = typ == 1;
    local k = (ul ? "U" : "D") + h;
    local x = Info($ts=network_time(), $fid=fid, $dir=ul ? "UL" : "DL", $kind="quic", $off=0, $len=len, $t_ue=t,
                   $status="ok", $resend=resend, $pseq=pseq, $skew=skew_s, $proto="quic", $qhash=h);
    fid_dst[fid] = dst;
    local miss = "";
    if ( k !in qidx ) miss = "nohash";
    else
        {
        local s = qidx[k];
        x$wire = s$flow;
        if ( s?$t1 ) x$ow_s1u = ul ? ow_ul(s$t1, t) : ow_dl(s$t1, t); else miss += "s1u,";
        if ( s?$t5 ) x$ow_s5s8 = ul ? ow_ul(s$t5, t) : ow_dl(s$t5, t); else miss += "s5s8,";
        if ( s?$t9 ) x$ow_sgi = ul ? ow_ul(s$t9, t) : ow_dl(s$t9, t); else miss += "sgi,";
        if ( s?$tc ) x$ow_cgnat = ul ? ow_ul(s$tc, t) : ow_dl(s$tc, t);
        if ( s?$teid ) x$teid = s$teid;
        }
    if ( miss != "" && ! final ) return F;
    if ( miss != "" ) { x$status = "miss:" + miss; ++st["q_miss"]; }
    else if ( ul ) ++st["q_ul_ok"]; else ++st["q_dl_ok"];
    wlog(x);
    return T;
    }

event q_retry(fid: string, typ: count, h: string, len: count, t: time, resend: bool, pseq: count, dst: string)
    { do_q(fid, typ, h, len, t, resend, pseq, dst, T); }

## Record v2.1 (20 B): 0 type u8 (1 U, 2 D, 4 X) | 1 flags (bit0 kiriman ulang) | 2 len u16 (payload UDP) | 4 hash 8 B | 12 t_ue_ns u64
function process_q(fid: string, p: string, pseq: count)
    {
    local dst = fmt("%s:%d", count_to_v4_addr(u(p, 42, 4)), u(p, 46, 2));
    local nrec = u(p, 33, 1);
    local rl = u(p, 34, 1);
    local i = 0;
    while ( i < nrec )
        {
        local o = 52 + i * rl;
        ++i;
        if ( |p| < o + 20 ) break;
        local typ = u(p, o, 1);
        if ( typ != 1 && typ != 2 ) next;
        local fl = u(p, o + 1, 1);
        local h = bytestring_to_hexstr(p[o + 4:o + 12]);
        ++st["recs"];
        if ( [fid, typ, h] in seen_qrec ) { ++st["rec_dup"]; next; }
        add seen_qrec[fid, typ, h];
        local resend = fl % 2 == 1;
        if ( resend ) ++st["rec_resend_used"];
        local t = ns2t(u(p, o + 12, 8));
        local len = u(p, o + 2, 2);
        if ( ! do_q(fid, typ, h, len, t, resend, pseq, dst, F) )
            { ++st["ul_retry"]; schedule recheck_after { PKTLAT2::q_retry(fid, typ, h, len, t, resend, pseq, dst) }; }
        }
    }

event udp_contents(c: connection, is_orig: bool, contents: string)
    {
    if ( ! is_orig || c$id$resp_p !in probe_ports || |contents| < 52 || contents[0:4] != "MGLT" || u(contents, 4, 1) != 2 )
        return;
    local pf = parse_frame();
    if ( pf$vlan != probe_vlan ) return;
    local fid = fmt("%08x", u(contents, 8, 4));
    local pseq = u(contents, 12, 4);
    if ( [fid, pseq] in seen_probe ) { ++st["probe_dup"]; return; }
    add seen_probe[fid, pseq];
    if ( MGLT::crc32c(contents[0:48]) != u(contents, 48, 4) ) { ++st["crc_bad"]; return; }
    ++st["probes"]; st["probe_bytes"] += |contents|;
    if ( u(contents, 5, 1) % 4 >= 2 ) { process_q(fid, contents, pseq); return; }   # v2.1: mode hash (QUIC)
    if ( fid !in fmap )
        {
        if ( fid !in pend )
            {
            local q: vector of string = vector(); pend[fid] = q;
            fid_dst[fid] = fmt("%s:%d", count_to_v4_addr(u(contents, 42, 4)), u(contents, 46, 2));
            pend_meta[fid] = PMeta($dst=fmt("%s:%d", count_to_v4_addr(u(contents, 42, 4)), u(contents, 46, 2)), $tconn=ns2t(u(contents, 24, 8)));
            schedule map_delay { PKTLAT2::map_retry(fid) };
            }
        local q2 = pend[fid];
        q2 += contents;
        return;
        }
    if ( fmap[fid] !in wflows ) { st["nomap"] += u(contents, 33, 1); return; }
    if ( fid in pend ) flush_pend(fid);
    process(fid, contents);
    }

event stats_tick()
    {
    local segs = 0;
    for ( k, w in wflows ) segs += |w$ul| + |w$dl|;
    local ru = get_proc_stats();
    Log::write(PKTLAT2::STATS, Stats($ts=network_time(), $flows=|wflows|, $segs=segs, $mapped=|fmap|, $pending=|pend|,
        $probes=st["probes"], $probe_bytes=st["probe_bytes"], $probe_dup=st["probe_dup"], $crc_bad=st["crc_bad"],
        $recs=st["recs"], $rec_dup=st["rec_dup"], $rec_resend_used=st["rec_resend_used"],
        $ul_ok=st["ul_ok"], $ul_miss=st["ul_miss"], $ul_retry=st["ul_retry"], $dl_ok=st["dl_ok"],
        $dl_unmatched_evicted=st["dl_unmatched_evicted"], $nomap=st["nomap"], $flow_drop=st["flow_drop"], $evicted=st["evicted"],
        $seg_drop=st["seg_drop"], $mem_mb=ru$mem / 1048576,
        $q_pkts=st["q_pkts"], $q_idx=|qidx|, $q_ul_ok=st["q_ul_ok"], $q_dl_ok=st["q_dl_ok"], $q_miss=st["q_miss"], $q_drop=st["q_drop"],
        $q_flows=|qflows|));
    schedule stats_every { stats_tick() };
    }
event zeek_init() &priority=-5 { schedule stats_every { stats_tick() }; }
