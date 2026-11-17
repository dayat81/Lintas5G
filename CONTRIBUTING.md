# Kontribusi

1. Buat branch dari `main`, buka pull request. Jangan push langsung ke `main`.
2. Repo ini **publik**: jangan commit kredensial, state Terraform, `.env`, project ID, IMSI/MSISDN/KEY/OPc nyata, IP/hostname node live, pcap/trace UE. Pakai placeholder dan `*.example`.
3. Sebelum PR jalankan:
   ```bash
   gitleaks dir . --redact
   (cd infra/gcp/terraform && terraform fmt -check && terraform init -backend=false && terraform validate)
   (cd adapters/qod-af && pytest -q)
   ```
4. Tandai di dokumen mana **FAKTA** (teruji) dan mana **USULAN**.
5. Kode repo berlisensi Apache-2.0. Patch ke Open5GS/srsRAN (AGPL-3.0) hanya di `upstream-patches/`.
