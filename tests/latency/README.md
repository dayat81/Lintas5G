# tests/latency

| Skrip | Fungsi |
|---|---|
| `77-ue-quic-gen.py <skew_s> <out.json> [flows] [pkts] [gap_ms]` | Generator QUIC (long-header, 1200 B) di netns UE + probe MGLT v2.1 (mode hash). Env: `PROBE_SINK`, `PROBE_PORT`, `DNS_SERVER`, `UE_PRIV_IP`. |
| `78-compare-quic.py <gen.json> <pktlat.log...>` | Cakupan UL/DL dan p50/p90 per tap dibanding record yang dikirim. |
| `74-compare-rt.py <run-dir> [pktlat.log] [stats]` | Bandingkan hasil waktu nyata dengan analisis offline (TCP, legacy). |

Contoh:

```bash
sudo ip netns exec <ns-ue> env PROBE_SINK=<ip-sink-sgi> python3 77-ue-quic-gen.py 0.0 /tmp/gen.json 6 20 50
python3 78-compare-quic.py /tmp/gen.json /var/log/lab5g/zeek/pktlat.log
```
