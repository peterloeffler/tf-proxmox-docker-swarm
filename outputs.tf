output "core_ip" {
  description = "Core VM IP"
  value       = local.core_ip
}

output "swarm_ips" {
  description = "Swarm VM IPs"

  value = {
    for idx, vm in proxmox_virtual_environment_vm.swarm : 
    vm.name => flatten(vm.ipv4_addresses)[index(vm.network_interface_names, "eth0")]
  }
} 
