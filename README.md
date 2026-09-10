# tf-proxmox-docker-swarm
This is just a terraform/tofu POC to initiate a very basic 3 node docker swarm on a 3 node proxmox cluster using the lightwhale iso image.
The VMs are HA managed. Application data lives on CephFS, mounted at `/mnt/cephfs` on every node.
Lightwhale itself claims the 20 GB VM disk for its own state, because the docker image store would otherwise sit in a
tmpfs sized at half the VM memory - too small for the images. That disk is on the ceph-vm RBD pool, so it is shared storage too.

Set proxmox environment variables as you need. Examples:
```
PROXMOX_VE_USERNAME=root@pam
PROXMOX_VE_PASSWORD=changeme
PROXMOX_VE_INSECURE=true
PROXMOX_VE_ENDPOINT=https://px1:8006/
```

Set the CephFS mount as an `/etc/fstab` line. It is appended to `/etc/fstab` on every swarm node, so keep `_netdev` -
lightwhale's `S41mount` creates the mountpoint, waits for the network and runs before dockerd, which is what makes the
mount come back on its own after a reboot:
```
export TF_VAR_cephfs_fstab_entry='192.168.1.11:6789,192.168.1.12:6789,192.168.1.13:6789:/docker/swarm01 /mnt/cephfs ceph name=swarm01,secret=xxxxxxxxxx,_netdev,noatime 0 0'
```

Also set the variables in variables.tf

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

Note that `docker-compose/komodo/compose.env` still ships the upstream placeholder secrets
(`KOMODO_JWT_SECRET`, `KOMODO_WEBHOOK_SECRET`, `KOMODO_INIT_ADMIN_PASSWORD`, mongo `admin`/`admin`) - change them before this is anything but a POC.
