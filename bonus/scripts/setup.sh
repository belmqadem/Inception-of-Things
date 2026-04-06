#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot-cluster-bonus"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITLAB_NAMESPACE="gitlab"
GITLAB_REPO="http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/abel-mqa-iot.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Cluster ───────────────────────────────────────────────────────────────────
echo "[1] Creating K3d cluster..."
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
k3d cluster create "$CLUSTER_NAME" --port "8888:8888@loadbalancer" --wait

# ── Namespaces ────────────────────────────────────────────────────────────────
echo "[2] Creating namespaces..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$DEV_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$GITLAB_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── GitLab ────────────────────────────────────────────────────────────────────
echo "[3] Installing GitLab..."
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --namespace "$GITLAB_NAMESPACE" \
  --values "$SCRIPT_DIR/../confs/gitlab-values.yaml" \
  --timeout 600s

echo "      Waiting for GitLab to be ready (this takes a few minutes)..."
kubectl wait --for=condition=ready pod \
  -l app=webservice \
  -n "$GITLAB_NAMESPACE" \
  --timeout=600s

GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password \
  -n "$GITLAB_NAMESPACE" \
  -o jsonpath='{.data.password}' | base64 --decode)

# ── Prompt user to push manifests ─────────────────────────────────────────────
kubectl port-forward svc/gitlab-webservice-default -n "$GITLAB_NAMESPACE" 8181:8181 &
GITLAB_PF_PID=$!
sleep 3

echo ""
echo "──────────────────────────────────────────────────────"
echo "  GitLab is ready at http://localhost:8181"
echo "  Login: root / $GITLAB_PASSWORD"
echo ""
echo "  Please:"
echo "  1. Create a new project named: abel-mqa-iot (Public)"
echo "  2. In a new terminal, run:"
echo ""
echo "     cd $SCRIPT_DIR/.."
echo "     git remote add gitlab http://root:$GITLAB_PASSWORD@localhost:8181/root/abel-mqa-iot.git"
echo "     git subtree push --prefix bonus/manifests gitlab main"
echo "──────────────────────────────────────────────────────"
echo ""
read -rp "Press ENTER once you have pushed the manifests..."

kill $GITLAB_PF_PID 2>/dev/null || true

# ── Argo CD ───────────────────────────────────────────────────────────────────
echo "[4] Installing Argo CD..."
kubectl apply -n "$ARGOCD_NAMESPACE" \
  --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  2>&1 | grep -v "^$" | grep -v "unchanged" || true

echo "      Waiting for Argo CD to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" --timeout=600s

# ── Configure Argo CD → GitLab ────────────────────────────────────────────────
echo "[5] Connecting Argo CD to local GitLab..."
kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443 &
ARGOCD_PF_PID=$!
sleep 5

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "$ARGOCD_NAMESPACE" \
  -o jsonpath='{.data.password}' | base64 --decode)

argocd login localhost:8080 \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure 2>/dev/null

argocd repo add "$GITLAB_REPO" \
  --username root \
  --password "$GITLAB_PASSWORD" \
  --insecure-skip-server-verification

kill $ARGOCD_PF_PID 2>/dev/null || true

# ── Deploy App ────────────────────────────────────────────────────────────────
echo "[6] Deploying app via Argo CD..."
kubectl apply -f "$SCRIPT_DIR/../confs/dev-app.yaml"

until kubectl get pods -n "$DEV_NAMESPACE" 2>/dev/null | grep -q "Running"; do
  sleep 5
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────────────"
echo "  Done!"
echo "  App:    http://localhost:8888"
echo "  GitLab: kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181"
echo "  ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "  GitLab password : $GITLAB_PASSWORD"
echo "  ArgoCD password : $ARGOCD_PASSWORD"
echo "──────────────────────────────────────────────────────"
