#!/bin/bash

set -euo pipefail

while [ ! -f /vagrant/node-token ]; do
  sleep 3
done

TOKEN=$(cat /vagrant/node-token)

curl -sfL https://get.k3s.io | \
  K3S_TOKEN="$TOKEN" \
  INSTALL_K3S_EXEC="agent \
    --server=https://192.168.56.110:6443 \
    --node-ip=192.168.56.111 \
    --flannel-iface=eth1" \
  sh -

echo "K3s agent is ready!"
