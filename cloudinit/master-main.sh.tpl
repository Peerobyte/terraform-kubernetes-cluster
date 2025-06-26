#!/bin/bash

# Exit on error
set -e

# Set hostname
hostnamectl set-hostname k8s-master-0
echo "127.0.0.1 k8s-master-0" >> /etc/hosts

# Set control-plane
echo "${master_ip} k8s-contorl-plane" >> /etc/hosts

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Update system and install required packages
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

# Install CRI-O
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${crio_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/v${crio_version}/deb/ /" > /etc/apt/sources.list.d/cri-o.list
apt-get update
apt-get install -y cri-o
systemctl enable crio
systemctl start crio

# Install kubeadm, kubelet and kubectl
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kubernetes_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Add master node to /etc/hosts
echo "${master_ip} k8s-master-0" >> /etc/hosts

# Enable br_netfilter module and sysctl for bridge networking
modprobe br_netfilter
echo 'br_netfilter' > /etc/modules-load.d/k8s.conf
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# Initialize Kubernetes cluster
echo '[INFO] Starting master node initialization...'
kubeadm init --control-plane-endpoint=k8s-contorl-plane --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${master_ip} --ignore-preflight-errors=all

# Configure kubectl for root user
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

# Configure kubectl for ${user} user
mkdir -p /home/${user}/.kube
cp -i /etc/kubernetes/admin.conf /home/${user}/.kube/config
chown ${user}:${user} /home/${user}/.kube/config

# Export KUBECONFIG for root user
export KUBECONFIG=/etc/kubernetes/admin.conf

# Install Flannel CNI
echo '[INFO] Installing Flannel CNI...'

curl -o /tmp/kube-flannel.yml https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

awk '
BEGIN {in_net = 0}
/^[[:space:]]+net-conf.json: \|/ {
  print "  net-conf.json: |"
  print "    {"
  print "      \"Network\": \"10.244.0.0/16\","
  print "      \"EnableNFTables\": false,"
  print "      \"Backend\": {"
  print "        \"Type\": \"vxlan\","
  print "        \"VNI\": 1,"
  print "        \"Port\": 65414"
  print "      }"
  print "    }"
  in_net = 1
  next
}
in_net {
  # Заканчиваем пропуск, когда находим строку "---" или другую секцию
  if (/^---/ || /^[^[:space:]]/) { in_net = 0; print }
  next
}
{ print }
' /tmp/kube-flannel.yml > /tmp/kube-flannel-patched.yml

kubectl apply -f /tmp/kube-flannel-patched.yml


# Install and configure nginx
echo '[INFO] Installing and configuring nginx...'
apt-get update
apt-get install -y nginx
mkdir -p /var/www/html
chown -R www-data:www-data /var/www/html

# Create join script
echo '[INFO] Creating join script...'
JOIN_COMMAND=$(kubeadm token create --print-join-command --ttl=24h)
if [ -z "$JOIN_COMMAND" ]; then
    echo "Error: Failed to create join command"
    exit 1
fi
echo "$JOIN_COMMAND" > /var/www/html/join.sh
chmod +x /var/www/html/join.sh
chown www-data:www-data /var/www/html/join.sh

echo '[INFO] Creating join script for masters...'
JOIN_CMD=$(kubeadm token create --print-join-command --ttl=24h)
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -1)

if [ -z "$JOIN_CMD" ] || [ -z "$CERT_KEY" ]; then
    echo "Error: Failed to create master join command or cert key"
    exit 1
fi

echo "$JOIN_CMD --control-plane --certificate-key $CERT_KEY" > /var/www/html/join-master.sh
chmod +x /var/www/html/join-master.sh
chown www-data:www-data /var/www/html/join-master.sh

# Configure nginx
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
        autoindex on;
    }
}
EOF

systemctl restart nginx

echo '[INFO] Master node initialization completed successfully!'

# Install Kubernetes Dashboard if enabled
if [ "${enable_dashboard}" = "true" ]; then
    echo '[INFO] Installing Kubernetes Dashboard...'
    kubectl create namespace kubernetes-dashboard
    kubectl create secret generic kubernetes-dashboard-csrf --from-literal=csrf=placeholder -n kubernetes-dashboard

    cat > /tmp/dashboard.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: kubernetes-dashboard
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
spec:
  type: NodePort
  ports:
    - port: 443
      targetPort: 8443
      nodePort: 30007
  selector:
    k8s-app: kubernetes-dashboard
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: kubernetes-dashboard
  template:
    metadata:
      labels:
        k8s-app: kubernetes-dashboard
    spec:
      serviceAccountName: admin-user
      containers:
        - name: kubernetes-dashboard
          image: kubernetesui/dashboard:v2.7.0
          imagePullPolicy: Always
          ports:
            - containerPort: 8443
              protocol: TCP
          args:
            - --auto-generate-certificates
            - --namespace=kubernetes-dashboard
          volumeMounts:
            - name: tmp-volume
              mountPath: /tmp
            - name: certs-volume
              mountPath: /certs
      volumes:
        - name: tmp-volume
          emptyDir: {}
        - name: certs-volume
          emptyDir: {}
EOF

    kubectl apply -f /tmp/dashboard.yaml

    # Store access token
    cat > /home/${user}/dashboard-token.txt <<EOF
$(kubectl -n kubernetes-dashboard create token admin-user)
EOF
    chown ${user}:${user} /home/${user}/dashboard-token.txt
    chmod 600 /home/${user}/dashboard-token.txt
fi

#Wait all nodes

EXPECTED_MASTERS=${count_master}
EXPECTED_WORKERS=${count_worker}
EXPECTED_TOTAL=$((EXPECTED_MASTERS + EXPECTED_WORKERS))

echo "⏳ Waiting for all $EXPECTED_TOTAL nodes ($EXPECTED_MASTERS masters, $EXPECTED_WORKERS workers) to become Ready..."

ATTEMPTS=30
SLEEP_INTERVAL=10

for i in $(seq 1 $ATTEMPTS); do
    if kubectl get nodes --no-headers &>/dev/null; then
        READY_NODES=$(kubectl get nodes --no-headers | grep -c ' Ready')

        if [ "$READY_NODES" -eq "$EXPECTED_TOTAL" ]; then
            echo "✅ All $READY_NODES nodes are Ready"
            break
        else
            echo "⏳ [$i/$ATTEMPTS] Currently Ready: $READY_NODES / $EXPECTED_TOTAL"
        fi
    else
        echo "❌ [$i/$ATTEMPTS] Kubernetes API not ready yet"
    fi

    sleep $SLEEP_INTERVAL

    if [ "$i" -eq "$ATTEMPTS" ]; then
        echo "⛔ Timeout: Not all nodes became Ready after $((ATTEMPTS * SLEEP_INTERVAL)) seconds"
        exit 1
    fi
done

echo "⬇️ Proceeding with detailed health checks..."

#Kubernetes health check

NAMESPACE="kube-system"
TEST_NS="health-check"
TEST_POD_NAME="dns-checker"

PASS=true

echo "⏳ Checking access to Kubernetes API server..."
if ! kubectl get --raw /healthz > /dev/null 2>&1; then
    echo "❌ API server is not reachable"
    PASS=false
else
    echo "✅ API server is reachable"
fi

echo "⏳ Checking node status..."
if ! kubectl get nodes > /dev/null 2>&1; then
    echo "❌ Unable to retrieve node list"
    PASS=false
else
    echo "✅ Nodes are healthy"
fi

echo "⏳ Checking system pods in namespace '$NAMESPACE'..."
if ! kubectl get pods -n $NAMESPACE > /dev/null 2>&1; then
    echo "❌ Failed to get system pods"
    PASS=false
else
    echo "✅ System pods are running"
fi

echo "⏳ Creating test namespace '$TEST_NS' (if not exists)..."
kubectl create ns $TEST_NS 2>/dev/null || echo "ℹ️ Namespace already exists"

echo "⏳ Starting test pod for DNS check..."
kubectl run $TEST_POD_NAME --image=busybox:1.28 -n $TEST_NS --restart=Never -- sleep 300 > /dev/null 2>&1

echo "⏳ Waiting for test pod to become ready..."
if ! kubectl wait --for=condition=Ready pod/$TEST_POD_NAME -n $TEST_NS --timeout=60s > /dev/null 2>&1; then
    echo "❌ Test pod did not become ready"
    PASS=false
else
    echo "✅ Test pod is ready"
fi

echo "⏳ Testing DNS resolution inside the pod..."
if ! kubectl exec -n $TEST_NS $TEST_POD_NAME -- nslookup kubernetes.default > /dev/null 2>&1; then
    echo "❌ DNS resolution failed inside the pod"
    PASS=false
else
    echo "✅ DNS resolution successful"
fi

echo "⏳ Testing network connectivity between pods using HTTP..."

POD1="netcheck-curl"
POD2="netcheck-http"

# Start HTTP server pod
kubectl run $POD2 --image=nginxdemos/hello -n $TEST_NS --restart=Never --port=80 > /dev/null 2>&1

# Start curl pod
kubectl run $POD1 --image=curlimages/curl -n $TEST_NS --restart=Never -- sleep 300 > /dev/null 2>&1

# Wait for both to be ready
kubectl wait --for=condition=Ready pod/$POD1 -n $TEST_NS --timeout=30s > /dev/null 2>&1
kubectl wait --for=condition=Ready pod/$POD2 -n $TEST_NS --timeout=30s > /dev/null 2>&1

# Get IP of the HTTP pod
IP2=$(kubectl get pod $POD2 -n $TEST_NS -o jsonpath='{.status.podIP}')

if [ -z "$IP2" ]; then
    echo "❌ Could not retrieve Pod IP"
    PASS=false
else
    if ! kubectl exec -n $TEST_NS $POD1 -- curl -s --max-time 5 http://$IP2:80 > /dev/null; then
        echo "❌ Pod-to-pod HTTP connectivity failed"
        PASS=false
    else
        echo "✅ Pod-to-pod HTTP connectivity is OK"
    fi
fi

echo "🧹 Cleaning up test namespace..."
kubectl delete ns $TEST_NS --grace-period=0 --force > /dev/null 2>&1

echo "📋 Cluster health check result:"
if $PASS; then
    echo -e "\n✅ GOOD"
    exit 0
else
    echo -e "\n❌ NOT GOOD"
    exit 1
fi