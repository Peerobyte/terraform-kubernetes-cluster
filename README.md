# Terraform Kubernetes Cluster on OpenStack

This repository contains Terraform code to deploy a full-featured Kubernetes cluster on OpenStack. It provisions both the networking infrastructure and the compute resources (masters and workers), and optionally installs the Kubernetes Dashboard.

---

## 🚀 Features

- Automated provisioning of:
  - OpenStack network, subnet, router
  - Master and worker nodes with user-data (cloud-init)
  - Security groups for Kubernetes (API, Flannel, etcd, NodePorts, DNS, etc.)
- Flexible cluster sizing via profiles (`small`, `medium`, `large`)
- CRI-O and Kubernetes version selection
- Optional Kubernetes Dashboard installation
- Customizable VM flavors and disk types

---

## 📦 Requirements

- Terraform ≥ 1.0
- OpenStack account with:
  - Keypair created
  - Access to image (e.g. Debian 12)
  - Available flavors
- SSH access to your OpenStack project

---

## 🧱 Cluster Profiles

Defined in `main.tf` via `local.profiles`:

| Profile | Masters | Workers | Volume Size (GB) |
|---------|---------|---------|------------------|
| small   | 1       | 2       | 20               |
| medium  | 2       | 3       | 30               |
| large   | 3       | 6       | 50               |

Use the `cluster_profile` variable to switch profiles.

---

## 📁 Project Structure

```
terraform-kubernetes-cluster/
├── .gitignore
├── main.tf                 # Main resources (network, VMs, etc.)
├── variables.tf            # Input variables
├── terraform.tfvars        # Default values and configuration
├── outputs.tf              # Output IPs of nodes
├── cloudinit/              # Cloud-init templates (masters, workers)
└── README.md               # Project documentation
```

---

## ⚙️ Usage

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Configure variables

Edit `terraform.tfvars`:

```hcl
auth_url    = "https://your-openstack:5000/v3"
tenant_name = "your-project"
user        = "your-username"
password    = "your-password"
domain      = "Default"
keypair     = "your-key"
cluster_profile = "medium"
...
```

Or export sensitive values:

```bash
export TF_VAR_password="your-password"
```

### 3. Plan and Apply

```bash
terraform plan
terraform apply
```

---

## 🔐 Security Groups

The configuration creates a security group (`k8s-secgroup`) that allows:

- SSH (22)
- Kubernetes API (6443)
- Flannel VXLAN (65414)
- etcd, DNS, kubelet, kube-scheduler, controller-manager, metrics-server, NodePorts

All internal traffic is allowed within the Kubernetes subnet.

---

## 📤 Outputs

After deployment, the following will be printed:

- Master node IPs
- Worker node IPs

Example:

```bash
master_ips = ["172.16.254.10", "172.16.254.11"]
worker_ips = ["172.16.254.20", "172.16.254.21"]
```

---

## 🧪 Notes

- Cloud-init is used to bootstrap nodes with Kubernetes components.
- `master-main.sh.tpl` is used for the first master node and creates the cluster.
- Additional master nodes run `master-default.sh.tpl` and join as control-plane nodes.
- Workers join via a `join.sh` script served by the first master.

---

## 📞 Support

If you encounter issues with networking (e.g. external connectivity), ensure the `external_network_id` is correct. Contact your support if needed.

---
