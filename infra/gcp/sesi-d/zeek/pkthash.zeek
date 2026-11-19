##! Lintas5G Fase 0 closeout: per-packet tap-to-tap latency WITHOUT an app probe (derived from poc-latency pktlat2.zeek v2.1).
##! One Zeek process per tap on vm-core-ran (same host = same clock, no skew correction):
##!   tap=ue  tun_srsue in netns ue1 (UE side, before srsUE/radio for UL, after radio for DL)
##!   tap=n3  lo, GTP-U eNB/gNB <-> SGW-U/UPF (S1-U / N3): TEID + QFI (PDU Session Container) read from the outer frame
##!   tap=n6   ogstun (SGi / N6). AF_PACKET TX = after egress qdisc (DL post-HTB);
##!            ingress UL is before ifb0 shaping.
##!   tap=sgiq complementary shaper point (same label from two capture units):
##!            sgiq-dl = dummy receiving nft dup / tc mirror of ogstun POSTROUTING
##!            (DL pre-HTB); sgiq-ul = ifb0 TX after ifb0 HTB (UL post-shaper).
##!            Segment sgi-queue = n6↔sgiq (DL: t_n6 - t_sgiq; UL: t_sgiq - t_n6).
##! Key per packet = md5(L4 payload[0:qhash_n])[0:8]. QUIC payload (encrypted) is byte-identical at every tap: NAT/GTP only
##! touch headers; a QUIC retransmission carries a new packet number -> new hash. The JOIN across taps is done in ClickHouse
##! (poc_latency.v_pkt), not here, so each process stays tiny and stateless.
##! Limits: one-way between taps only (no app timestamp, no stream/request mapping for encrypted HTTP/3).
module PKTHASH;

export {
    redef enum Log::ID += { LOG };
    ## tap label, set on the command line: PKTHASH::tap=ue|n3|n6|sgiq
    const tap = "na" &redef;
    ## run/condition tags, updated live through the Config framework (file written by the runner, see zeek-taps.sh)
    option run_id: string = "live";
    option cond: string = "na";
    const ue_net: set[subnet] = { 10.45.0.0/16 } &redef;
    const udp_ports: set[port] = { 443/udp } &redef;    ##< QUIC/HTTP3 (+ e.g. 4789/udp GBR flow when redef'd)
    const tcp_ports: set[port] = { 443/tcp } &redef;    ##< TCP/443 (TRANSPORT=tcp-only / mixed); retransmits share a hash
    const qhash_n = 64 &redef;

    type Info: record {
        ts:     time   &log;   ##< packet capture time (host clock)
        tap:    string &log;
        dir:    string &log;   ##< UL (src in ue_net) / DL
        proto:  string &log;   ##< quic | udp | tcp
        flow:   string &log;   ##< "<ue ip:port>><remote ip:port>"
        h:      string &log;   ##< 64-bit payload hash (hex)
        len:    count  &log;   ##< L4 payload bytes
        teid:   count  &log &optional;
        qfi:    count  &log &optional;
        run_id: string &log;
        cond:   string &log;
    };
}

redef udp_content_delivery_ports_use_resp = T;   # key on the responder port for BOTH directions (DL packets have dport=UE port)
redef udp_content_delivery_ports_orig += { [443/udp] = T };
redef udp_content_delivery_ports_resp += { [443/udp] = T };

event zeek_init()
    {
    Log::create_stream(PKTHASH::LOG, [$columns=Info, $path="pkthash"]);
    for ( p in udp_ports )
        {
        udp_content_delivery_ports_orig[p] = T;
        udp_content_delivery_ports_resp[p] = T;
        }
    }

function bu(s: string, off: count, len: count): count { return bytestring_to_count(s[off:off+len], F); }

type GT: record { teid: count &optional; qfi: count &optional; };
## outer GTP-U header of the current frame (Ethernet/802.1Q on lo). Raw-IP links (tun) have no GTP -> empty.
function gtp_info(): GT
    {
    local r = GT();
    local d = get_current_packet()$data;
    local n = |d|;
    if ( n < 34 ) return r;
    local off = 0;
    if ( bu(d, 0, 1) / 16 != 4 )
        {
        local et = bu(d, 12, 2); off = 14;
        if ( et == 0x8100 || et == 0x88a8 ) { et = bu(d, 16, 2); off = 18; }
        if ( et != 0x0800 ) return r;
        }
    if ( n < off + 28 || bu(d, off + 9, 1) != 17 ) return r;
    local l4 = off + (bu(d, off, 1) % 16) * 4;
    if ( n < l4 + 16 || (bu(d, l4, 2) != 2152 && bu(d, l4 + 2, 2) != 2152) ) return r;
    local g = l4 + 8;
    local fl = bu(d, g, 1);
    r$teid = bu(d, g + 4, 4);
    if ( fl % 8 == 0 ) return r;                       # no E/S/PN -> no extension headers
    if ( (fl / 4) % 2 == 0 ) return r;                 # no E bit
    local nxt = bu(d, g + 11, 1);
    local e = g + 12;
    while ( nxt != 0 && e + 4 <= n )
        {
        local el = bu(d, e, 1) * 4;
        if ( el == 0 || e + el > n ) break;
        if ( nxt == 0x85 ) r$qfi = bu(d, e + 2, 1) % 64; # PDU Session Container: octet 3 low 6 bits = QFI
        nxt = bu(d, e + el - 1, 1);
        e += el;
        }
    return r;
    }

function emit(c: connection, is_orig: bool, payload: string, proto: string)
    {
    local src = is_orig ? c$id$orig_h : c$id$resp_h;
    local sp = is_orig ? c$id$orig_p : c$id$resp_p;
    local dst = is_orig ? c$id$resp_h : c$id$orig_h;
    local dp = is_orig ? c$id$resp_p : c$id$orig_p;
    local ul = src in ue_net;
    if ( ! ul && dst !in ue_net ) return;
    local flow = ul ? fmt("%s:%d>%s:%d", src, port_to_count(sp), dst, port_to_count(dp))
                    : fmt("%s:%d>%s:%d", dst, port_to_count(dp), src, port_to_count(sp));
    local n = |payload| < qhash_n ? |payload| : qhash_n;
    local x = Info($ts=network_time(), $tap=tap, $dir=ul ? "UL" : "DL", $proto=proto, $flow=flow,
                   $h=md5_hash(payload[0:n])[0:16], $len=|payload|, $run_id=run_id, $cond=cond);
    if ( tap == "n3" )
        {
        local g = gtp_info();
        if ( g?$teid ) x$teid = g$teid;
        if ( g?$qfi ) x$qfi = g$qfi;
        }
    Log::write(PKTHASH::LOG, x);
    }

event udp_contents(u: connection, is_orig: bool, contents: string)
    {
    if ( |contents| == 0 ) return;
    if ( u$id$resp_p !in udp_ports && u$id$orig_p !in udp_ports ) return;
    emit(u, is_orig, contents, (u$id$resp_p == 443/udp || u$id$orig_p == 443/udp) ? "quic" : "udp");
    }

event tcp_packet(c: connection, is_orig: bool, flags: string, seq: count, ack: count, len: count, payload: string)
    {
    if ( len == 0 || |tcp_ports| == 0 ) return;
    if ( c$id$resp_p !in tcp_ports && c$id$orig_p !in tcp_ports ) return;
    emit(c, is_orig, payload, "tcp");
    }
