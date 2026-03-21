# Inception-of-Things (IoT)

A 42 School System Administration project that introduces Kubernetes through K3s, K3d, and Argo CD.

## Concepts

### Vagrant

A tool that creates and manages virtual machines using simple configuration files called `Vagrantfile`.

### K3s

A lightweight version of Kubernetes (K8s) designed for resource-constrained environments.
It's the full Kubernetes, just packaged smaller. One node runs as a **controller** (the brain),
others run as **agents** (the workers).

### K3d

K3s running inside Docker containers. No VMs needed — much lighter than K3s with Vagrant.

### Argo CD

A GitOps tool that watches a GitHub repository and automatically deploys whatever is in it
to your cluster. Change a file on GitHub → the cluster updates itself.

---

## Requirements

- [Vagrant](https://www.vagrantup.com/) `>= 2.4.0`
- [VMware Fusion](https://www.vmware.com/products/fusion.html) (Apple Silicon) or VirtualBox (Intel/Linux)
- [vagrant-vmware-desktop](https://developer.hashicorp.com/vagrant/docs/providers/vmware) plugin `>= 3.0.5`
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

## Part 1: K3s and Vagrant

### Overview

This part sets up a minimal Kubernetes cluster using K3s across two Vagrant-managed
virtual machines. One machine acts as the control plane (server) and the other as a
worker node (agent).

| Machine     | Role       | IP             |
| ----------- | ---------- | -------------- |
| `<login>S`  | Controller | 192.168.56.110 |
| `<login>SW` | Agent      | 192.168.56.111 |

---

### Project Structure

```
p1/
├── Vagrantfile
└── scripts/
    ├── install-k3s-controller-mode.sh
    └── install-k3s-agent-mode.sh
```

---

### How It Works

#### Virtual Machines

Both VMs are provisioned using [Vagrant](https://developer.hashicorp.com/vagrant/docs)
with the `bento/debian-11` box. Each is allocated 1 CPU and 1024 MB of RAM, which is
the recommended minimum for running K3s.

#### Network

Vagrant assigns each VM two network interfaces:

- `eth0` — NAT interface used for internet access (not used by K3s)
- `eth1` — Private network interface with a static IP (`192.168.56.x`)

K3s is explicitly told to use `eth1` via `--flannel-iface=eth1` to ensure all
node-to-node communication happens over the correct interface.

#### Token Sharing

After K3s is installed on the controller, it generates a secret token at:

```
/var/lib/rancher/k3s/server/node-token
```

This token is copied to the Vagrant shared folder (`/vagrant/node-token`) so the
agent machine can read it during provisioning and use it to securely join the cluster.
The agent script waits in a loop until the token file is available before proceeding.

#### Provisioning Order

Vagrant provisions the controller first, then the agent. This guarantees the token
exists before the agent tries to read it.

---

### Prerequisites

- [Vagrant](https://developer.hashicorp.com/vagrant/downloads) >= 2.4.0
- [VMware Desktop](https://www.vmware.com/products/fusion.html) (or replace the provider block in the Vagrantfile)
- A working internet connection (K3s is downloaded during provisioning)

---

### Usage

#### Start the cluster

```bash
cd p1
vagrant up
```

This will:

1. Create and boot both VMs
2. Install K3s on the controller (`<login>S`)
3. Share the cluster token via `/vagrant/node-token`
4. Install K3s agent on the worker (`<login>SW`) and join the cluster

#### SSH into a machine

```bash
vagrant ssh <login>S   # controller
vagrant ssh <login>SW  # agent
```

#### Verify the cluster

```bash
vagrant ssh <login>S
kubectl get nodes -o wide
```

#### Stop or destroy the VMs

```bash
vagrant halt      # stop (keeps disk)
vagrant destroy   # remove completely
```

---

### Expected Output

After a successful `vagrant up`, SSHing into the controller and running
`kubectl get nodes` should show both nodes in `Ready` state:

```
NAME          STATUS   ROLES                  AGE   VERSION
<login>s     Ready    control-plane,master   Xm    v1.xx.x+k3s1
<login>sw    Ready    <none>                 Xm    v1.xx.x+k3s1
```

> **Note:** Linux lowercases hostnames automatically — `<login>S` displays as
> `<login>s` and `<login>SW` as `<login>sw`. This is expected behavior.

---

### Testing

All tests are run from your **host machine** unless otherwise noted.

#### 1. Verify both VMs are running

```bash
vagrant status
```

Expected output:

```
abel-mqaS   running (vmware_desktop)
abel-mqaSW  running (vmware_desktop)
```

---

#### 2. Verify passwordless SSH access

```bash
vagrant ssh abel-mqaS  -c "echo 'SSH OK'"
vagrant ssh abel-mqaSW -c "echo 'SSH OK'"
```

Both commands should print `SSH OK` without asking for a password.

---

#### 3. Verify network interfaces and IPs

```bash
vagrant ssh abel-mqaS  -c "ip a show eth1"
vagrant ssh abel-mqaSW -c "ip a show eth1"
```

Expected: `abel-mqaS` shows `192.168.56.110` and `abel-mqaSW` shows `192.168.56.111`
on `eth1`. If the interface name differs on your system (e.g., `enp0s8`), adjust accordingly.

---

#### 4. Verify both nodes are registered and Ready

```bash
vagrant ssh abel-mqaS -c "kubectl get nodes -o wide"
```

Expected output:

```
NAME          STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
abel-mqas     Ready    control-plane,master   Xm    v1.xx.x+k3s1   192.168.56.110
abel-mqasw    Ready    <none>                 Xm    v1.xx.x+k3s1   192.168.56.111
```

Both nodes must show `Ready`. If the agent shows `NotReady`, wait 30 seconds and retry —
it may still be syncing.

---

#### 5. Verify K3s services are running

```bash
# Controller
vagrant ssh abel-mqaS  -c "sudo systemctl is-active k3s"

# Agent
vagrant ssh abel-mqaSW -c "sudo systemctl is-active k3s-agent"
```

Both should return `active`.

---

#### 6. Verify the correct IPs are used by K3s

```bash
vagrant ssh abel-mqaS -c "kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\\n\"}{end}'"
```

Expected output:

```
abel-mqas   192.168.56.110
abel-mqasw  192.168.56.111
```

If K3s picked up the NAT interface IP (typically `10.x.x.x`), the `--flannel-iface`
flag is not working correctly — verify the interface name inside the VM with `ip a`.

---

#### 7. End-to-end cluster test — deploy and schedule a pod

```bash
vagrant ssh abel-mqaS -c "
  kubectl run test-pod --image=nginx --restart=Never
  sleep 10
  kubectl get pod test-pod -o wide
  kubectl delete pod test-pod
"
```

Expected: the pod reaches `Running` state and is scheduled on one of the two nodes.
This confirms the controller can schedule workloads and the agent can run them.

---

### Expected Final State

| Check               | Expected result            |
| ------------------- | -------------------------- |
| `vagrant status`    | Both VMs `running`         |
| SSH (no password)   | Works on both machines     |
| `kubectl get nodes` | Both nodes `Ready`         |
| Controller IP       | `192.168.56.110` on `eth1` |
| Agent IP            | `192.168.56.111` on `eth1` |
| `k3s` service       | `active` on controller     |
| `k3s-agent` service | `active` on agent          |
| Test pod            | Reaches `Running` state    |

---

### Troubleshooting

**Agent fails to join the cluster**
The agent waits up to several minutes for the token file. If provisioning times out,
re-run provisioning manually:

```bash
vagrant provision <login>SW
```

**Wrong IP used by K3s**
If nodes show an unexpected internal IP, verify the interface name inside the VM:

```bash
vagrant ssh <login>S
ip a
```

Then update `--flannel-iface` in the controller script to match the correct interface name.

**VMware provider not found**
Replace the `vmware_desktop` provider block in the Vagrantfile with your provider
(e.g., `virtualbox`). No other changes are needed.

---

### References

- [Vagrant Multi-Machine docs](https://developer.hashicorp.com/vagrant/docs/multi-machine)
- [K3s Quick Start](https://docs.k3s.io/quick-start)
- [K3s Installation Options](https://docs.k3s.io/installation/configuration)
- [bento/debian-11 box](https://portal.cloud.hashicorp.com/vagrant/discover/bento/debian-11)

---

## Part 2: K3s and three simple applications

_In progress_

## Part 3: K3d and Argo CD

_In progress_

## Bonus: Gitlab

_In progress_
