# Sesi D lab: pktlat2.zeek v2.1 on the VLAN-tagged fan-in iface (pktlat0).
# ZEEKPATH must include observability/zeek (mglt.zeek, pktlat2.zeek) and this directory.
# vlan_fivetuple keeps the three tap copies of the same 5-tuple as distinct connections.
@load base/frameworks/logging
@load base/frameworks/tunnels
@load base/frameworks/config
@load base/protocols/conn
@load policy/protocols/conn/vlan-logging
@load frameworks/conn_key/vlan_fivetuple
@load mglt
@load pktlat2
redef LogAscii::use_json = T;
redef Log::default_rotation_interval = 0secs;
redef PKTLAT2::tcp_on = F;
# skew.cfg is written by the runner (Core vs emulator clock). Live reload via Config.
redef Config::config_files += { "/var/log/lab5g/pktlat/skew.cfg" };

hook Conn::log_policy(rec: Conn::Info, id: Log::ID, filter: Log::Filter)
    {
    if ( rec$id$resp_p !in MGLT::ports && rec$id$resp_p !in PKTLAT2::quic_ports
         && rec$id$resp_p != 443/tcp )
        break;
    }

event zeek_init() &priority=-10
    {
    local off: set[Log::ID] = set();
    for ( id in Log::active_streams )
        if ( id != MGLT::LOG && id != Conn::LOG && id != PKTLAT2::LOG && id != PKTLAT2::STATS && id != Config::LOG )
            add off[id];
    for ( id in off )
        Log::disable_stream(id);
    }
