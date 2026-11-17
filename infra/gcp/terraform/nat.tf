resource "google_compute_address" "nat" {
  name         = "lab5g-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  description  = "IP statis Cloud NAT untuk egress SGi/UE. Bukan IP publik VM."
}

resource "google_compute_router" "lab" {
  name    = "lab5g-router"
  region  = var.region
  network = google_compute_network.lab5g.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "lab" {
  name                               = "lab5g-nat"
  router                             = google_compute_router.lab.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.lab.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.obs.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  min_ports_per_vm                    = var.nat_min_ports_per_vm
  enable_dynamic_port_allocation      = true
  max_ports_per_vm                    = 2048
  tcp_established_idle_timeout_sec    = 1200
  tcp_transitory_idle_timeout_sec     = 30
  udp_idle_timeout_sec                = 30
  icmp_idle_timeout_sec               = 30
  enable_endpoint_independent_mapping = false

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
