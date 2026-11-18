# poc-phase3: instance live poc-phase2-zeek-mglt = mglt (marker v1) + pktraw (per paket mentah, validasi PoC) + pktlat2 (waktu nyata).
# Rollback: 61-zeek-pktlat.sh start (mode 2b) / 53-zeek-start.sh (mode fase 2).
@load ./run-local.zeek
@load ./pktlat.zeek
@load ./pktlat2.zeek
redef PKTLAT::log_path = "pktraw";
# v2.1 (QUIC): TCP tidak dibuffer/dilog per paket (pktraw mati, PKTLAT2::tcp_on=F). Mode TCP v0.9: ubah dua baris ini ke T.
redef PKTLAT::enable = F;
redef PKTLAT2::tcp_on = F;
redef Config::config_files += { "skew.cfg" };
hook Conn::log_policy(rec: Conn::Info, id: Log::ID, filter: Log::Filter)
    {
    if ( rec$id$resp_p !in MGLT::ports && rec$id$resp_p !in PKTLAT2::quic_ports && ! ( rec$id$resp_p in PKTLAT::ports && rec$id$orig_h in PKTLAT::ue_net ) )
        break;
    }
event zeek_init() &priority=-10
    {
    local off: set[Log::ID] = set();
    for ( id in Log::active_streams )
        if ( id != MGLT::LOG && id != Conn::LOG && id != PKTLAT::LOG && id != PKTLAT2::LOG && id != PKTLAT2::STATS && id != Config::LOG )
            add off[id];
    for ( id in off )
        Log::disable_stream(id);
    }
