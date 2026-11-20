# Desain: emulator -> UE lab 5G lewat routing TCP/IP langsung (tanpa SOCKS, tanpa Zeek)

> Update after the TAP baseline: use `-net-tap tap0` with the emulator's static 10.0.2.x addressing (no DHCP, no second NIC). See README-baseline.md and 01-host-tap.sh. The virtio-net second-NIC idea below does not work on the Play image.

Status: USULAN, offline. Belum ada apply atau perubahan konfigurasi lab.

## Masalah
- FAKTA: jalur SOCKS (gost di netns UE) membatasi unduhan Ookla ke sekitar 5 Mbps.
- FAKTA: di sesi Pixel ini, emulator memakai SLIRP (user-mode NAT). Thread `MainLoopThread` QEMU mentok 99,9% CPU.
  Unduhan di dalam guest dari server lokal di container (tanpa internet) hanya 80-86 Mbps.
  Jadi SLIRP sendiri sudah membatasi sekitar 80-86 Mbps, sebelum 5G ikut dihitung.
- FAKTA: VM emulator bisa unduh sekitar 370 Mbps dari dl.google.com dan sekitar 900 Mbps dari server Ookla Jakarta, jadi NAT GCP bukan batasnya.

## Target
Semua trafik guest Android masuk ke UE lewat routing L3 biasa. Jalurnya: TAP emulator -> bridge/route di host -> policy routing -> netns UE (tun) -> gNB -> UPF.
Tanpa proxy aplikasi, tanpa SLIRP, tanpa Zeek.

## Arsitektur
```
guest Android (eth0 10.0.2.15/24 static, gw 10.0.2.2, dns 10.0.2.3)
  -- virtio-net --> tap0 (host 10.0.2.2/24 + 10.0.2.3/24), via -net-tap
vm-emu: ip rule iif tap0 -> table 201 -> gre-core 10.201.0.2 (SNAT)   [mekanisme ue-l3 yang sudah ada]
  == GRE (proto 47, firewall lab5g-allow-internal sudah ada) ==> vm-core-ran gre-emu 10.201.0.1
vm-core-ran: ip rule iif gre-emu -> table 201 -> veth ke netns ue1 -> MASQUERADE ke IP UE -> tun UE -> gNB -> UPF -> N6 -> Cloud NAT
```
Mekanisme GRE + policy routing dan fail-closed (`emu-egress-policy.sh`, `core-gre-emu.sh`) sudah ada dan teruji di mode `ue-l3`.
Yang baru hanya sisi emulator: TAP menggantikan SLIRP. Emulator Android tidak mengirim trafik ke docker0.

## Perubahan yang dibutuhkan
Terraform:
1. `gui_session=true`, `gui_emu_egress="ue-l3"`, `gui_vnc=true`, `gui_public_tunnel=false`.
   Mode `ue-l3` sudah ada di variables.tf, jadi tidak perlu resource GCP baru.
2. Firewall dan IAM tidak perlu diubah. GRE sudah diizinkan oleh `lab5g-allow-internal`.
3. Zeek: tidak dipasang. Di lab ini Zeek hanya jalan bila diaktifkan oleh skrip bring-up, jadi cukup tidak memanggilnya (flag `ZEEK=0`).
   Verifikasi dengan `pgrep zeek` kosong dan tidak ada mirror port.

Script (di `pkg-final/gcp-lab5g/vnc/`):
1. `emu-vnc-start.sh`: container dibuat dengan `--cap-add NET_ADMIN --device /dev/net/tun` (sudah `--privileged`).
   Tambahkan `EMULATOR_ADDITIONAL_ARGS="-netdev tap,id=t0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=t0 -feature -VirtioWifi"`
   supaya guest memakai NIC ethernet biasa, bukan virtio-wifi di atas SLIRP.
   Alternatif jika dua NIC bentrok: `-net-tap tap0 -net-tap-script-up /opt/lab5g/tap-up.sh`.
2. Skrip baru `tap-up.sh` di vm-emu:
   `ip tuntap add tap0 mode tap`, `ip addr add 10.0.2.2/24 dev tap0` (+ 10.0.2.3 for DNS), `ip link set tap0 up`, lalu jalankan dnsmasq (DHCP + DNS) di tap0.
   MTU 1400 dan MSS clamp ke 1360 di tap0 supaya cocok dengan GRE (lihat `gui-net-fix.sh`).
3. `emu-egress-policy.sh`: ganti `iif docker0` menjadi `iif tap0`. Filter fail-closed (REJECT) berlaku untuk `tap0`.
4. Untuk container emulator: pakai `--network host` atau pindahkan tap0 ke netns container (`ip link set tap0 netns <pid>`).
   Paling sederhana adalah host network, tapi port 5900/6080/5555 harus tetap bind ke 127.0.0.1.
5. Konfigurasi guest: Android harus mengonfigurasi eth0 lewat DHCP. Kalau tidak, set manual lewat `adb shell` (`ip addr`, `ip route`, `setprop net.dns1`) atau pasang script `init.d`.
   Ini langkah paling berisiko.

## Risiko
- **Android tidak mengonfigurasi eth0 otomatis.** Image emulator ini defaultnya Wi-Fi virtual. Perlu uji, dengan fallback konfigurasi manual.
- **Sesi Google login.** Mengganti argumen emulator butuh container baru atau restart. Data AVD ada di overlay container, jadi `docker commit` dulu sebagai cadangan sebelum recreate. Jangan wipe.
- **MTU/MSS.** Salah MTU lewat GRE menyebabkan stall pada TCP besar.
- **Fail-closed.** Kalau GRE atau UE mati, trafik di-REJECT dan emulator offline. Itu perilaku yang diinginkan. Watchdog UE harus aktif.
- **UE tidak boleh idle.** Keepalive ping dari netns UE harus jalan.
- **Beban CPU.** TAP/virtio-net bisa multi-queue, tapi GRE dan MASQUERADE di dua VM menambah CPU. Pantau softirq.
- **Pengukuran.** Pakai iperf3 dari UE ke server N6 dulu (tanpa emulator) sebagai plafon radio/UPF.

## Estimasi plafon throughput (USULAN, belum diukur)
- **Emulator TAP/virtio-net:** sekitar 1-3 Gbps (bukan SLIRP). Tidak jadi batas.
- **GRE antar VM:** sekitar 1+ Gbps pada n2-standard-4/8, dikurangi overhead enkapsulasi.
- **Radio ZMQ srsRAN 4G / OAI rfsim:** tergantung profil. Di lab ini plafon sebenarnya adalah gNB/UE software dan CPU core. Dugaan kasar: 100-300 Mbps untuk OAI 2x2 40 MHz di n2-standard-8, dan jauh lebih rendah untuk srsRAN 4G ZMQ (puluhan Mbps).
- **Kesimpulan:** target >100 Mbps di Ookla via 5G realistis hanya dengan OAI 2x2 40 MHz, tanpa proxy. Ukur dulu dengan iperf3 sebelum klaim.

## Urutan uji (setelah ada approval)
1. iperf3 UE ke N6 (plafon 5G tanpa emulator).
2. Emulator via TAP + GRE ke UE, uji `nc` atau iperf dari guest (bukan Ookla dulu).
3. Ookla 2 run dan cek QFI di N3.
