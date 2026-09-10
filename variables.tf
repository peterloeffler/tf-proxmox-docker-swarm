variable "proxmox_nodes" {
  type        = list(string)
  description = "The names of the Proxmox cluster nodes, used for even swarm VM placement"
  default     = ["pve01-001", "pve01-002", "pve01-003"]
}

variable "swarm_name" {
  type        = string
  description = "Name of the docker swarm"
  default     = "swarm01"
}

variable "ssh_public_key" {
  type        = string
  description = "Your SSH public key"
  default     = "ssh-rsa AAAAB3Nzaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx== me"
}

variable "proxmox_ssh_user" {
  type        = string
  description = "SSH user on the Proxmox hosts, used to prepare the swarm's CephFS directory"
  default     = "root"
}

variable "cephfs_hosts" {
  type        = string
  description = "Comma separated CephFS monitors with port, e.g. 192.168.1.11:6789,192.168.1.12:6789"
  default     = ""

  validation {
    condition     = can(regex("^[^,:]+:[0-9]+(,[^,:]+:[0-9]+)*$", var.cephfs_hosts))
    error_message = "cephfs_hosts must be a comma separated list of host:port, e.g. 192.168.1.11:6789,192.168.1.12:6789."
  }
}

variable "cephfs_root_dir" {
  type        = string
  description = "Directory inside CephFS holding the per swarm subdirectories. The swarm mounts <cephfs_root_dir>/<swarm_name>"
  default     = "/docker"

  validation {
    condition     = startswith(var.cephfs_root_dir, "/") && !endswith(var.cephfs_root_dir, "/")
    error_message = "cephfs_root_dir must start with a slash and must not end with one, e.g. /docker."
  }
}

variable "cephfs_target" {
  type        = string
  description = "Mountpoint for CephFS on the swarm nodes. The komodo compose file hardcodes /mnt/cephfs, so change it there too"
  default     = "/mnt/cephfs"

  validation {
    condition     = startswith(var.cephfs_target, "/") && !endswith(var.cephfs_target, "/")
    error_message = "cephfs_target must start with a slash and must not end with one, e.g. /mnt/cephfs."
  }
}
