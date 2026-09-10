#output "core_ip" {
#  description = "Core VM IP"
#  value       = local.core_ip
#}

output "swarm_ips" {
  description = "Swarm VM IPs"

  value = {
    for idx, vm in proxmox_virtual_environment_vm.swarm :
    vm.name => local.swarm_ips[idx]
  }
}
