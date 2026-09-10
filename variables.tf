variable "proxmox_nodes" {
  type        = list(string)
  description = "The names of the Proxmox cluster nodes, used for even swarm VM placement"
  default     = ["pve01-001", "pve01-002", "pve01-003"]
}

variable "ssh_public_key" {
  type        = string
  description = "Your SSH public key"
  default     = "ssh-rsa AAAAB3Nzaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx== me"
}
