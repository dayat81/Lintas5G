# infra/mpls — backhaul MPLS S1 (USULAN)

`mpls-backhaul.sh setup|status|verify|netem|rollback|hint` membangun eNB — PE1 — (P1 | P2) — PE2 — SGW-U/MME di dalam satu VM (netns + veth), FRR OSPF + LDP, BGP VPNv4, VRF `S1`. Alamat hanya internal host (`10.255.0.0/16`).

Terraform memuat skrip ini ke metadata `vm-core-ran` dan ke bucket GCS; startup **tidak** menjalankannya.

```bash
sudo /opt/lab5g/scripts/mpls-backhaul.sh setup
sudo /opt/lab5g/scripts/mpls-backhaul.sh verify
sudo /opt/lab5g/scripts/mpls-backhaul.sh netem set p1 delay 20ms jitter 5ms loss 0.1%
sudo /opt/lab5g/scripts/mpls-backhaul.sh rollback
```

Catatan: kernel GCP Ubuntu default mungkin tidak memuat `mpls_router`; skrip mencoba `linux-modules-extra-$(uname -r)`. VM `vm-mpls` opsional menyusul di commit berikutnya.
