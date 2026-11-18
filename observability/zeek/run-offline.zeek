# poc-phase3: offline/selftest (zeek -r) = mglt + pktraw + pktlat2. skew lewat argumen: PKTLAT2::skew_s=<detik>
@load ./run-local.zeek
@load ./pktlat.zeek
@load ./pktlat2.zeek
redef PKTLAT::log_path = "pktraw";
