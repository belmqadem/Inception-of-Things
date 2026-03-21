#!/bin/bash

set -euo pipefail

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server \
    --bind-address=192.168.56.110 \
    --node-ip=192.168.56.110 \
    --flannel-iface=eth1 \
    --write-kubeconfig-mode=644" \
  sh -

cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token

echo "K3s controller is ready!"
