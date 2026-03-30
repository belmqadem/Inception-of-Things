#!/bin/bash
set -e  

echo "=== [1/6] Installing Docker ==="
if ! command -v docker &> /dev/null; then
  sudo apt update -y
  sudo apt install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo usermod -aG docker $USER   
  echo "Docker installed."
else
  echo "Docker already installed, skipping."
fi

echo "=== [2/6] Installing kubectl ==="
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  echo "kubectl installed."
else
  echo "kubectl already installed, skipping."
fi

echo "=== [3/6] Installing K3d ==="
if ! command -v k3d &> /dev/null; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "K3d installed."
else
  echo "K3d already installed, skipping."
fi

echo "=== [4/6] Creating K3d cluster ==="
# Delete existing cluster if it exists (clean start)
k3d cluster delete msaadidi-cluster 2>/dev/null || true

# Create a cluster with port 8888 exposed on localhost
# --port "8888:8888@loadbalancer" → forward localhost:8888 to the cluster's port 8888
k3d cluster create msaadidi-cluster \
  --port "8888:8888@loadbalancer" \
  --wait    # Wait until all nodes are Ready before returning

echo "Cluster created."

echo "=== [5/6] Installing ArgoCD ==="
# Create the argocd namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --dry-run=client -o yaml | kubectl apply -f - is a safe way to create namespaces
# it won't error if the namespace already exists

# Apply the official ArgoCD install manifest
kubectl apply -n argocd \
    --server-side \
    --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD to be ready (this takes 3-5 min on first run)..."
until kubectl get deployment argocd-server -n argocd \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; do
  echo "  still waiting... $(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c Running) pods running"
  sleep 10
done
echo "ArgoCD is ready."

echo "=== [6/6] Deploying ArgoCD Application ==="
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"

echo ""
echo "=== DONE ==="
echo ""
echo "ArgoCD is running. To access the UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "  Then open: https://localhost:8080"
echo ""
echo "Get the ArgoCD admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret \\"
echo "    -o jsonpath='{.data.password}' | base64 -d && echo"
echo ""
echo "Your app will be available at:"
echo "  kubectl port-forward svc/wil-playground-svc -n dev 8888:8888 &"
echo "  curl http://localhost:8888"
