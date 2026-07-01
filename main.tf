resource "proxmox_virtual_environment_file" "lightwhale_iso" {
  node_name    = var.proxmox_node
  content_type = "iso"
  datastore_id = "local"

  source_file {
    path      = "https://lightwhale.asklandd.dk/download/lightwhale-3.0.4-x86.iso"
  }
}

resource "proxmox_virtual_environment_vm" "lightwhale_vm" {
  count = 3

  node_name = var.proxmox_node
  name      = "lw${count.index + 1}"
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

resource "ssh_resource" "guest_ssh_bootstrap" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.lightwhale_vm[count.index].id
  }

  host     = flatten(proxmox_virtual_environment_vm.lightwhale_vm[count.index].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[count.index].network_interface_names, "eth0")]
  user     = "op"
  password = "opsecret"

  commands = [
    "echo 'opsecret' | sudo -S bash -c 'echo lightwhale-please-format-me > /dev/sda'",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    proxmox_virtual_environment_vm.lightwhale_vm,
  ]
}


resource "time_sleep" "wait_for_disk" {
  count = 3

  create_duration = "30s"

  depends_on = [
    ssh_resource.guest_ssh_bootstrap,
  ]
}

resource "ssh_resource" "guest_setup_stuff" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.lightwhale_vm[count.index].id
  }

  host     = flatten(proxmox_virtual_environment_vm.lightwhale_vm[count.index].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[count.index].network_interface_names, "eth0")]
  user     = "op"
  password = "opsecret"

  commands = [
    "rm -f /home/op/.telemetry-nudge",
    "echo '${var.ssh_public_key}' > /home/op/.ssh/authorized_keys",
    "echo 'opsecret' | sudo -S bash -c 'setup-hostname ${proxmox_virtual_environment_vm.lightwhale_vm[count.index].name}'",
    "echo 'opsecret' | sudo -S bash -c 'echo \"op ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/op_nopasswd'",
    "echo 'opsecret' | sudo -S bash -c \"sed -i 's/^\\(op:\\)[^:]*:/\\1*:/g' /etc/shadow\"",
    "echo 'opsecret' | sudo -S bash -c 'reboot'",
  ]

  depends_on = [
    ssh_resource.guest_ssh_bootstrap,
    time_sleep.wait_for_disk,
  ]
}

resource "time_sleep" "wait_for_reboot" {
  create_duration = "30s"

  depends_on = [
    ssh_resource.guest_setup_stuff,
  ]
}

resource "ssh_resource" "swarm_init" {
  host  = flatten(proxmox_virtual_environment_vm.lightwhale_vm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[0].network_interface_names, "eth0")]
  user  = "op"
  agent = true

  commands = [
    "docker swarm init --advertise-addr ${flatten(proxmox_virtual_environment_vm.lightwhale_vm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[0].network_interface_names, "eth0")]} > /dev/null 2>&1 && docker swarm join-token manager -q",
  ]

  depends_on = [
    time_sleep.wait_for_reboot,
  ]
}

resource "ssh_resource" "swarm_join" {
  count = 2

  host  = flatten(proxmox_virtual_environment_vm.lightwhale_vm[count.index + 1].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[count.index + 1].network_interface_names, "eth0")]
  user  = "op"
  agent = true

  commands = [
    "docker swarm join --token ${trimspace(ssh_resource.swarm_init.result)} ${flatten(proxmox_virtual_environment_vm.lightwhale_vm[0].ipv4_addresses)[index(proxmox_virtual_environment_vm.lightwhale_vm[0].network_interface_names, "eth0")]}:2377",
  ]

  depends_on = [
    ssh_resource.swarm_init,
  ]
}
