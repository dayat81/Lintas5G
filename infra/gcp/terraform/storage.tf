resource "random_id" "bucket_suffix" {
  byte_length = 2
}

resource "google_storage_bucket" "runs" {
  name                        = "lab5g-runs-${var.project_id}-${random_id.bucket_suffix.hex}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.bucket_force_destroy

  labels = var.labels

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "core_writer" {
  bucket = google_storage_bucket.runs.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.core.email}"
}

resource "google_storage_bucket_iam_member" "emu_writer" {
  bucket = google_storage_bucket.runs.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.emu.email}"
}

resource "google_storage_bucket_iam_member" "obs_reader" {
  bucket = google_storage_bucket.runs.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.obs.email}"
}

# Snapshot harian pukul 17:00 UTC = 00:00 WIB. Retensi 7 hari.
resource "google_compute_resource_policy" "daily_snapshot" {
  name   = "lab5g-daily-snapshot"
  region = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = "17:00"
      }
    }

    retention_policy {
      max_retention_days    = 7
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      storage_locations = [var.region]
      labels            = var.labels
      guest_flush       = false
    }
  }
}

resource "google_compute_disk" "core" {
  name   = "vm-core-ran-boot"
  type   = var.disk_type
  zone   = var.zone
  size   = 100
  image  = "ubuntu-os-cloud/ubuntu-2204-lts"
  labels = merge(var.labels, { role = "core-ran" })
}

resource "google_compute_disk" "emu" {
  name   = "vm-emu-boot"
  type   = var.disk_type
  zone   = var.zone
  size   = 150
  image  = "ubuntu-os-cloud/ubuntu-2204-lts"
  labels = merge(var.labels, { role = "emu" })
}

resource "google_compute_disk" "obs" {
  name   = "vm-obs-boot"
  type   = var.disk_type
  zone   = var.zone
  size   = 200
  image  = "ubuntu-os-cloud/ubuntu-2204-lts"
  labels = merge(var.labels, { role = "obs" })
}

resource "google_compute_disk_resource_policy_attachment" "core" {
  name = google_compute_resource_policy.daily_snapshot.name
  disk = google_compute_disk.core.name
  zone = var.zone
}

resource "google_compute_disk_resource_policy_attachment" "emu" {
  name = google_compute_resource_policy.daily_snapshot.name
  disk = google_compute_disk.emu.name
  zone = var.zone
}

resource "google_compute_disk_resource_policy_attachment" "obs" {
  name = google_compute_resource_policy.daily_snapshot.name
  disk = google_compute_disk.obs.name
  zone = var.zone
}

resource "google_storage_bucket_object" "mpls_backhaul" {
  name   = "scripts/mpls-backhaul.sh"
  bucket = google_storage_bucket.runs.name
  source = "${path.module}/../../mpls/mpls-backhaul.sh"

  content_type = "text/x-shellscript"
}
