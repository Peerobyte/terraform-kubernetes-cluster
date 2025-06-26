output "master_ips" {
  value = [for m in openstack_compute_instance_v2.masters : m.access_ip_v4]
}

output "worker_ips" {
  value = [for w in openstack_compute_instance_v2.workers : w.access_ip_v4]
}
