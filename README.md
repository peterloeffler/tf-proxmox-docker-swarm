# tf-proxmox-docker-swarm
This is just a terraform/tofu POC to initiate a very basic 3 node docker swarm on a singel proxmox server using the lightwhale iso image

Set proxmox environment variables as you need. Examples:
```
PROXMOX_VE_USERNAME=root@pam
PROXMOX_VE_PASSWORD=changeme
PROXMOX_VE_INSECURE=true
PROXMOX_VE_ENDPOINT=https://px1:8006/
```

Also set the variables in variables.tf
