terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
    }
    ssh = {
      source = "loafoe/ssh"
    }
    docker = {
      source  = "kreuzwerker/docker"
    }
  } 
}
