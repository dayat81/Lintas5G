# IAP TCP forwarding merujuk rentang resmi 35.235.240.0/20.
# https://cloud.google.com/iap/docs/using-tcp-forwarding

resource "google_compute_firewall" "allow_iap" {
  name        = "lab5g-allow-iap"
  network     = google_compute_network.lab5g.id
  description = "SSH, VNC/noVNC, dan Grafana hanya dari rentang IAP."
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = concat(["22", "3000"], var.gui_vnc ? ["5900", "6080"] : []) # headless (gui_vnc=false): no VNC ports
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["lab5g"]
}

resource "google_compute_firewall" "allow_internal_lab" {
  name        = "lab5g-allow-internal"
  network     = google_compute_network.lab5g.id
  description = "Lalu lintas antar-VM: proxy CONNECT, collector dashboard 8099, ClickHouse, Vector, SSH internal, ICMP, GRE/VXLAN (CE-PE MPLS)."
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22", "18080", "8123", "9000", "6000", "8099"] # 8099: collector dashboard (vm-core-ran -> vm-emu)
  }

  allow {
    protocol = "udp"
    ports    = ["4789"] # VXLAN CE↔PE
  }

  allow {
    protocol = "47" # GRE (IANA) untuk gretap CE↔PE
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.10.0.0/16"]
  target_tags   = ["lab5g"]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name        = "lab5g-deny-other-ingress"
  network     = google_compute_network.lab5g.id
  description = "Tolak ingress lain. Aturan allow di atas (priority 1000) lebih dulu."
  direction   = "INGRESS"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
