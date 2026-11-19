variable "project_id" {
  description = "GCP project ID yang akan menampung lab. Tidak ada nilai default."
  type        = string
}

variable "region" {
  description = "Region lab."
  type        = string
  default     = "asia-southeast2"
}

variable "zone" {
  description = "Zone lab. Nested virtualization N2 tersedia di a/b/c."
  type        = string
  default     = "asia-southeast2-a"
}

variable "emu_spot" {
  description = "Jika true, vm-emu memakai provisioning_model SPOT (bisa di-preempt)."
  type        = bool
  default     = false
}

variable "my_iap_users" {
  description = "Daftar anggota IAM yang boleh IAP tunnel + OS Login, misalnya [\"user:anda@example.com\"]."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.my_iap_users : can(regex("^(user|group|serviceAccount|domain):", m))
    ])
    error_message = "Setiap entri my_iap_users harus memakai prefix IAM (user:, group:, serviceAccount:, atau domain:)."
  }
}

variable "grant_os_admin_login" {
  description = "Jika true, pengguna IAP juga mendapat roles/compute.osAdminLogin (sudo). Lab butuh ini untuk Docker."
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Jika true, Terraform mengaktifkan API yang dibutuhkan. Set false jika API sudah diaktifkan di luar modul ini."
  type        = bool
  default     = true
}

variable "nat_min_ports_per_vm" {
  description = "Minimum port Cloud NAT per VM. Emulator + banyak koneksi UE membutuhkan headroom."
  type        = number
  default     = 256
}

variable "labels" {
  description = "Label bersama untuk resource lab."
  type        = map(string)
  default = {
    project    = "lab5g"
    component  = "latency-poc"
    managed-by = "terraform"
  }
}

variable "core_machine_type" {
  description = "Tipe mesin vm-core-ran. Default (optimal) n2-standard-8. Minimal untuk 1 UE: n2-standard-4. n2-standard-2 hanya untuk smoke test IaC."
  type        = string
  default     = "n2-standard-8"

  validation {
    condition     = can(regex("^n2-(standard-(2|4|8|16)|custom-(2|4|6|8|10|12)-[0-9]+)$", var.core_machine_type))
    error_message = "core_machine_type harus n2-standard-2, 4, 8, 16 atau n2-custom-<2|4|6|8|10|12>-<MB> (Intel N2). Budget 12 vCPU: lihat vcpu_budget."
  }
}

variable "emu_machine_type" {
  description = "Tipe mesin vm-emu. Default n2-standard-8. Boleh dikecilkan ke n2-standard-4 atau n2-standard-2 untuk smoke test kuota. Nested virtualization tetap membutuhkan keluarga N2."
  type        = string
  default     = "n2-standard-8"

  validation {
    condition     = can(regex("^n2-standard-(2|4|8|16)$", var.emu_machine_type))
    error_message = "emu_machine_type harus n2-standard-2, 4, 8, atau 16 (nested virt / Intel N2)."
  }
}

variable "obs_machine_type" {
  description = "Tipe mesin vm-obs. Default e2-standard-4. Boleh dikecilkan untuk smoke test kuota."
  type        = string
  default     = "e2-standard-4"

  validation {
    condition     = can(regex("^e2-(standard|medium|highmem|highcpu)-[0-9]+$", var.obs_machine_type))
    error_message = "obs_machine_type harus tipe e2 yang valid, misalnya e2-standard-2 atau e2-standard-4."
  }
}

variable "bucket_force_destroy" {
  description = "Jika true, terraform destroy menghapus bucket beserta objek di dalamnya (termasuk skrip yang diunggah Terraform)."
  type        = bool
  default     = false
}

variable "disk_type" {
  description = "Tipe boot disk. Default pd-balanced. Gunakan pd-standard jika kuota SSD_TOTAL_GB (termasuk pd-balanced) tidak cukup untuk smoke test."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-balanced", "pd-standard", "pd-ssd"], var.disk_type)
    error_message = "disk_type harus pd-balanced, pd-standard, atau pd-ssd."
  }
}

variable "core_disk_gb" {
  description = "Ukuran boot disk vm-core-ran (GB). Minimal 80."
  type        = number
  default     = 100
}

variable "emu_disk_gb" {
  description = "Ukuran boot disk vm-emu (GB). Minimal 100."
  type        = number
  default     = 150
}

variable "obs_disk_gb" {
  description = "Ukuran boot disk vm-obs (GB). Minimal 80."
  type        = number
  default     = 200
}

variable "mpls_disk_gb" {
  description = "Ukuran boot disk vm-mpls (GB). Default 20."
  type        = number
  default     = 20
}

variable "enable_mpls" {
  description = "Jika true, buat vm-mpls (FRR PE/P di netns) dan skrip terowongan GRE/VXLAN ke vm-core-ran. Default false."
  type        = bool
  default     = false
}

variable "mpls_machine_type" {
  description = "Tipe mesin vm-mpls. Default e2-medium (4 GB) agar 4 instansi FRR longgar. e2-small (2 GB) juga muat kuota 2 vCPU."
  type        = string
  default     = "e2-medium"

  validation {
    condition     = can(regex("^e2-(small|medium|standard-[0-9]+)$", var.mpls_machine_type))
    error_message = "mpls_machine_type harus e2-small, e2-medium, atau e2-standard-N."
  }
}

variable "mpls_tunnel_mode" {
  description = "Jenis terowongan CE (vm-core-ran) ke PE (vm-mpls): gre (gretap) atau vxlan. Label MPLS hanya di dalam vm-mpls."
  type        = string
  default     = "gre"

  validation {
    condition     = contains(["gre", "vxlan"], var.mpls_tunnel_mode)
    error_message = "mpls_tunnel_mode harus gre atau vxlan."
  }
}

variable "enable_obs" {
  description = "Buat vm-obs (ClickHouse/Grafana). false = hemat kuota vCPU (mis. core n2-4 + emu n2-8 = 12)."
  type        = bool
  default     = true
}

# --- Sesi GUI (remote emulator via VNC/noVNC + dashboard lab) ---
variable "gui_session" {
  description = "Jika true, VM menjalankan bring-up sesi GUI otomatis saat boot: EPC + srsRAN ZMQ + gost (emulator via UE), tanpa shaping QoD, MTU/MSS fix, watchdog, dashboard (caddy 127.0.0.1:6081). Skrip diunggah ke bucket runs."
  type        = bool
  default     = false
}

variable "ran_mode" {
  description = "RAN/core profile of vm-core-ran (gui_session=true). epc-srsran4g (default): Open5GS EPC + srsRAN_4G eNB/UE ZMQ. sa-srsran: Open5GS 5GC SA + srsRAN Project gNB + srsUE (5G SA, ZMQ) with a static PCC rule -> second QoS flow (QFI 2). sa-ueransim: Open5GS 5GC SA + UERANSIM (control-plane/N3 only). sa-oai: Open5GS 5GC SA + OAI v3.0.0 gNB + nrUE (docker images by digest, rfsim/vrtsim, n78 TDD 40 MHz, 2x2 + 256QAM, nr_pairs = number of UEs 1..3, native SCTP)."
  type        = string
  default     = "epc-srsran4g"
  validation {
    condition     = contains(["epc-srsran4g", "sa-srsran", "sa-ueransim", "sa-oai"], var.ran_mode)
    error_message = "ran_mode harus epc-srsran4g, sa-srsran, sa-ueransim, atau sa-oai."
  }
}

variable "ran_prebuild_object" {
  description = "Opsional: objek GCS (di bucket runs) berisi tarball prebuild srsRAN (gnb+srsue, /opt/srsran) + .sha256, mis. prebuild/srsran-release_24_10_1-release_23_11-x86-64-v3-jammy-x86_64.tar.zst (portabel, jalan di Cascade Lake; tarball v1 tanpa -x86-64-v3 butuh Ice Lake). Kosong = build dari source di VM (~30-40 menit)."
  type        = string
  default     = ""
}

variable "gui_vnc" {
  description = "true (default): emulator publishes VNC/noVNC on 127.0.0.1 + caddy dashboard (IAP SSH tunnel). false = HEADLESS (Fase 0 closeout): no VNC/noVNC ports, no caddy, no public tunnel; only adb 127.0.0.1:5555 + collectors. gui_public_tunnel must be false."
  type        = bool
  default     = true
}

variable "gui_public_tunnel" {
  description = "OPT-IN: Cloudflare Quick Tunnel publik ke halaman dashboard+noVNC (basic auth + password VNC). Tanpa SLA, TLS diputus di Cloudflare."
  type        = bool
  default     = false
}

variable "gui_emu_egress" {
  description = "Kebijakan egress emulator: ue-l3 (default: SEMUA trafik TCP/UDP/QUIC/ICMP lewat GRE -> netns UE, fail-closed), ue-proxy (hanya proxy HTTP Android; app yang mengabaikan proxy seperti YouTube GAGAL), quic-block, atau off (langsung Cloud NAT, tidak lewat UE)."
  type        = string
  default     = "ue-l3"
  validation {
    condition     = contains(["ue-l3", "ue-proxy", "quic-block", "off"], var.gui_emu_egress)
    error_message = "gui_emu_egress harus ue-l3, ue-proxy, quic-block, atau off."
  }
}

variable "gui_emu_api" {
  description = "API level image emulator: 36 (Android 16, default), 35 (Android 15), atau budtmo (image asli emulator_14.0, tanpa Play Store/ARM translation). API 35+ google_apis_playstore x86_64 punya translasi ARM64 untuk game/app ARM-only."
  type        = string
  default     = "36"
  validation {
    condition     = contains(["35", "36", "budtmo"], var.gui_emu_api)
    error_message = "gui_emu_api harus 35, 36, atau budtmo."
  }
}

variable "gui_emu_img_type" {
  description = "Tipe system image: google_apis_playstore (default, Play Store) atau google_apis (bisa root)."
  type        = string
  default     = "google_apis_playstore"
  validation {
    condition     = contains(["google_apis_playstore", "google_apis"], var.gui_emu_img_type)
    error_message = "gui_emu_img_type harus google_apis_playstore atau google_apis."
  }
}

variable "gui_emu_device" {
  description = "Profil AVD (nama device budtmo). Default Pixel C (tablet layar besar)."
  type        = string
  default     = "Pixel C"
}

variable "gui_emu_screen" {
  description = "Resolusi framebuffer X/VNC WxH."
  type        = string
  default     = "1920x1080"
  validation {
    condition     = can(regex("^[0-9]{3,4}x[0-9]{3,4}$", var.gui_emu_screen))
    error_message = "gui_emu_screen format WxH, mis. 1920x1080."
  }
}

variable "gui_cost_per_hour" {
  description = "Estimasi biaya USD/jam untuk tampilan dashboard (bukan tagihan)."
  type        = string
  default     = "0.80"
}

variable "gui_emu_gpu" {
  description = "GPU untuk vm-emu: none (default, n2 + swiftshader CPU) atau t4 (n1-standard-8 + 1x nvidia-tesla-t4, on_host_maintenance=TERMINATE, zona asia-southeast2-a/b; butuh kuota NVIDIA_T4_GPUS dan GPUS_ALL_REGIONS >= 1). Emulator render lewat VirtualGL EGL ke GPU; fallback swiftshader bila GPU tidak terdeteksi."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "t4"], var.gui_emu_gpu)
    error_message = "gui_emu_gpu harus none atau t4."
  }
}

variable "gui_emu_gpu_machine_type" {
  description = "Tipe mesin vm-emu saat gui_emu_gpu=t4 (T4 hanya bisa di-attach ke N1)."
  type        = string
  default     = "n1-standard-8"
  validation {
    condition     = can(regex("^n1-(standard|highmem)-(4|8|16)$", var.gui_emu_gpu_machine_type))
    error_message = "gui_emu_gpu_machine_type harus N1 (mis. n1-standard-8)."
  }
}

variable "gui_cost_per_hour_gpu" {
  description = "Estimasi USD/jam lab saat gui_emu_gpu=t4 (n1-standard-8 0.511 + T4 ~0.35-0.40 + n2-standard-4 0.261 + disk + NAT). Estimasi, bukan tagihan."
  type        = string
  default     = "1.19"
}

variable "gui_emu_userdata_uri" {
  description = "OPSIONAL: gs://<bucket-privat>/<path>/session.tar.zst berisi sesi user emulator (akun Google yang sudah login). SENSITIF. Bucket TIDAK dikelola terraform lab (tidak ikut destroy); terraform hanya memberi lab5g-emu roles/storage.objectViewer di bucket itu. Kosong = boot fresh."
  type        = string
  default     = ""
  validation {
    condition     = var.gui_emu_userdata_uri == "" || can(regex("^gs://[a-z0-9._-]+/.+\\.tar\\.zst$", var.gui_emu_userdata_uri))
    error_message = "gui_emu_userdata_uri harus kosong atau gs://<bucket>/<path>.tar.zst."
  }
}

# ---- Radio capacity uplift (Fase 0 offline, 19 Nov 2026). Semua default = perilaku lama (tidak ada diff). ----
variable "emu_enabled" {
  description = "false = profil radio-only: vm-emu tidak dibuat (count 0), vCPU emulator dipakai core/RAN. Disk emu tetap ada (state sesi)."
  type        = bool
  default     = true
}

variable "nr_pairs" {
  description = "Jumlah pasangan srsRAN Project gNB + srsUE NR 20 MHz ZMQ pada ran_mode=sa-srsran (1..4; 4 = 1 vCPU gNB + 1 vCPU UE per pasangan di 12 vCPU, NR_PIN=0 berbagi CPU). 1 = perilaku lama. Dikirim ke core via metadata nr-pairs hanya bila > 1."
  type        = number
  default     = 1

  validation {
    condition     = var.nr_pairs >= 1 && var.nr_pairs <= 4 && floor(var.nr_pairs) == var.nr_pairs
    error_message = "nr_pairs harus bilangan bulat 1..4 (batas 12 vCPU)."
  }
}

variable "nr_exclude_zmq_from_n3_tap" {
  description = "true = tap N3 hanya menangkap GTP-U (BPF udp port 2152) dan menolak I/Q ZMQ (tcp 2000-2299) pada lo."
  type        = bool
  default     = true
}

variable "vcpu_budget" {
  description = "Batas vCPU total lab (CPUS_ALL_REGIONS). check{} memberi peringatan bila total VM melebihi ini. Tidak menaikkan kuota."
  type        = number
  default     = 12
}

variable "core_min_cpu_platform" {
  description = "min_cpu_platform vm-core-ran. null (default) = otomatis: \"Intel Ice Lake\" bila ran_mode=sa-srsran atau sa-oai (sesi radio; FAKTA GCP 19 Nov 2026, n2-custom-12: Ice Lake +44-48% DL vs Cascade Lake pada vCPU sama, kernel AVX512 srsRAN aktif via runtime dispatch, tarif n2 sama), selain itu default GCP. \"\" = paksa default GCP (prebuild x86-64-v3 juga jalan di Cascade Lake). Nilai lain (mis. \"Intel Cascade Lake\") dipakai apa adanya."
  type        = string
  default     = null
  nullable    = true
}

# ---- ran_mode = sa-oai (OAI gNB + nrUE, user approval 19 Nov 2026 13:43 WIB). Hanya dipakai bila ran_mode = sa-oai. ----
variable "oai_gnb_image" {
  description = "Image OAI gNB, wajib dipin dengan digest (FAKTA offline 19 Nov 2026: v3.0.0, banner commit 6f89078)."
  type        = string
  default     = "oaisoftwarealliance/oai-gnb:v3.0.0@sha256:170b4878a79086bd343d0abef8e327e7c6179cd5995618217db4417395665cbd"
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.oai_gnb_image))
    error_message = "oai_gnb_image harus dipin dengan @sha256:<digest>."
  }
}

variable "oai_ue_image" {
  description = "Image OAI nrUE, wajib dipin dengan digest."
  type        = string
  default     = "oaisoftwarealliance/oai-nr-ue:v3.0.0@sha256:b482191d636dc8f743923cdc8ef5cbf35722ad0f8def21598fbdc364ffd7910f"
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.oai_ue_image))
    error_message = "oai_ue_image harus dipin dengan @sha256:<digest>."
  }
}

variable "oai_rf" {
  description = "RF OAI: rfsim (default, multi-UE, tidak di-pacing: laporkan sim/real ratio) atau vrtsim (shared memory, di-pacing real-time, 1..3 UE via num_ues/ue_id; FAKTA GCP 19 Nov 2026 n2-custom-12 Ice Lake: timescale 1.0 stabil untuk 1 dan 3 UE 2x2)."
  type        = string
  default     = "rfsim"
  validation {
    condition     = contains(["rfsim", "vrtsim"], var.oai_rf)
    error_message = "oai_rf harus rfsim atau vrtsim."
  }
}

variable "oai_mimo" {
  description = "Jumlah antena/layer OAI: 2 (default, 2x2 + 256QAM via uecap_ports2) atau 1 (1x1 + 256QAM via uecap_ports1)."
  type        = number
  default     = 2
  validation {
    condition     = contains([1, 2], var.oai_mimo)
    error_message = "oai_mimo harus 1 atau 2."
  }
}
