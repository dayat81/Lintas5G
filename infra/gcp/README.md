# Lab 5G Latency PoC di GCP

Paket Terraform untuk test run lab latency di `asia-southeast2` (Jakarta).
Ini **usulan infrastruktur**; paket ini **tidak mendeploy apa pun** sampai
Anda menjalankan `terraform apply` sendiri.

Stack aplikasi (Open5GS, srsRAN, Zeek, emulator, ClickHouse, Grafana)
**tidak** diinstal oleh startup script. Startup hanya memasang Docker,
chrony ke `metadata.google.internal`, dan direktori kerja.

## Isi paket

```
infra/gcp/terraform/           # modul Terraform (google provider ~> 6)
  terraform.tfvars.example
infra/gcp/startup/             # bootstrap Docker + chrony per VM (core-ran, emu, obs)
infra/mpls/mpls-backhaul.sh    # USULAN backhaul MPLS S1 (OSPF+LDP+VPNv4), dimuat ke metadata VM core
infra/gcp/scripts/test-run-day1.sh   # checklist test run hari pertama
```

## Prasyarat

1. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6 dan
   [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`).
2. Proyek GCP dengan billing aktif. Cek **CPUS_ALL_REGIONS** (bisa lebih ketat
   daripada kuota regional). Default optimal memakai 16 vCPU N2 + 4 vCPU E2.
   Minimal 1 UE: 8 vCPU N2 + 2 vCPU E2. Nested virtualization hanya untuk
   seri Intel (N2 memakai `min_cpu_platform = "Intel Cascade Lake"`).
   `pd-balanced` memakai kuota `SSD_TOTAL_GB`; jika sisa tipis, set
   `disk_type = "pd-standard"`. Spot membutuhkan kuota `PREEMPTIBLE_CPUS`.
3. Autentikasi: `gcloud auth login` + ADC, atau
   `GOOGLE_APPLICATION_CREDENTIALS` untuk service account, atau
   `GOOGLE_OAUTH_ACCESS_TOKEN` dari `gcloud auth print-access-token`.
4. API berikut (diaktifkan otomatis jika `enable_apis = true`):
   `compute`, `iap`, `storage`, `iam`, `iamcredentials`, `oslogin`,
   `cloudresourcemanager`.
5. Identitas yang boleh akses IAP dimasukkan ke `my_iap_users`
   (contoh `user:anda@example.com`). Jangan menaruh kredensial, kunci, atau
   token di file Terraform.

## Langkah deploy

```bash
cd infra/gcp/terraform
cp terraform.tfvars.example terraform.tfvars
# edit project_id dan my_iap_users

terraform init
terraform plan
terraform apply
```

Tidak ada backend remote yang dikonfigurasi. State default-nya lokal.
Jika tim memakai bucket GCS untuk state, tambahkan blok `backend "gcs"`
sendiri; jangan commit `terraform.tfstate`.

## Akses lewat IAP (tanpa IP publik)

Perintah lengkap juga muncul di output `iap_tunnel_commands`.

```bash
# SSH
gcloud compute ssh vm-core-ran --zone=asia-southeast2-a --tunnel-through-iap
gcloud compute ssh vm-emu      --zone=asia-southeast2-a --tunnel-through-iap
gcloud compute ssh vm-obs      --zone=asia-southeast2-a --tunnel-through-iap

# VNC emulator → klien VNC ke localhost:5900
gcloud compute start-iap-tunnel vm-emu 5900 \
  --local-host-port=localhost:5900 --zone=asia-southeast2-a

# Grafana → http://127.0.0.1:3000
gcloud compute start-iap-tunnel vm-obs 3000 \
  --local-host-port=localhost:3000 --zone=asia-southeast2-a
```

OS Login aktif pada ketiga VM. Firewall ingress hanya menerima
`35.235.240.0/20` (rentang IAP) untuk port 22, 5900, dan 3000.

## Test run hari pertama

Setelah `apply` selesai dan startup script menuliskan
`/opt/lab5g/.bootstrap-complete`, jalankan checklist:

```bash
./infra/gcp/scripts/test-run-day1.sh
```

Kriteria sukses ringkas: UE attach, keepalive hidup, Zeek melihat flow,
latency p50 S1-U terukur, Grafana menampilkan dashboard.

## USULAN: backhaul MPLS S1

Default penempatan: **di dalam `vm-core-ran`** (netns + veth). VPC GCP tidak
meneruskan frame berlabel MPLS antar-VM, jadi ini jalur yang didukung skrip.

Topologi: eNB — PE1 — (P1 | P2) — PE2 — SGW-U/MME. IGP OSPF + LDP, L3VPN
VRF `S1` (BGP VPNv4 PE1–PE2). SR-MPLS tercatat sebagai opsi, belum
diaktifkan. VPLS/EVPN tidak didukung FRR secara penuh (risiko).

Startup **tidak** menjalankan topologi. Setelah bootstrap:

```bash
sudo /opt/lab5g/scripts/mpls-backhaul.sh setup
sudo /opt/lab5g/scripts/mpls-backhaul.sh verify
# show mpls ldp neighbor, show bgp ipv4 vpn, ip -f mpls route,
# traceroute/ping CE dummy, lalu pastikan UE attach tetap OK

sudo /opt/lab5g/scripts/mpls-backhaul.sh netem set p1 delay 20ms jitter 5ms loss 0.1%
sudo /opt/lab5g/scripts/mpls-backhaul.sh netem clear
sudo /opt/lab5g/scripts/mpls-backhaul.sh rollback
```

Kernel GCP Ubuntu 22.04 default sering tidak memuat `mpls_router`. Skrip
setup sekarang mencoba memasang `linux-modules-extra-$(uname -r)` bila
modul belum ada.

## Sizing minimal vs optimal

Diukur di lab on-prem saat ini (VM lab 5G + container emulator) pada 17 Nov 2026 dan idle footprint
VM GCP (tanpa stack 5G). Angka "optimal" adalah rekomendasi, bukan hasil
benchmark penuh emulator di GCP (emulator penuh tidak di-deploy pada uji IaC).

| Peran | Minimal | Optimal | Dasar |
| --- | --- | --- | --- |
| vm-core-ran | n2-standard-4 (4 vCPU, 16 GB), disk 80–100 GB | n2-standard-8 (8 vCPU, 32 GB), disk 100 GB | FAKTA VM lab 5G on-prem: 16 vCPU / 24 GB, memori tamu terpakai 5,9 GB, load ~1,7 (mpstat ~10% dari 16 CPU). srsenb+srsue ~70% CPU + ~900 MB. Open5GS kecil. ~10 kontainer FRR MPLS ~350 MB. Rata-rata historis qemu-kvm ~8,8 core (bukan snapshot). |
| vm-emu | n2-standard-4 (4 vCPU, 16 GB), disk 100 GB | n2-standard-8 (8 vCPU, 32 GB), disk 150 GB | FAKTA container emulator on-prem: qemu `-cores 4 -memory 8192`, RSS 7,3 GiB / limit 10 GiB, CPU ~15–58% (satu AVD, relatif idle). Overlay 75 GB terisi 94%. |
| vm-obs | e2-standard-2 (2 vCPU, 8 GB), disk 80 GB | e2-standard-4 (4 vCPU, 16 GB), disk 200 GB | ESTIMASI untuk Vector+ClickHouse+Grafana 1 UE. ClickHouse bersama di host lab on-prem (17 GB) tidak mewakili lab kecil. |
| 3-VM total | 10 vCPU / 40 GB | 20 vCPU / 80 GB | Minimal ~USD 0,61/jam; optimal ~USD 1,22/jam (estimasi on-demand Jakarta, agregator 17 Nov 2026). |
| 1-VM gabungan | n2-standard-8 (8/32), disk 200 GB, ~USD 0,52/jam | n2-standard-16 (16/64), disk 300 GB, ~USD 1,04/jam | ESTIMASI. Mengorbankan isolasi; nested virt + core + obs berhimpit. 3-VM lebih disarankan. |

Idle OS Ubuntu di GCP (FAKTA uji IaC, ~3 menit setelah boot): core ~290 MB, emu ~355 MB, obs ~324 MB, steal 0%.


Opsi multi-VM (MPLS-over-GRE/VXLAN di atas VPC) hanya dokumentasi: MTU VPC
~1460 dikurangi GTP-U, label, dan GRE; turunkan MTU tun aplikasi ke 1400
atau lebih kecil. Fragmentasi GTP-U sudah pernah terlihat di lab saat ini.

Titik ukur Zeek yang diusulkan: `pe1-ce` (PE1-ingress, sisi eNB, tanpa
label), `pe2-ce` (PE2-egress, sisi SGW, tanpa label), plus tap S1-U lama.

## Destroy

```bash
cd infra/gcp/terraform
terraform destroy
```

Disk boot `auto_delete = false`, tetapi resource disk dikelola Terraform
jadi `destroy` tetap menghapusnya. Set `bucket_force_destroy = true`
(disarankan) agar objek di bucket tidak menggagalkan destroy.

Jangan membuat secret placeholder di Terraform kecuali service account
operator punya izin Secret Manager; uji 17 Nov 2026 gagal refresh secret
dan harus `terraform state rm` lalu hapus secret secara terpisah.

## Rahasia

Tidak ada password, token, atau kunci di paket ini. Jika nanti dibutuhkan
(misalnya password Grafana), buat secret di Secret Manager di luar modul
ini, lalu berikan `roles/secretmanager.secretAccessor` ke service account
yang relevan. Jangan hard-code nilai rahasia di `terraform.tfvars` atau
startup script.
