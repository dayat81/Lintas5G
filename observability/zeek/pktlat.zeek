##! poc-phase2b: log per paket TCP (header saja) untuk flow UE (10.45.0.0/16) -> port 443, di semua tap mirror0
##! (S1-U & S5/S8 dalam GTP-U, SGi polos). Dipakai untuk memasangkan paket ASLI Chrome dengan pktlog app (byte offset).
##! rel_seq = seq relatif Zeek (byte data pertama = 1); aseq = seq absolut dari frame mentah (inner TCP), isn dihitung di analisis.

module PKTLAT;

export {
    redef enum Log::ID += { LOG };
    const ue_net: set[subnet] = { 10.45.0.0/16 } &redef;
    const ports: set[port] = { 443/tcp } &redef;
    ## log juga paket tanpa payload (ACK murni)? SYN/FIN/RST selalu dilog.
    const log_pure_ack = F &redef;
    ## v3: path stream mentah per paket (fase 2b: "pktlat"; fase 3: "pktraw", nama pktlat dipakai log waktu nyata)
    const log_path = "pktlat" &redef;
    ## v3: matikan log mentah per paket (deployment) -> F
    const enable = T &redef;

    type Info: record {
        ts:    time   &log;
        uid:   string &log;
        vlan:  int    &log &optional;
        seg:   string &log &optional;
        teid:  count  &log &optional;
        dir:   string &log;          ##< UL = UE->server (orig), DL = server->UE
        o:     string &log;          ##< orig ip:port (UE setelah SNAT)
        r:     string &log;          ##< resp ip:port
        fl:    string &log;          ##< flag TCP (Zeek)
        rseq:  count  &log;          ##< seq relatif (Zeek)
        aseq:  count  &log &optional;##< seq absolut (frame mentah)
        rack:  count  &log;
        len:   count  &log;          ##< panjang payload TCP
        frag:  bool   &log &default=F; ##< paket luar ter-fragmentasi IP (GTP-U > MTU): frame = fragmen terakhir, tanpa header GTP
    };
}

function u(s: string, off: count, len: count): count
    {
    return bytestring_to_count(s[off:off+len], F);
    }

event zeek_init() &priority=5
    {
    Log::create_stream(PKTLAT::LOG, [$columns=Info, $path=log_path]);
    }

event tcp_packet(c: connection, is_orig: bool, flags: string, seq: count, ack: count, len: count, payload: string)
    {
    if ( ! enable || c$id$resp_p !in ports || c$id$orig_h !in ue_net )
        return;
    if ( len == 0 && ! log_pure_ack && /[SFR]/ !in flags )
        return;
    local r = Info($ts=network_time(), $uid=c$uid, $dir=is_orig ? "UL" : "DL",
                   $o=fmt("%s:%d", c$id$orig_h, port_to_count(c$id$orig_p)),
                   $r=fmt("%s:%d", c$id$resp_h, port_to_count(c$id$resp_p)),
                   $fl=flags, $rseq=seq, $rack=ack, $len=len);
    # frame mentah: Ethernet [+802.1Q] + IPv4 [+ UDP/2152 GTP-U + inner IPv4] + TCP
    local d = get_current_packet()$data;
    local n = |d|;
    if ( n >= 34 )
        {
        local et = u(d, 12, 2);
        local off = 14;
        if ( et == 0x8100 || et == 0x88a8 )
            {
            r$vlan = u(d, 14, 2) % 4096;
            et = u(d, 16, 2);
            off = 18;
            }
        if ( et == 0x0800 && n >= off + 40 )
            {
            local ihl = (u(d, off, 1) % 16) * 4;
            local l4 = off + ihl;
            local ipo = off;
            local fo = u(d, off + 6, 2);
            if ( fo % 8192 != 0 )   # fragmen lanjutan (offset > 0): header UDP/GTP/inner ada di fragmen pertama
                r$frag = T;
            if ( u(d, off + 9, 1) == 17 && n >= l4 + 16 && u(d, l4 + 2, 2) == 2152 )
                {
                local g = l4 + 8;
                local gf = u(d, g, 1);
                r$teid = u(d, g + 4, 4);
                local gi = g + 8;
                if ( gf % 8 != 0 )
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
                local ihl2 = (u(d, ipo, 1) % 16) * 4;
                if ( n >= ipo + ihl2 + 8 )
                    r$aseq = u(d, ipo + ihl2 + 4, 4);
                }
            }
        }
    if ( r?$vlan && r$vlan in MGLT::vlan_seg )
        r$seg = MGLT::vlan_seg[r$vlan] + ((r?$teid || (r$frag && (r$vlan == 102 || r$vlan == 105))) ? "(gtp)" : "");
    Log::write(PKTLAT::LOG, r);
    }
