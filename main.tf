terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.1.0"
    }
  }
}

provider "openstack" {
  auth_url            = var.auth_url
  user_name           = var.user
  password            = var.password
  tenant_name         = var.tenant_name
  region              = "RegionOne"
  user_domain_name    = var.domain
  project_domain_name = var.domain

  # Increase retry count for OpenStack API operations
  max_retries   = 10
  endpoint_type = "public"
}

# Get image information by name
data "openstack_images_image_v2" "image" {
  name = var.image_name
}

# Create internal network for Kubernetes
resource "openstack_networking_network_v2" "k8s_network" {
  name           = "k8s-net"
  admin_state_up = true
}

# Create subnet
resource "openstack_networking_subnet_v2" "k8s_subnet" {
  name            = "k8s-subnet"
  network_id      = openstack_networking_network_v2.k8s_network.id
  cidr            = "172.16.254.0/24"
  ip_version      = 4
  gateway_ip      = "172.16.254.1"
  enable_dhcp     = true
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# Create router for external access
resource "openstack_networking_router_v2" "k8s_router" {
  name                = "k8s-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
}

# Connect subnet to the router
resource "openstack_networking_router_interface_v2" "k8s_router_interface" {
  router_id = openstack_networking_router_v2.k8s_router.id
  subnet_id = openstack_networking_subnet_v2.k8s_subnet.id
}

# Security group for all Kubernetes nodes
resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "k8s-secgroup"
  description = "Security group for Kubernetes nodes"
}

# SSH access
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Kubernetes API server
resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# NodePort services
resource "openstack_networking_secgroup_rule_v2" "nodeports" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Internal cluster communication - TCP
resource "openstack_networking_secgroup_rule_v2" "internal_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Internal cluster communication - UDP
resource "openstack_networking_secgroup_rule_v2" "internal_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Flannel VXLAN (custom port 65414)
resource "openstack_networking_secgroup_rule_v2" "flannel_vxlan_custom" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 65414
  port_range_max    = 65414
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Kubelet API (used for logs, exec, metrics, etc.)
resource "openstack_networking_secgroup_rule_v2" "kubelet_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# etcd cluster (control-plane nodes)
resource "openstack_networking_secgroup_rule_v2" "etcd" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2380
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# DNS - UDP
resource "openstack_networking_secgroup_rule_v2" "dns_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# DNS - TCP
resource "openstack_networking_secgroup_rule_v2" "dns_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# kube-scheduler
resource "openstack_networking_secgroup_rule_v2" "kube_scheduler" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10259
  port_range_max    = 10259
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# kube-controller-manager
resource "openstack_networking_secgroup_rule_v2" "controller_manager" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10257
  port_range_max    = 10257
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# kube-proxy health and metrics
resource "openstack_networking_secgroup_rule_v2" "kube_proxy" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10256
  port_range_max    = 10256
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# metrics-server
resource "openstack_networking_secgroup_rule_v2" "metrics_server" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 4443
  port_range_max    = 4443
  remote_ip_prefix  = openstack_networking_subnet_v2.k8s_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Cluster size and volume settings
locals {
  profiles = {
    small  = { masters = 1, workers = 2, volume_size = 20 }
    medium = { masters = 2, workers = 2, volume_size = 30 }
    large  = { masters = 3, workers = 6, volume_size = 50 }
  }
  profile = local.profiles[var.cluster_profile]
}

# Cluster profile selection
variable "cluster_profile" {
  description = "Cluster profile (small, medium, large)"
  type        = string
  default     = "small"
}

# Master nodes
resource "openstack_compute_instance_v2" "masters" {
  count       = local.profile.masters
  name        = "k8s-master-${count.index}"
  flavor_name = var.master_flavor
  key_pair    = var.keypair
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    uuid       = openstack_networking_network_v2.k8s_network.id
    fixed_ip_v4 = "172.16.254.${10 + count.index}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = local.profile.volume_size
    volume_type           = var.volume_type
    boot_index            = 0
    delete_on_termination = true
  }

  depends_on = [
    openstack_networking_subnet_v2.k8s_subnet,
    openstack_networking_router_interface_v2.k8s_router_interface
  ]

  user_data = templatefile(
    count.index == 0 ? "cloudinit/master-main.sh.tpl" :
    count.index == 1 ? "cloudinit/master-default.sh.tpl" :
    "cloudinit/master-default.sh.tpl",
    {
      master_ip          = "172.16.254.10"
      kubernetes_version = var.kubernetes_version
      crio_version       = var.crio_version
      enable_dashboard   = var.enable_dashboard
      count              = count.index
      user               = var.default_os_user
      count_master       = local.profile.masters
      count_worker       = local.profile.workers
    }
  )
}

# Worker nodes
resource "openstack_compute_instance_v2" "workers" {
  count       = local.profile.workers
  name        = "k8s-worker-${count.index}"
  flavor_name = var.worker_flavor
  key_pair    = var.keypair
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    uuid       = openstack_networking_network_v2.k8s_network.id
    fixed_ip_v4 = "172.16.254.${20 + count.index}"
  }

  block_device {
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = local.profile.volume_size
    volume_type           = var.volume_type
    boot_index            = 0
    delete_on_termination = true
  }

  depends_on = [
    openstack_networking_subnet_v2.k8s_subnet,
    openstack_networking_router_interface_v2.k8s_router_interface,
    openstack_compute_instance_v2.masters
  ]

  user_data = templatefile("cloudinit/worker.sh.tpl", {
    master_ip          = "172.16.254.10"
    kubernetes_version = var.kubernetes_version
    crio_version       = var.crio_version
    count              = count.index
  })
}
