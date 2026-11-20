# Lintas5G QoD booster lab: recommended stack (offline, box only)

| Part | Image / file | Notes |
|---|---|---|
| Core | `lintas5g/open5gs:2.8.0-qosrel` (container `n5-lab`) | Open5GS v2.8.0 built from source + `patches/open5gs-v2.8.0-upf-stale-qfi.diff`; pcf.yaml `qos_profiles` QOS_E/S/M/L/7 → 5QI 80/2/3/4/7; `/opt/lintas5g/core-up.sh` |
| DB | `mongo:6` (container `n5-mongo`, volume `n5-mongo-db`) | copy of the lab subscriber DB; **no secrets in images** |
| gNB (recommended) | `lintas5g/oai-gnb:v3.0.0-slice-qosrel3` + `SLICE=1` (`../slice/slice.conf`) | OAI v3.0.0 + QoD DL slice policy + E2 slice glue + qosflow-release fix + dup-release guard |
| gNB (plain) | `lintas5g/oai-gnb:v3.0.0-qosrel3` + `SLICE=0` | OAI v3.0.0 + qosflow-release fix + dup-release guard |
| UE | `oaisoftwarealliance/oai-nr-ue:v3.0.0` (`n5-ue1..N`) | confs from `../secrets/ue*.conf` (dir 700), keepalive ping 1 s on every UE after attach |
| Shared | `/workspace/oai-multiue/conf/gnb-c-n78-106-2x2.conf`, `/workspace/oai-multiue/shim/libsctp2tcp2.so` | read-only mounts (box kernel has no SCTP) |

```
./lab.sh start          # default: slice-qosrel2 gNB, SLICE=1, N_UE=2, RAN on CPUs 4-7, core on 0-3
GNB_IMG=lintas5g/oai-gnb:v3.0.0-qosrel3 SLICE=0 ./lab.sh start
./lab.sh status         # containers, NF state, UE + keepalive, foreign RAN (oai-*/mq-*/qa-*) left untouched
./lab.sh reset-pcc      # remove all PCC rules from the lab DB
./lab.sh stop           # reset PCC + remove n5-* containers (volume kept)
```

Tests (from `..`): `./accept.sh <tag> [cycles] [profile]` (env DLR/ULR load, PAR=1 two parallel sessions),
`./ut-upf.sh <tag> <n3.pcap>` (deterministic stale-QFI UPF check). Rebuild core image: `docker build -t lintas5g/open5gs:2.8.0-qosrel img-open5gs`
(needs the base `lintas5g/n5-core-base:tmp` = `docker commit srs-lab`, or adapt FROM). Images are local only, never push
(the base snapshot carries the lab's demo SUCI home-network keys under /etc/open5gs/hnet).
