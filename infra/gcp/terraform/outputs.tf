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
  value = {
    vm-core-ran = google_compute_instance.core.network_interface[0].network_ip
    vm-emu      = google_compute_instance.emu.network_interface[0].network_ip
    vm-obs      = google_compute_instance.obs.network_interface[0].network_ip
  }
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

    # VNC emulator (lalu buka klien VNC ke localhost:5900)
    gcloud compute start-iap-tunnel vm-emu 5900 --local-host-port=localhost:5900 --project=${var.project_id} --zone=${var.zone}

    # Grafana (lalu buka http://127.0.0.1:3000)
    gcloud compute start-iap-tunnel vm-obs 3000 --local-host-port=localhost:3000 --project=${var.project_id} --zone=${var.zone}
  EOT
}

output "next_steps" {
  value = "Lanjut ke ../scripts/test-run-day1.sh setelah terraform apply selesai. Jangan simpan kredensial di repo ini."
}

output "mpls_backhaul" {
  description = "USULAN: skrip backhaul MPLS S1 (tidak di-setup otomatis)."
  value       = <<-EOT
    Di vm-core-ran: sudo /opt/lab5g/scripts/mpls-backhaul.sh setup
    Verifikasi:     sudo /opt/lab5g/scripts/mpls-backhaul.sh verify
    Salinan GCS:    gs://${google_storage_bucket.runs.name}/scripts/mpls-backhaul.sh
    Naikkan mesin:  core_machine_type = "n2-standard-8" jika CPU steal tinggi.
  EOT
}
