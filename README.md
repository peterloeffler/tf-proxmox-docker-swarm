# tf-proxmox-docker-swarm
This is just a terraform/tofu POC to initiate a very basic 3 node docker swarm on a 3 node proxmox cluster using the lightwhale iso image.
The VMs are HA managed and boot stateless from the ISO. Application data lives on CephFS, mounted at `/mnt/cephfs` on every node.

Lightwhale still claims the 20 GB VM disk for its own state, because the docker image store would otherwise sit in a
tmpfs sized at half the VM memory - too small for the images. That disk is on the ceph-vm RBD pool, so it is shared storage too.
Persistency is enabled without a provisioning reboot: `proxmox_virtual_environment_file.lightwhale_magic` uploads a 1 MiB image
whose first bytes are lightwhale's `lightwhale-please-format-me` magic header, and the VM disk is imported from it. Lightwhale
finds the header on the very first boot, formats the disk and overwrites the header with its own partition table, so this only
ever triggers on a fresh disk.

Because `/etc` is then persistent, the node config survives a reboot: the CephFS mount goes into `/etc/fstab` and eth1 into
`/etc/network/interfaces`. A rebooted node remounts CephFS and rejoins the swarm on its own, without running tofu.

`docs/architecture.excalidraw` shows how the pieces fit together - open it on excalidraw.com or with the VS Code
Excalidraw extension.

## Configuration

Set proxmox environment variables as you need. Examples:
```
PROXMOX_VE_USERNAME=root@pam
PROXMOX_VE_PASSWORD=changeme
PROXMOX_VE_INSECURE=true
PROXMOX_VE_ENDPOINT=https://px1:8006/
```

Set the CephFS connection. The swarm authenticates as a CephFS client named after `var.swarm_name` and mounts its own
subdirectory `<cephfs_root_dir>/<swarm_name>`, so several swarms can share one CephFS:
```
export TF_VAR_cephfs_hosts=192.168.1.11:6789,192.168.1.12:6789,192.168.1.13:6789
export TF_VAR_cephfs_root_dir=/docker
export TF_VAR_cephfs_target=/mnt/cephfs
```

There is no secret to set. `ssh_sensitive_resource.cephfs_client` connects to the first monitor from `cephfs_hosts` - a
Proxmox host, where CephFS is already mounted - over the SSH agent as `var.proxmox_ssh_user` (default `root`), and runs:

```
mkdir -p /mnt/pve/cephfs<cephfs_root_dir>/<swarm_name>
chmod 777 /mnt/pve/cephfs<cephfs_root_dir>/<swarm_name>
ceph fs authorize cephfs client.<swarm_name> <cephfs_root_dir>/<swarm_name> rw
ceph auth get-key client.<swarm_name>
```

So it creates the swarm's directory and a CephFS client restricted to it, and the key it returns is used as the mount
secret. `ceph fs authorize` returns the existing key unchanged when the client already exists, so this is repeatable.
The key lands in the terraform state, which is why the resource is the sensitive variant - it never shows up in plan output.

With the defaults and `swarm_name = "swarm01"` the resulting fstab line is
`192.168.1.11:6789,...:/docker/swarm01 /mnt/cephfs ceph name=swarm01,secret=<key>,_netdev,noatime 0 0`.

**Cleanup is manual.** The ssh resources have no destroy hook, so `tofu destroy` leaves both the CephFS client and the
swarm's data behind. Rebuilding the same `swarm_name` picks both up again, which is usually what you want. To retire a
swarm for good, remove them on a Proxmox host:
```
ceph auth del client.<swarm_name>
rm -rf /mnt/pve/cephfs<cephfs_root_dir>/<swarm_name>
```

Note that `var.cephfs_target` only reaches the terraform side. The komodo compose file hardcodes `/mnt/cephfs`, so a different
mountpoint has to be changed there as well.

Also set the variables in variables.tf - most importantly `swarm_name`, `proxmox_nodes` and `ssh_public_key`.
The node names are derived from `swarm_name`, zero padded to three digits: `swarm01-001`, `swarm01-002`, ...

## Komodo

`ssh_resource.komodo_deploy` uploads `docker-compose/komodo/` to the first swarm node and runs `docker stack deploy`.
The stack keeps everything under `/mnt/cephfs/komodo`, so every service can be rescheduled onto any node:

```
/mnt/cephfs/komodo/
  komodo.compose.yaml           uploaded by terraform
  compose.env                   uploaded by terraform
  mongo/data                    -> /data/db
  mongo/config                  -> /data/configdb
  keys/                         -> /config/keys (shared by core and all periphery tasks)
  backups/                      -> /backups
  periphery/<node-hostname>/    -> same path inside the container, one per node
```

Mongo and Komodo Core run with one replica each, Periphery runs as a global service so every swarm node is manageable.
The UI is published on port 9120 through the swarm ingress mesh, so it answers on any node IP.

Mongo is pinned to 7 because mongo 8+ refuses to start on lightwhale's kernel 6.19.

Note that `docker-compose/komodo/compose.env` still ships the upstream placeholder secrets
(`KOMODO_JWT_SECRET`, `KOMODO_WEBHOOK_SECRET`, `KOMODO_INIT_ADMIN_PASSWORD`, mongo `admin`/`admin`) - change them before this is anything but a POC.

## Password login

`ssh_resource.swarm_config` uses lightwhale's default password to bootstrap a node and installs `var.ssh_public_key`.
`ssh_resource.swarm_lock_password` runs last, over the SSH agent, and blanks the password hash of `op` so only key login remains.
A node that has to be reprovisioned therefore has to be recreated, not just reconfigured.
