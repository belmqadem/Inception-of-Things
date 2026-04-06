#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot-cluster"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"

# ── Cluster ───────────────────────────────────────────────────────────────────
echo "[1] Creating K3d cluster..."
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
k3d cluster create "$CLUSTER_NAME" --port "8888:8888@loadbalancer" --wait

echo "Waiting for cluster to be ready..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

# ── Namespaces ────────────────────────────────────────────────────────────────
echo "[2] Creating namespaces..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$DEV_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── Argo CD ───────────────────────────────────────────────────────────────────
echo "[3] Installing Argo CD..."
kubectl apply -n "$ARGOCD_NAMESPACE" \
  --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for Argo CD to be ready..."
until kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" 2>/dev/null; do
  sleep 3
done
kubectl wait --for=condition=available deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" --timeout=600s

# ── Argo CD App ───────────────────────────────────────────────────────────────
echo "[4] Deploying Argo CD application..."
kubectl apply -f "$(dirname "$0")/../confs/dev-app.yaml"

echo "Waiting for Argo CD application to be ready..."
until kubectl get pods -n "$DEV_NAMESPACE" 2>/dev/null | grep -q "Running"; do
  sleep 5
done

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
