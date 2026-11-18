output "region" {
  value = var.region
}

output "zone" {
  value = var.zone
}

output "network" {
  value = google_compute_network.lab5g.name
}

output "vm_internal_ips" {
  description = "IP internal VM. Tidak ada IP publik."
  value = merge(
    {
      vm-core-ran = google_compute_instance.core.network_interface[0].network_ip
      vm-emu      = google_compute_instance.emu.network_interface[0].network_ip
    },
    var.enable_obs ? {
      vm-obs = google_compute_instance.obs[0].network_interface[0].network_ip
    } : {},
    var.enable_mpls ? {
      vm-mpls = google_compute_instance.mpls[0].network_interface[0].network_ip
    } : {}
  )
}

output "nat_ip" {
  description = "IP eksternal Cloud NAT (egress saja, bukan SSH)."
  value       = google_compute_address.nat.address
}

output "runs_bucket" {
  value = google_storage_bucket.runs.name
}

output "emu_spot" {
  value = var.emu_spot
}

output "iap_tunnel_commands" {
  description = "Perintah IAP dari laptop. Ganti PROJECT jika perlu."
  value       = <<-EOT
    gcloud compute ssh vm-core-ran --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap
    gcloud compute ssh vm-emu --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap
    gcloud compute ssh vm-obs --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap
    # vm-mpls hanya ada jika enable_mpls = true
    gcloud compute ssh vm-mpls --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap

    # VNC/noVNC emulator: port 5900/6080 hanya bind 127.0.0.1 di vm-emu, jadi start-iap-tunnel langsung
    # ke 5900/6080 GAGAL (4003). Pakai SSH tunnel via IAP, lalu buka http://localhost:6080/vnc.html
    # atau klien VNC ke localhost:5900. Password: sudo cat /opt/lab5g/vnc-password.txt (lihat infra/gcp/vnc/README.md)
    gcloud compute ssh vm-emu --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap -- -N -L 6080:localhost:6080 -L 5900:localhost:5900

    # Grafana (lalu buka http://127.0.0.1:3000)
    gcloud compute start-iap-tunnel vm-obs 3000 --local-host-port=localhost:3000 --project=${var.project_id} --zone=${var.zone}
  EOT
}

output "next_steps" {
  value = "Lanjut ke ../scripts/test-run-day1.sh setelah terraform apply selesai. Jangan simpan kredensial di repo ini."
}

output "enable_mpls" {
  value = var.enable_mpls
}

output "mpls_backhaul" {
  description = "USULAN: backhaul MPLS di vm-mpls (tidak di-setup otomatis)."
  value = var.enable_mpls ? join("\n", [
    "1) Di vm-mpls:      sudo /opt/lab5g/scripts/mpls-backhaul.sh setup",
    "2) Di vm-core-ran:  sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh setup",
    "3) Verifikasi PE:   sudo /opt/lab5g/scripts/mpls-backhaul.sh verify",
    "4) Verifikasi CE:   sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh verify",
    "   (ping/traceroute ce-enb 10.255.10.2 -> ce-sgw 10.255.20.2 lewat VRF S1)",
    "Salinan GCS: gs://${google_storage_bucket.runs.name}/scripts/mpls-backhaul.sh",
    "             gs://${google_storage_bucket.runs.name}/scripts/mpls-ce-tunnels.sh",
    "MTU: VPC 1460, gretap+key ~28 B + Ethernet 14 B -> MTU terowongan 1400;",
    "     GTP-U (~36 B) + inner IP -> tun aplikasi 1360-1400.",
  ]) : "enable_mpls=false; vm-mpls tidak dibuat."
}
