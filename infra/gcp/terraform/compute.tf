locals {
  core_internal_dns = "vm-core-ran.${var.zone}.c.${var.project_id}.internal"
  mpls_internal_dns = "vm-mpls.${var.zone}.c.${var.project_id}.internal"
  startup_core      = file("${path.module}/../startup/core-ran.sh")
  startup_obs       = file("${path.module}/../startup/obs.sh")
  startup_mpls      = file("${path.module}/../startup/mpls.sh")
  startup_emu = templatefile("${path.module}/../startup/emu.sh", {
    core_proxy_host = "vm-core-ran.${var.zone}.c.${var.project_id}.internal"
    core_proxy_port = 18080
  })
}

resource "google_compute_instance" "core" {
  depends_on   = [google_storage_bucket_object.gui_files]
  name         = "vm-core-ran"
  machine_type = var.core_machine_type
  zone         = var.zone
  tags         = ["lab5g", "lab5g-core"]
  labels       = merge(var.labels, { role = "core-ran" })

  allow_stopping_for_update = true
  can_ip_forward            = true
  deletion_protection       = false

  boot_disk {
    source      = google_compute_disk.core.id
    auto_delete = false
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
    # Tanpa access_config: tidak ada IP publik.
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "TRUE"
    lab-role               = "core-ran"
    startup-script         = local.startup_core
    gui-session            = var.gui_session ? "true" : "false"
    lab5g-bucket           = google_storage_bucket.runs.name
    mpls-enabled           = var.enable_mpls ? "true" : "false"
    mpls-peer-host         = var.enable_mpls ? local.mpls_internal_dns : ""
    mpls-tunnel-mode       = var.mpls_tunnel_mode
    mpls-ce-script         = file("${path.module}/../startup/mpls-ce-tunnels.sh")
  }

  service_account {
    email  = google_service_account.core.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }
}

locals {
  emu_gpu          = var.gui_emu_gpu == "t4"
  emu_machine_type = local.emu_gpu ? var.gui_emu_gpu_machine_type : var.emu_machine_type
  # N1 in asia-southeast2 tops out at Skylake (nested virt needs Haswell+); N2 keeps Cascade Lake
  emu_cpu_platform = local.emu_gpu ? "Intel Skylake" : "Intel Cascade Lake"
  emu_cost         = local.emu_gpu ? var.gui_cost_per_hour_gpu : var.gui_cost_per_hour
  t4_zones         = ["asia-southeast2-a", "asia-southeast2-b"] # gcloud compute accelerator-types list, 18 Nov 2026
}

resource "google_compute_instance" "emu" {
  depends_on   = [google_storage_bucket_object.gui_files]
  name         = "vm-emu"
  machine_type = local.emu_machine_type
  zone         = var.zone

  lifecycle {
    precondition {
      condition     = !local.emu_gpu || contains(local.t4_zones, var.zone)
      error_message = "gui_emu_gpu=t4 butuh zona dengan T4: asia-southeast2-a atau asia-southeast2-b."
    }
    precondition {
      condition     = !(local.emu_gpu && var.emu_spot)
      error_message = "gui_emu_gpu=t4 tidak dikombinasikan dengan emu_spot di IaC ini (kuota PREEMPTIBLE_NVIDIA_T4_GPUS = 0)."
    }
  }
  tags   = ["lab5g", "lab5g-emu"]
  labels = merge(var.labels, { role = "emu" })

  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = false
  min_cpu_platform          = local.emu_cpu_platform

  advanced_machine_features {
    enable_nested_virtualization = true
  }

  dynamic "guest_accelerator" {
    for_each = local.emu_gpu ? [1] : []
    content {
      type  = "nvidia-tesla-t4"
      count = 1
    }
  }

  boot_disk {
    source      = google_compute_disk.emu.id
    auto_delete = false
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "TRUE"
    lab-role               = "emu"
    core-proxy             = "http://vm-core-ran.${var.zone}.c.${var.project_id}.internal:18080"
    startup-script         = local.startup_emu
    gui-session            = var.gui_session ? "true" : "false"
    gui-public-tunnel      = var.gui_public_tunnel ? "true" : "false"
    gui-emu-egress         = var.gui_emu_egress
    gui-emu-api            = var.gui_emu_api
    gui-emu-img-type       = var.gui_emu_img_type
    gui-emu-device         = var.gui_emu_device
    gui-emu-screen         = var.gui_emu_screen
    gui-emu-gpu            = var.gui_emu_gpu
    gui-emu-userdata-uri   = var.gui_emu_userdata_uri
    gui-cost-per-hour      = local.emu_cost
    lab5g-bucket           = google_storage_bucket.runs.name
  }

  service_account {
    email  = google_service_account.emu.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart           = var.emu_spot ? false : true
    on_host_maintenance         = (var.emu_spot || local.emu_gpu) ? "TERMINATE" : "MIGRATE" # GPU VMs cannot live-migrate
    preemptible                 = var.emu_spot
    provisioning_model          = var.emu_spot ? "SPOT" : "STANDARD"
    instance_termination_action = var.emu_spot ? "STOP" : null
  }
}

resource "google_compute_instance" "obs" {
  count        = var.enable_obs ? 1 : 0
  name         = "vm-obs"
  machine_type = var.obs_machine_type
  zone         = var.zone
  tags         = ["lab5g", "lab5g-obs"]
  labels       = merge(var.labels, { role = "obs" })

  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = false

  boot_disk {
    source      = google_compute_disk.obs[0].id
    auto_delete = false
  }

  network_interface {
    subnetwork = google_compute_subnetwork.obs.id
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "TRUE"
    lab-role               = "obs"
    startup-script         = local.startup_obs
  }

  service_account {
    email  = google_service_account.obs.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }
}

resource "google_compute_instance" "mpls" {
  count        = var.enable_mpls ? 1 : 0
  name         = "vm-mpls"
  machine_type = var.mpls_machine_type
  zone         = var.zone
  tags         = ["lab5g", "lab5g-mpls"]
  labels       = merge(var.labels, { role = "mpls" })

  allow_stopping_for_update = true
  can_ip_forward            = true
  deletion_protection       = false

  boot_disk {
    source      = google_compute_disk.mpls[0].id
    auto_delete = false
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab.id
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "TRUE"
    lab-role               = "mpls"
    startup-script         = local.startup_mpls
    core-peer-host         = local.core_internal_dns
    mpls-tunnel-mode       = var.mpls_tunnel_mode
    mpls-backhaul-script   = file("${path.module}/../startup/mpls-backhaul.sh")
  }

  service_account {
    email  = google_service_account.mpls[0].email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }
}

# Sesi user emulator (opsional): bucket privat di luar terraform lab; hanya grant baca untuk SA vm-emu (dicabut saat destroy).
# Simpan ulang (emu-session-save.sh) butuh objectAdmin -> diberikan manual di bucket, bukan oleh IaC ini.
resource "google_storage_bucket_iam_member" "emu_userdata_reader" {
  count  = var.gui_emu_userdata_uri == "" ? 0 : 1
  bucket = split("/", trimprefix(var.gui_emu_userdata_uri, "gs://"))[0]
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.emu.email}"
}
