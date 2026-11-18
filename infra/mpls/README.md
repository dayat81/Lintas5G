# infra/mpls — rujukan backhaul MPLS S1

Skrip kanonis ada di `infra/gcp/startup/`, bukan di folder ini:

- `infra/gcp/startup/mpls-backhaul.sh` — FRR PE1 / P1 / P2 / PE2 di netns pada `vm-mpls` (opsional, `enable_mpls`, default false)
- `infra/gcp/startup/mpls-ce-tunnels.sh` — sisi CE GRE atau VXLAN di `vm-core-ran`, tanpa label MPLS
- `infra/gcp/startup/mpls.sh` — bootstrap modul kernel di `vm-mpls`

`mpls-backhaul.sh` di folder ini hanya meneruskan ke salinan kanonis supaya tidak ada dua skrip yang berbeda.

Label MPLS hanya di dalam `vm-mpls` (`net.mpls.platform_labels` per netns). Antar-VM memakai GRE (protokol 47) atau VXLAN (UDP 4789) karena VPC tidak meneruskan frame berlabel. Startup tidak menjalankan topologi.

```bash
# di vm-mpls
sudo /opt/lab5g/scripts/mpls-backhaul.sh setup
# di vm-core-ran
sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh setup
sudo /opt/lab5g/scripts/mpls-backhaul.sh verify
```

Uji 17 Nov: modul dan GRE PASS. L3VPN end-to-end FAIL karena LDP neighbor tidak terbentuk (known issue). Detail ada di `infra/gcp/README.md`.
