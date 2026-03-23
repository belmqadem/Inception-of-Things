#!/bin/bash

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"

# ── Cluster ───────────────────────────────────────────────────────────────────

k3d cluster create "iot-cluster" --port "8888:8888@loadbalancer" --wait

# ── Namespaces ────────────────────────────────────────────────────────────────

kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$DEV_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── Argo CD ───────────────────────────────────────────────────────────────────

kubectl apply -n "$ARGOCD_NAMESPACE" \
  --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

until kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" 2>/dev/null; do
  sleep 3
done
kubectl wait --for=condition=available deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" --timeout=600s

# ── Argo CD App ───────────────────────────────────────────────────────────────

kubectl apply -f "$(dirname "$0")/../confs/dev-app.yaml"

until kubectl get pods -n "$DEV_NAMESPACE" 2>/dev/null | grep -q "Running"; do
  sleep 5
done

echo "Cluster and Argo CD are ready!"
