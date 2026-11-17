resource "google_project_service" "required" {
  for_each = var.enable_apis ? toset([
    "compute.googleapis.com",
    "iap.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "oslogin.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "lab5g" {
  name                    = "lab5g"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC custom-mode lab 5G latency PoC. Tanpa IP publik pada VM."

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "lab" {
  name                     = "lab"
  ip_cidr_range            = "10.10.0.0/24"
  region                   = var.region
  network                  = google_compute_network.lab5g.id
  private_ip_google_access = true
  description              = "Core/RAN + emulator"
}

resource "google_compute_subnetwork" "obs" {
  name                     = "obs"
  ip_cidr_range            = "10.10.1.0/24"
  region                   = var.region
  network                  = google_compute_network.lab5g.id
  private_ip_google_access = true
  description              = "ClickHouse + Grafana + sink Vector"
}
