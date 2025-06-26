#!/bin/bash

# Exit on error
set -e

# Set hostname
hostnamectl set-hostname k8s-worker-${count}
echo "127.0.0.1 k8s-worker-${count}" >> /etc/hosts

# Set control-plane
echo "${master_ip} k8s-contorl-plane" >> /etc/hosts

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Update system and install required packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

# Install CRI-O
# Add CRI-O repo and key
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${crio_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${crio_version}/deb/ /" > /etc/apt/sources.list.d/cri-o.list

apt-get update
apt-get install -y cri-o

# Start and enable CRI-O
systemctl enable crio
systemctl start crio

# Install kubeadm, kubelet and kubectl
echo "Installing Kubernetes components..."
# Create /etc/apt/keyrings if it doesn't exist
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Add master node to /etc/hosts
echo "${master_ip} k8s-master-0" >> /etc/hosts

# Ensure bridge networking is configured properly for Kubernetes
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/k8s.conf

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system


# Join the cluster
# Wait for the master to be ready (join.sh available)
echo "[INFO] Waiting for join.sh to become available on the master node..."
until curl -sf http://${master_ip}/join.sh > /dev/null; do
  echo "[INFO] Master not ready, retrying in 10 seconds..."
  sleep 10
done

echo "[INFO] Master is ready. Proceeding to join the cluster..."
curl -s http://${master_ip}/join.sh | bash

echo '[INFO] Worker node initialization completed successfully!'