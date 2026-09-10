resource "proxmox_virtual_environment_file" "lightwhale_iso" {
  node_name    = var.proxmox_nodes[0]
  content_type = "iso"
  datastore_id = "cephfs"

  source_file {
    path = "https://lightwhale.asklandd.dk/download/lightwhale-3.0.5-x86.iso"
  }
}

resource "proxmox_virtual_environment_file" "lightwhale_magic" {
  node_name    = var.proxmox_nodes[0]
  content_type = "iso"
  datastore_id = "cephfs"

  source_raw {
    # Lightwhale formats any disk carrying this byte sequence at offset 0 on the
    # next boot, so shipping it as the VM disk means persistency is already active
    # on the first boot - no provisioning reboot needed. Lightwhale's partition
    # table then overwrites it, so this only ever triggers on a fresh disk.
    data      = "lightwhale-please-format-me"
    file_name = "lightwhale-magic.img"
    resize    = 1048576
  }
}

# Prepare CephFS for this swarm on a Proxmox host, where CephFS is already
# mounted. Creates the swarm's own subdirectory and a CephFS client restricted
# to it, then returns that client's key - which is the mount secret, so it never
# has to be passed in. `ceph fs authorize` returns the existing key unchanged if
# the client already exists.
resource "ssh_sensitive_resource" "cephfs_client" {
  host  = local.cephfs_first_host
  user  = var.proxmox_ssh_user
  agent = true

  triggers = {
    path = "${var.cephfs_root_dir}/${var.swarm_name}"
  }

  commands = [
    "mkdir -p ${local.cephfs_pve_path} && chmod 777 ${local.cephfs_pve_path} && ceph fs authorize cephfs client.${var.swarm_name} ${var.cephfs_root_dir}/${var.swarm_name} rw > /dev/null 2>&1 && ceph auth get-key client.${var.swarm_name}",
  ]
}

#################################################################################################################################################################

resource "proxmox_virtual_environment_vm" "swarm" {
  count = 3

  node_name = var.proxmox_nodes[count.index]
  name      = format("%s-%03d", var.swarm_name, count.index + 1)
  started   = true

  machine = "q35"
  bios    = "seabios"

  lifecycle {
    ignore_changes = [node_name]
  }

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

  network_device {
    bridge = "vmbr1"
  }

  agent {
    enabled = true
  }

  cdrom {
    file_id   = proxmox_virtual_environment_file.lightwhale_iso.id
    interface = "ide2"
  }

  disk {
    datastore_id = "ceph-vm"
    interface    = "scsi0"
    file_id      = proxmox_virtual_environment_file.lightwhale_magic.id
    size         = 20
    file_format  = "raw"
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["ide2"]
}

locals {
  swarm_ips = [
    for vm in proxmox_virtual_environment_vm.swarm :
    flatten(vm.ipv4_addresses)[index(vm.network_interface_names, "eth0")]
  ]

  # The swarm gets its own CephFS subdirectory, and authenticates as a client
  # named after the swarm, so several swarms can share one CephFS.
  cephfs_source = "${var.cephfs_hosts}:${var.cephfs_root_dir}/${var.swarm_name}"

  # _netdev is what makes lightwhale's S41mount wait for the network and run
  # before S60dockerd, so the mount is back on its own after a reboot.
  cephfs_fstab_entry = "${local.cephfs_source} ${var.cephfs_target} ceph name=${var.swarm_name},secret=${local.cephfs_secret},_netdev,noatime 0 0"

  # Only the first monitor is used to prepare CephFS, without its port. It is a
  # Proxmox host, which mounts CephFS under /mnt/pve/<datastore>.
  cephfs_first_host = split(":", split(",", var.cephfs_hosts)[0])[0]
  cephfs_pve_path   = "/mnt/pve/cephfs${var.cephfs_root_dir}/${var.swarm_name}"

  cephfs_secret = trimspace(ssh_sensitive_resource.cephfs_client.result)
}

resource "proxmox_haresource" "swarm" {
  count = 3

  resource_id = "vm:${proxmox_virtual_environment_vm.swarm[count.index].vm_id}"
  state       = "started"
  failback    = true

  depends_on = [
    proxmox_virtual_environment_vm.swarm,
  ]
}

resource "proxmox_harule" "swarm" {
  for_each = { for idx, node in var.proxmox_nodes : idx => node }

  rule   = format("%s-%03d-home", var.swarm_name, tonumber(each.key) + 1)
  type   = "node-affinity"
  strict = true

  nodes = { for node in var.proxmox_nodes : node => (node == each.value ? 1 : null) }

  resources = [proxmox_haresource.swarm[each.key].resource_id]

  depends_on = [
    proxmox_haresource.swarm,
  ]
}

resource "ssh_resource" "swarm_config" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.swarm[count.index].id
  }

  host     = local.swarm_ips[count.index]
  user     = "op"
  password = "opsecret"

  commands = [
    # The docker data root is a tmpfs at half the VM memory unless lightwhale
    # claimed the disk - too small for the images, so fail loudly instead.
    "findmnt -n -o SOURCE /mnt/lightwhale-data | grep -q '^/dev/' || { echo 'persistency not active'; exit 1; }",
    "rm -f /home/op/.telemetry-nudge",
    "echo '${var.ssh_public_key}' > /home/op/.ssh/authorized_keys",
    "echo 'opsecret' | sudo -S bash -c 'setup-hostname ${proxmox_virtual_environment_vm.swarm[count.index].name}'",
    "echo 'opsecret' | sudo -S bash -c 'echo \"op ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/op_nopasswd'",
    # eth1 is the ceph network. Configure it in /etc/network/interfaces (now on the
    # data disk) instead of calling udhcpc by hand, so it also comes back after a
    # reboot. Its DHCP lease installs a default route that beats eth0's and kills
    # registry access, hence the up hook.
    "echo 'opsecret' | sudo -S sh -c \"grep -q '^auto eth1' /etc/network/interfaces || printf 'auto eth1\\niface eth1 inet dhcp\\n\\thostname ${proxmox_virtual_environment_vm.swarm[count.index].name}\\n\\tudhcpc_opts -t1 -A3 -O search -O staticroutes\\n\\tup ip route del default dev eth1 || true\\n' >> /etc/network/interfaces\"",
    "echo 'opsecret' | sudo -S bash -c 'ifup eth1 || true'",
    # CephFS goes into /etc/fstab: lightwhale's S41mount creates the mountpoint,
    # waits for the network because of _netdev and runs before S60dockerd, so the
    # mount is back on its own after a reboot.
    "echo 'opsecret' | sudo -S sh -c \"grep -q ' ${var.cephfs_target} ' /etc/fstab || printf '%s\\n' '${local.cephfs_fstab_entry}' >> /etc/fstab\"",
    "echo 'opsecret' | sudo -S bash -c 'mkdir -p ${var.cephfs_target} && mount ${var.cephfs_target}'",
  ]

  depends_on = [
    proxmox_virtual_environment_vm.swarm,
    ssh_sensitive_resource.cephfs_client,
  ]
}

resource "ssh_resource" "swarm_init" {
  host  = local.swarm_ips[0]
  user  = "op"
  agent = true

  commands = [
    "docker swarm init --advertise-addr ${local.swarm_ips[0]} > /dev/null 2>&1 && docker swarm join-token manager -q",
  ]

  depends_on = [
    ssh_resource.swarm_config,
  ]
}

resource "ssh_resource" "swarm_join" {
  count = 2

  host  = local.swarm_ips[count.index + 1]
  user  = "op"
  agent = true

  commands = [
    "docker swarm join --token ${trimspace(ssh_resource.swarm_init.result)} ${local.swarm_ips[0]}:2377",
  ]

  depends_on = [
    ssh_resource.swarm_init,
  ]
}

#################################################################################################################################################################

resource "ssh_resource" "komodo_deploy" {
  host  = local.swarm_ips[0]
  user  = "op"
  agent = true

  triggers = {
    compose = filesha256("${path.module}/docker-compose/komodo/komodo.compose.yaml")
    env     = filesha256("${path.module}/docker-compose/komodo/compose.env")
  }

  # Runs before the file uploads, so the target directory exists and is writable.
  # All komodo state lives on CephFS, the lightwhale nodes stay stateless.
  pre_commands = [
    "sudo mkdir -p ${var.cephfs_target}/komodo/mongo/data ${var.cephfs_target}/komodo/mongo/config ${var.cephfs_target}/komodo/keys ${var.cephfs_target}/komodo/backups",
    # Swarm never creates bind mount sources, so the per-node periphery roots
    # have to exist before the tasks are scheduled.
    "sudo mkdir -p ${join(" ", [for vm in proxmox_virtual_environment_vm.swarm : "${var.cephfs_target}/komodo/periphery/${vm.name}"])}",
    "sudo chown -R op:op ${var.cephfs_target}/komodo",
    "sudo chown -R 999:999 ${var.cephfs_target}/komodo/mongo",
  ]

  file {
    content     = file("${path.module}/docker-compose/komodo/komodo.compose.yaml")
    destination = "${var.cephfs_target}/komodo/komodo.compose.yaml"
    permissions = "0644"
  }

  file {
    content     = file("${path.module}/docker-compose/komodo/compose.env")
    destination = "${var.cephfs_target}/komodo/compose.env"
    permissions = "0600"
  }

  # docker stack deploy only substitutes ${...} from the shell environment,
  # env_file is resolved separately and does not feed the interpolation.
  commands = [
    "set -a && . ${var.cephfs_target}/komodo/compose.env && set +a && docker stack deploy -d -c ${var.cephfs_target}/komodo/komodo.compose.yaml komodo",
  ]

  depends_on = [
    ssh_resource.swarm_join,
  ]
}

#################################################################################################################################################################

# Runs last and over the key that swarm_config installed, because it takes away
# the password login that swarm_config itself needs.
resource "ssh_resource" "swarm_lock_password" {
  count = 3

  triggers = {
    vm_id = proxmox_virtual_environment_vm.swarm[count.index].id
  }

  host  = local.swarm_ips[count.index]
  user  = "op"
  agent = true

  commands = [
    "sudo sh -c \"sed -i 's/^\\(op:\\)[^:]*:/\\1*:/g' /etc/shadow\"",
  ]

  depends_on = [
    ssh_resource.komodo_deploy,
  ]
}
