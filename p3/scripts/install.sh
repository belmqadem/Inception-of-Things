#!/bin/bash
set -euo pipefail

install_if_missing() {
  if command -v "$1" &>/dev/null; then
    echo "==> $1 already installed, skipping."
  else
    echo "==> Installing $1..."
    brew install "$2"
  fi
}

install_cask_if_missing() {
  if command -v "$1" &>/dev/null; then
    echo "==> $1 already installed, skipping."
  else
    echo "==> Installing $1..."
    brew install --cask "$2"
  fi
}

install_cask_if_missing docker docker
install_if_missing kubectl kubectl
install_if_missing k3d k3d
install_if_missing argocd argocd

echo "==> Starting Docker Desktop..."
open -a Docker
echo "==> Waiting for Docker to be ready..."
until docker info > /dev/null 2>&1; do
  sleep 2
done

echo "==> Versions installed:"
docker --version
k3d --version
kubectl version --client
argocd version --client

echo "==> All dependencies installed!"
