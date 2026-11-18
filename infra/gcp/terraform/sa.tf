resource "google_service_account" "core" {
  account_id   = "lab5g-core-ran"
  display_name = "lab5g vm-core-ran"
  description  = "SA minimal untuk core/RAN, Zeek, dan unggah hasil run ke GCS."
}

resource "google_service_account" "emu" {
  account_id   = "lab5g-emu"
  display_name = "lab5g vm-emu"
  description  = "SA minimal untuk emulator dan unggah artefak run ke GCS."
}

resource "google_service_account" "obs" {
  account_id   = "lab5g-obs"
  display_name = "lab5g vm-obs"
  description  = "SA minimal untuk ClickHouse/Grafana dan baca objek hasil run."
}

resource "google_service_account" "mpls" {
  count        = var.enable_mpls ? 1 : 0
  account_id   = "lab5g-mpls"
  display_name = "lab5g vm-mpls"
  description  = "SA minimal untuk backhaul MPLS (FRR di netns) dan unggah log run."
}

resource "google_project_iam_member" "log_writer" {
  for_each = merge(
    {
      core = google_service_account.core.email
      emu  = google_service_account.emu.email
      obs  = google_service_account.obs.email
    },
    var.enable_mpls ? { mpls = google_service_account.mpls[0].email } : {}
  )

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${each.value}"
}

resource "google_project_iam_member" "metric_writer" {
  for_each = merge(
    {
      core = google_service_account.core.email
      emu  = google_service_account.emu.email
      obs  = google_service_account.obs.email
    },
    var.enable_mpls ? { mpls = google_service_account.mpls[0].email } : {}
  )

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${each.value}"
}

resource "google_project_iam_member" "iap_tunnel" {
  for_each = toset(var.my_iap_users)

  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

resource "google_project_iam_member" "os_login" {
  for_each = toset(var.my_iap_users)

  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = each.value
}

resource "google_project_iam_member" "os_admin_login" {
  for_each = var.grant_os_admin_login ? toset(var.my_iap_users) : toset([])

  project = var.project_id
  role    = "roles/compute.osAdminLogin"
  member  = each.value
}

# Dibutuhkan agar gcloud compute start-iap-tunnel / ssh bisa menemukan instans.
resource "google_project_iam_member" "compute_viewer" {
  for_each = toset(var.my_iap_users)

  project = var.project_id
  role    = "roles/compute.viewer"
  member  = each.value
}

