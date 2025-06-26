variable "auth_url" {
  description = "The authentication URL for OpenStack"
  type        = string
}

variable "tenant_name" {
  description = "The tenant name for OpenStack"
  type        = string
}

variable "user" {
  description = "The username for OpenStack"
  type        = string
}

variable "password" {
  description = "The password for OpenStack"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "The domain name for OpenStack"
  type        = string
}

variable "region" {
  description = "The region for OpenStack"
  type        = string
  default     = "RegionOne"
}

variable "image_name" {}
variable "master_flavor" {}
variable "worker_flavor" {}
variable "keypair" {}
variable "external_network_id" {}

variable "cluster_size" {
  default = "small"
}

variable "enable_dashboard" {
  description = "Enable Kubernetes Dashboard deployment"
  type        = bool
  default     = false
}

variable "volume_type" {
  description = "Type of volume backend to use (e.g. Hybrid-Datastore, All-Flash-Datastore)"
  type        = string
  default     = "All-Flash-Datastore"
}

variable "master_volume_size" {
  description = "Size of the master node volume in GB"
  type        = number
  default     = 20
}

variable "worker_volume_size" {
  description = "Size of the worker node volume in GB"
  type        = number
  default     = 20
}

variable "os_codename" {
  default = "Debian_12"
}

variable "default_os_user" {
  default = "debian"
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.33"
}

variable "crio_version" {
  description = "CRI-O version to install"
  type        = string
  default     = "1.33"
}