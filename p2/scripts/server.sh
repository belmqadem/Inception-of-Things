#!/bin/bash

set -euo pipefail

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server \
    --bind-address=192.168.56.110 \
    --node-ip=192.168.56.110 \
    --flannel-iface=eth1 \
    --write-kubeconfig-mode=644" \
  sh -

sleep 10

kubectl apply -f /vagrant/confs/

echo "K3s server is ready!"
