locals {
  startup_core = file("${path.module}/../startup/core-ran.sh")
  startup_obs  = file("${path.module}/../startup/obs.sh")
  startup_emu = templatefile("${path.module}/../startup/emu.sh", {
    core_proxy_host = "vm-core-ran.${var.zone}.c.${var.project_id}.internal"
    core_proxy_port = 18080
  })
}

resource "google_compute_instance" "core" {
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
    mpls-backhaul-script   = file("${path.module}/../../mpls/mpls-backhaul.sh")
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

resource "google_compute_instance" "emu" {
  name         = "vm-emu"
  machine_type = var.emu_machine_type
  zone         = var.zone
  tags         = ["lab5g", "lab5g-emu"]
  labels       = merge(var.labels, { role = "emu" })

  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = false
  min_cpu_platform          = "Intel Cascade Lake"

  advanced_machine_features {
    enable_nested_virtualization = true
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
    on_host_maintenance         = var.emu_spot ? "TERMINATE" : "MIGRATE"
    preemptible                 = var.emu_spot
    provisioning_model          = var.emu_spot ? "SPOT" : "STANDARD"
    instance_termination_action = var.emu_spot ? "STOP" : null
  }
}

resource "google_compute_instance" "obs" {
  name         = "vm-obs"
  machine_type = var.obs_machine_type
  zone         = var.zone
  tags         = ["lab5g", "lab5g-obs"]
  labels       = merge(var.labels, { role = "obs" })

  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = false

  boot_disk {
    source      = google_compute_disk.obs.id
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
