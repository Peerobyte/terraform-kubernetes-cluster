##########################################
# OpenStack authentication (IaaS access)
# Authorize access to your OpenStack project
##########################################
auth_url    = "https://your-openstack-endpoint:5000/v3"
tenant_name = "your-project-name"         # OpenStack project (tenant) name
user        = "your-username"             # OpenStack user login
password    = "your-password"             # OpenStack user password (use TF_VAR_password for security)
domain      = "your-domain-name"          # Usually 'Default' or project-specific domain

##########################################
# Cluster profile
# Defines the size of the cluster: number of master and worker nodes
# and the disk volume size for each node.
# Values are set via local.profiles in main.tf
# Available profiles: small, medium, large
##########################################
cluster_profile = "medium"

##########################################
# Kubernetes component versions
##########################################
kubernetes_version = "1.33"
crio_version       = "1.33"

##########################################
# Virtual machine flavors (CPU/RAM sizes)
# These are flavor names defined in your OpenStack project
# Minimum recommendation for Kubernetes:
# - masters: 2 vCPU / 4 GB RAM
# - workers: 2 vCPU / 4–8 GB RAM
##########################################
master_flavor = "de2.g.dot"
worker_flavor = "de2.g.dot"

##########################################
# VM disk volume type
# Available options:
# - "All-Flash-Datastore" (default)
# - "Hybrid-Datastore" 
##########################################
volume_type = "All-Flash-Datastore"

##########################################
# Image name used to create VM instances
# Must match an image available in your OpenStack project
##########################################
image_name = "Debian_12_x64"

##########################################
# Default OS username
# Must match the default user for the image (e.g. 'debian', 'ubuntu')
##########################################
default_os_user = "debian"

##########################################
# SSH keypair name in OpenStack
# This must be an existing keypair in your OpenStack project
##########################################
keypair = "k8s"

##########################################
# External network ID used to connect the router
# This is your OpenStack provider's public/external network
# If this value is invalid or causes issues — contact support
##########################################
external_network_id = "35f22b46-ec84-4a43-ba2c-ac865bd2c22a"

##########################################
# Enable Kubernetes Dashboard (true/false)
# Enables web UI on the cluster
##########################################
enable_dashboard = "true"
