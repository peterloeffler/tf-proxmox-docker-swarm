resource "proxmox_virtual_environment_file" "lightwhale_iso" {
  node_name    = var.proxmox_node
  content_type = "iso"
  datastore_id = "local"

  source_file {
    path      = "https://lightwhale.asklandd.dk/download/lightwhale-3.0.4-x86.iso"
  }
}

#################################################################################################################################################################

resource "proxmox_virtual_environment_vm" "core" {
  node_name = var.proxmox_node
  name      = "core"
  started   = true

  machine = "q35"
  bios    = "seabios"

  cpu {
    type  = "host"
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  agent {
    enabled = true
  }

  cdrom {
    file_id      = proxmox_virtual_environment_file.lightwhale_iso.id
    interface    = "ide2"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["ide2"]
}

locals {
  core_ip = flatten(proxmox_virtual_environment_vm.core.ipv4_addresses)[index(proxmox_virtual_environment_vm.core.network_interface_names, "eth0")]
}

resource "ssh_resource" "core_persistency" {
  triggers = {
    vm_id = proxmox_virtual_environment_vm.core.id
  }

  host     = local.core_ip
  user     = "op"
  password = "opsecret"

  commands = [
    "echo 'opsecret' | sudo -S bash -c 'echo lightwhale-please-format-me > /dev/sda'",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    proxmox_virtual_environment_vm.core,
  ]
}

resource "time_sleep" "core_persistency_wait" {
  create_duration = "5s"

  depends_on = [
    ssh_resource.core_persistency,
  ]
}

resource "ssh_resource" "core_config" {
  triggers = {
    vm_id = proxmox_virtual_environment_vm.core.id
  }

  host        = local.core_ip
  user        = "op"
  password    = "opsecret"

  commands = [
    "rm -f /home/op/.telemetry-nudge",
    "echo '${var.ssh_public_key}' > /home/op/.ssh/authorized_keys",
    "echo 'opsecret' | sudo -S bash -c 'setup-hostname ${proxmox_virtual_environment_vm.core.name}'",
    "echo 'opsecret' | sudo -S bash -c 'echo \"op ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/op_nopasswd'",
    "echo 'opsecret' | sudo -S bash -c \"sed -i 's/^\\(op:\\)[^:]*:/\\1*:/g' /etc/shadow\"",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    time_sleep.core_persistency_wait,
  ]
}

resource "time_sleep" "core_config_wait" {
  create_duration = "5s"

  depends_on = [
    ssh_resource.core_config,
  ]
}

#################################################################################################################################################################

resource "proxmox_virtual_environment_vm" "swarm" {
  count = 3

  node_name = var.proxmox_node
  name      = "swarm${count.index + 1}"
  started   = true

  machine = "q35"
  bios    = "seabios"

  cpu {
    type  = "host"
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  agent {
    enabled = true
  }

  cdrom {
    file_id      = proxmox_virtual_environment_file.lightwhale_iso.id
    interface    = "ide2"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["ide2"]
}

##### LOCALS for IPs!!!!!!

resource "ssh_resource" "swarm_persistency" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.swarm[count.index].id
  }

  host     = flatten(proxmox_virtual_environment_vm.swarm[count.index].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[count.index].network_interface_names, "eth0")]
  user     = "op"
  password = "opsecret"

  commands = [
    "echo 'opsecret' | sudo -S bash -c 'echo lightwhale-please-format-me > /dev/sda'",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    proxmox_virtual_environment_vm.swarm,
  ]
}

resource "time_sleep" "swarm_persistency_wait" {
  create_duration = "5s"

  depends_on = [
    ssh_resource.swarm_persistency,
  ]
}

resource "ssh_resource" "swarm_config" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.swarm[count.index].id
  }

  host     = flatten(proxmox_virtual_environment_vm.swarm[count.index].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[count.index].network_interface_names, "eth0")]
  user     = "op"
  password = "opsecret"

  commands = [
    "rm -f /home/op/.telemetry-nudge",
    "echo '${var.ssh_public_key}' > /home/op/.ssh/authorized_keys",
    "echo 'opsecret' | sudo -S bash -c 'setup-hostname ${proxmox_virtual_environment_vm.swarm[count.index].name}'",
    "echo 'opsecret' | sudo -S bash -c 'echo \"op ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/op_nopasswd'",
    "echo 'opsecret' | sudo -S bash -c \"sed -i 's/^\\(op:\\)[^:]*:/\\1*:/g' /etc/shadow\"",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    time_sleep.swarm_persistency_wait,
  ]
}

resource "time_sleep" "swarm_config_wait" {
  create_duration = "5s"

  depends_on = [
    ssh_resource.swarm_config,
  ]
}

resource "ssh_resource" "swarm_init" {
  host  = flatten(proxmox_virtual_environment_vm.swarm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[0].network_interface_names, "eth0")]
  user  = "op"
  agent = true

  commands = [
    "docker swarm init --advertise-addr ${flatten(proxmox_virtual_environment_vm.swarm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[0].network_interface_names, "eth0")]} > /dev/null 2>&1 && docker swarm join-token manager -q",
  ]

  depends_on = [
    time_sleep.swarm_config_wait,
  ]
}

resource "ssh_resource" "swarm_join" {
  count = 2

  host  = flatten(proxmox_virtual_environment_vm.swarm[count.index + 1].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[count.index + 1].network_interface_names, "eth0")]
  user  = "op"
  agent = true

  commands = [
    "docker swarm join --token ${trimspace(ssh_resource.swarm_init.result)} ${flatten(proxmox_virtual_environment_vm.swarm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.swarm[0].network_interface_names, "eth0")]}:2377",
  ]

  depends_on = [
    ssh_resource.swarm_init,
  ]
}

#################################################################################################################################################################

provider "docker" {
  host     = "ssh://op@${local.core_ip}:22"
}

resource "docker_compose" "komodo" {
  project_name   = "komodo"
  remove_orphans = true
  wait           = true
  wait_timeout   = "30s"

  env_files = [
    "${path.module}/docker-compose/komodo/compose.env",
  ]

  config_paths = [
    "${path.module}/docker-compose/komodo/mongo.compose.yaml",
  ]

  depends_on = [
    time_sleep.core_config_wait,
  ]
}
