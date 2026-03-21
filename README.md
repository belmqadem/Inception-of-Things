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

- [Vagrant](https://www.vagrantup.com/) `>= 2.4.9`
- [VMware Fusion](https://www.vmware.com/products/fusion.html) (Apple Silicon) or VirtualBox (Intel/Linux)
- [vagrant-vmware-desktop](https://developer.hashicorp.com/vagrant/docs/providers/vmware) plugin `>= 3.0.5`
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

---

## Part 1: K3s and Vagrant

### Goal

Set up 2 virtual machines using Vagrant with K3s installed:

- `<login>S` — K3s in controller mode at `192.168.56.110`
- `<login>SW` — K3s in agent mode at `192.168.56.111`

### Steps followed

#### 1. Initialize the Vagrantfile

```bash
vagrant init bento/debian-11 --box-version 202508.03.0
```

Box found at: https://portal.cloud.hashicorp.com/vagrant/discover

#### 2. Configure the Vagrantfile

Updated the Vagrantfile to define 2 VMs with their hostnames, IPs, and provisioning scripts.
Following: https://developer.hashicorp.com/vagrant/docs/multi-machine

Key configurations:

- Private network interface with dedicated IPs for each VM
- 1 CPU and 1024MB RAM per VM
- Shell provisioning scripts for K3s installation

#### 3. Write the provisioning scripts

Two scripts in `p1/scripts/`:

- `install-k3s-controller-mode.sh` — installs K3s in controller mode
- `install-k3s-agent-mode.sh` — installs K3s in agent mode

The server generates a token at `/var/lib/rancher/k3s/server/node-token` after installation.
This token is shared with the worker via the Vagrant shared folder `/vagrant` so the worker
can authenticate and join the cluster.

Following: https://docs.k3s.io/quick-start

#### 4. Network configuration

Since Vagrant VMs have 2 network interfaces:

- `eth0` — NAT interface (internet access, wrong IP)
- `eth1` — Private network (192.168.56.x, correct IP)

We explicitly set `--flannel-iface=eth1` to force K3s to use the correct interface
for node-to-node communication.

### Usage

```bash
cd p1
vagrant up
vagrant ssh abel-mqaS
kubectl get nodes
```

### Expected output

```bash
NAME          STATUS   ROLES           AGE   VERSION
<login>s     Ready    control-plane   Xm    v1.x.x
<login>sw    Ready    <none>          Xm    v1.x.x
```

Note: Linux lowercases hostnames automatically — `<login>S` displays as `<login>s`. This is expected behavior.

---

## Part 2: K3s and three simple applications

### Goal

One VM running K3s with 3 web applications, accessible via different hostnames
all pointing to the same IP `192.168.56.110`:

- `app1.com` → App 1
- `app2.com` → App 2 (3 replicas)
- anything else → App 3 (default backend)

### Steps followed

#### 1. Initialize the Vagrantfile

One VM with K3s in server mode, same configuration as Part 1 but with a single machine.

#### 2. Write the Kubernetes manifests

Three manifest files in `p2/confs/`:

- `app1.yaml` — Deployment (1 replica) + Service + ConfigMap with custom HTML
- `app2.yaml` — Deployment (3 replicas) + Service + ConfigMap with custom HTML
- `app3.yaml` — Deployment (1 replica) + Service + ConfigMap with custom HTML
- `ingress.yaml` — Ingress routing rules by HOST header

#### 3. Ingress routing

Traefik acts as the Ingress controller, routing traffic based on the `Host` header:

```
Browser request → Traefik (port 80) → Service → Pod(s)
```

The `defaultBackend` catches all unmatched hosts and routes to app3.

#### 4. App differentiation

Each app has a distinct colored HTML page served via a ConfigMap mounted as a volume
into the nginx container:

- App 1 → green page
- App 2 → blue page
- App 3 → orange page (default backend)

### Usage

```bash
cd p2
vagrant up
vagrant ssh <login>S
```

### Verify everything is running

```bash
kubectl get pods
kubectl get services
kubectl get ingress
```

### Expected output

```bash
NAME                    READY   STATUS    RESTARTS   AGE
app1-xxx                1/1     Running   0          Xm
app2-xxx                1/1     Running   0          Xm
app2-xxx                1/1     Running   0          Xm
app2-xxx                1/1     Running   0          Xm
app3-xxx                1/1     Running   0          Xm
```

### Test routing

```bash
curl -H "Host: app1.com" http://192.168.56.110   # → green page
curl -H "Host: app2.com" http://192.168.56.110   # → blue page
curl http://192.168.56.110                        # → orange page (default)
```

### Key concepts learned

**ConfigMap** — stores configuration data as key-value pairs. Used here to inject
custom HTML into nginx containers without rebuilding the image.

**Ingress** — exposes HTTP routes from outside the cluster to services inside.
Routes based on HOST header, path, or both.

**Replicas** — multiple identical pods running simultaneously. App2 runs 3 replicas
for load balancing. Kubernetes automatically distributes traffic between them.

**Labels and Selectors** — the glue between Deployments, Services, and Ingress.
A Service finds its pods by matching labels defined in the Deployment.

## Part 3: K3d and Argo CD

_In progress_

## Bonus: Gitlab

_In progress_
