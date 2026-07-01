variable "proxmox_node" {
  type        = string
  description = "The name of the Proxmox node where resources will be created"
  default     = "px1"
}

variable "ssh_public_key" {
  type        = string
  description = "Your SSH public key"
  default     = "ssh-rsa AAAAB3Nzaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx== me"
}
