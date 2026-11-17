# Lisensi

- **Kode dan dokumentasi di repo ini**: Apache License 2.0 ([LICENSE](../LICENSE)), copyright "Lintas5G contributors".
- **Open5GS** dan **srsRAN** berlisensi **AGPL-3.0**. Keduanya dipakai sebagai **komponen terpisah** (biner/container upstream yang dijalankan sendiri), tidak di-vendor dan tidak di-link ke kode repo ini. Skrip dan konfigurasi di sini hanya berinteraksi lewat antarmuka jaringan standar (SBI, PFCP, GTP-U, Diameter, ZMQ) dan berkas konfigurasi.
- **Patch ke Open5GS/srsRAN** (jika ada) ditempatkan terpisah di [`upstream-patches/`](../upstream-patches/) dengan lisensi **AGPL-3.0** sendiri (`upstream-patches/LICENSE`), atau di repo terpisah. Folder itu **tidak** tercakup Apache-2.0.
- Komponen pihak ketiga lain (Zeek BSD, Vector MPL-2.0, ClickHouse Apache-2.0, Grafana AGPL-3.0 sebagai layanan terpisah, FRR GPL-2.0) dijalankan sebagai image/paket upstream, tidak didistribusikan ulang dari repo ini.
- Jika ragu soal kewajiban AGPL saat lab dibuka ke partner (akses jaringan ke layanan AGPL yang dimodifikasi), konsultasikan ke penasihat hukum.
