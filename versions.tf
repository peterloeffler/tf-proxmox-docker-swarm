terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.112.0"
    }
    ssh = {
      source  = "loafoe/ssh"
      version = "~> 2.7.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14.1"
    }
  }
}
