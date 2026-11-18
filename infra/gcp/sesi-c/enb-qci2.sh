#!/bin/bash
# srsenb rb.conf.example hanya punya QCI 7 & 9 -> E-RAB Setup dedicated bearer QCI 2 (Rx VIDEO) ditolak
# dengan S1AP cause radioNetwork 37 (not-supported-QCI-value). Tambah qci_config QCI 2 (RLC UM, mirip QCI 7).
C=/opt/lab5g/srsran/conf/rb.conf
grep -q "qci = 2;" $C || python3 - "$C" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
blk='''qci_config = (
{
  qci = 2;
  pdcp_config = { discard_timer = 150; pdcp_sn_size = 12; }
  rlc_config = { ul_um = { sn_field_length = 10; }; dl_um = { sn_field_length = 10; t_reordering = 45; }; };
  logical_channel_config = { priority = 4; prioritized_bit_rate = -1; bucket_size_duration = 100; log_chan_group = 1; };
  enb_specific = { dl_max_retx_thresh = 32; };
},
'''
s=s.replace('qci_config = (\n', blk, 1); open(p,'w').write(s)
PY
grep -n "qci = " $C
