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
<login>S   running (vmware_desktop)
<login>SW  running (vmware_desktop)
```

---

#### 2. Verify passwordless SSH access

```bash
vagrant ssh <login>S  -c "echo 'SSH OK'"
vagrant ssh <login>SW -c "echo 'SSH OK'"
```

Both commands should print `SSH OK` without asking for a password.

---

#### 3. Verify network interfaces and IPs

```bash
vagrant ssh <login>S  -c "ip a show eth1"
vagrant ssh <login>SW -c "ip a show eth1"
```

Expected: `<login>S` shows `192.168.56.110` and `<login>SW` shows `192.168.56.111`
on `eth1`. If the interface name differs on your system (e.g., `enp0s8`), adjust accordingly.

---

#### 4. Verify both nodes are registered and Ready

```bash
vagrant ssh <login>S -c "kubectl get nodes -o wide"
```

Expected output:

```
NAME          STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
<login>s     Ready    control-plane,master   Xm    v1.xx.x+k3s1   192.168.56.110
<login>sw    Ready    <none>                 Xm    v1.xx.x+k3s1   192.168.56.111
```

Both nodes must show `Ready`. If the agent shows `NotReady`, wait 30 seconds and retry —
it may still be syncing.

---

#### 5. Verify K3s services are running

```bash
# Controller
vagrant ssh <login>S  -c "sudo systemctl is-active k3s"

# Agent
vagrant ssh <login>SW -c "sudo systemctl is-active k3s-agent"
```

Both should return `active`.

---

#### 6. Verify the correct IPs are used by K3s

```bash
vagrant ssh <login>S -c "kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\" \"}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\\n\"}{end}'"
```

Expected output:

```
<login>s   192.168.56.110
<login>sw  192.168.56.111
```

If K3s picked up the NAT interface IP (typically `10.x.x.x`), the `--flannel-iface`
flag is not working correctly — verify the interface name inside the VM with `ip a`.

---

#### 7. End-to-end cluster test — deploy and schedule a pod

```bash
vagrant ssh <login>S -c "
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

## Part 2: K3s and Three Simple Applications

### Overview

One VM running K3s in server mode, hosting 3 web applications accessible via the
same IP `192.168.56.110` but differentiated by the HTTP `Host` header:

| Host header   | App   | Replicas | Page color |
| ------------- | ----- | -------- | ---------- |
| `app1.com`    | App 1 | 1        | 🟢 Green   |
| `app2.com`    | App 2 | 3        | 🔵 Blue    |
| anything else | App 3 | 1        | 🟠 Orange  |

---

### Project Structure

```
p2/
├── Vagrantfile
├── scripts/
│   └── server.sh
└── confs/
    ├── app1.yaml
    ├── app2.yaml
    ├── app3.yaml
    └── ingress.yaml
```

---

### How It Works

#### Ingress Routing

K3s ships with [Traefik](https://traefik.io/) as its default Ingress controller.
All HTTP traffic hits Traefik on port 80, which then routes to the correct Service
based on the `Host` header:

```
curl -H "Host: app1.com" http://192.168.56.110
        │
        ▼
   Traefik (port 80)
        │
        ├── Host: app1.com  → app1-service → app1 pod
        ├── Host: app2.com  → app2-service → app2 pods (x3)
        └── anything else   → app3-service → app3 pod
```

### Why Two Ingress Objects

Traefik does **not** support the `defaultBackend` field of the Ingress spec — it
returns 404 for unmatched hosts instead of falling back to it. To handle the default
case, a second Ingress object with `host: ""` and a low router priority (`"1"`) is
used. Named host rules get a higher default priority and always win for `app1.com`
and `app2.com`, while everything else falls through to app3.

### App Differentiation

Each app serves a distinct HTML page injected via a **ConfigMap** mounted as a volume
into the nginx container. This avoids building custom Docker images — the stock
`nginx:1.27-alpine` image is reused for all three apps.

### Replicas

App 2 runs with `replicas: 3`. Kubernetes automatically load-balances traffic across
all three pods through the Service. Each request may be served by a different pod.

---

### Prerequisites

- [Vagrant](https://developer.hashicorp.com/vagrant/downloads) >= 2.4.0
- [VMware Desktop](https://www.vmware.com/products/fusion.html) (or replace the provider block)
- A working internet connection (K3s and nginx image are pulled during provisioning)

---

### Usage

#### Start the VM

```bash
cd p2
vagrant up
```

This will:

1. Create and boot the VM (`<login>S`) at `192.168.56.110`
2. Install K3s in server mode
3. Wait for the API server to be ready
4. Apply all manifests from `confs/`

### SSH into the VM

```bash
vagrant ssh <login>S
```

### Stop or destroy the VM

```bash
vagrant halt      # stop (keeps disk)
vagrant destroy   # remove completely
```

---

### Testing

All `curl` tests can be run from your **host machine**.
All `kubectl` tests can be run either from the host or inside the VM.

#### 1. Verify the node is Ready

```bash
vagrant ssh <login>S -c "kubectl get nodes"
```

Expected:

```
NAME        STATUS   ROLES                  AGE   VERSION
<login>s   Ready    control-plane,master   Xm    v1.xx.x+k3s1
```

---

#### 2. Verify all pods are Running

```bash
vagrant ssh <login>S -c "kubectl get pods -o wide"
```

Expected: 5 pods total — all in `Running` state:

```
NAME                    READY   STATUS    RESTARTS   AGE
app1-xxxxxxxxx-xxxxx    1/1     Running   0          Xm
app2-xxxxxxxxx-xxxxx    1/1     Running   0          Xm
app2-xxxxxxxxx-xxxxx    1/1     Running   0          Xm
app2-xxxxxxxxx-xxxxx    1/1     Running   0          Xm
app3-xxxxxxxxx-xxxxx    1/1     Running   0          Xm
```

---

#### 3. Verify app2 has exactly 3 replicas

```bash
vagrant ssh <login>S -c "kubectl get deployment app2"
```

Expected:

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
app2   3/3     3            3           Xm
```

---

#### 4. Verify the Ingress is configured

```bash
vagrant ssh <login>S -c "kubectl get ingress"
```

Expected:

```
NAME             CLASS     HOSTS                ADDRESS          PORTS   AGE
ingress-rules    traefik   app1.com,app2.com    192.168.56.110   80      Xm
ingress-default  traefik   *                    192.168.56.110   80      Xm
```

---

#### 5. Test host-based routing

```bash
# App 1 — green page
curl -H "Host: app1.com" http://192.168.56.110
# Expected: HTML containing "App 1"

# App 2 — blue page
curl -H "Host: app2.com" http://192.168.56.110
# Expected: HTML containing "App 2"

# App 3 — default, no Host header
curl http://192.168.56.110
# Expected: HTML containing "App 3"

# App 3 — default, unrecognized host
curl -H "Host: anything.com" http://192.168.56.110
# Expected: HTML containing "App 3"

curl -H "Host: notarealsite.io" http://192.168.56.110
# Expected: HTML containing "App 3"
```

---

#### 6. Test app2 load balancing across replicas

Run the same request multiple times — Kubernetes distributes traffic across all
3 replicas:

```bash
for i in $(seq 1 6); do
  curl -s -H "Host: app2.com" http://192.168.56.110 | grep "<h1>"
done
```

To see which pod is actually serving each request, check pod logs:

```bash
vagrant ssh <login>S -c "kubectl logs -l app=app2 --prefix=true"
```

---

### Expected Final State

| Check                         | Expected                     |
| ----------------------------- | ---------------------------- |
| `kubectl get nodes`           | 1 node `Ready`               |
| `kubectl get pods`            | 5 pods `Running` (1 + 3 + 1) |
| `kubectl get deployment app2` | `READY 3/3`                  |
| `kubectl get ingress`         | 2 ingress objects            |
| `curl -H "Host: app1.com"`    | App 1 — green page           |
| `curl -H "Host: app2.com"`    | App 2 — blue page            |
| `curl` (no host)              | App 3 — orange page          |
| `curl -H "Host: anything"`    | App 3 — orange page          |

---

### Troubleshooting

**Pods stuck in `ContainerCreating`**
The nginx image is being pulled. Wait 30–60 seconds and check again:

```bash
vagrant ssh <login>S -c "kubectl describe pod <pod-name>"
```

**curl returns 404**
Traefik does not support the `defaultBackend` field — unmatched hosts return 404
instead of falling back. This is handled by the `ingress-default` object with
`host: ""` and low priority. Verify it exists:

```bash
vagrant ssh <login>S -c "kubectl get ingress ingress-default"
```

**curl returns connection refused**
K3s or Traefik may still be starting. Wait a minute and retry. You can check:

```bash
vagrant ssh <login>S -c "sudo systemctl status k3s"
vagrant ssh <login>S -c "kubectl get pods -n kube-system"
```

---

### Key Concepts

**ConfigMap** — stores configuration data as key-value pairs. Used here to inject
custom HTML into nginx containers without rebuilding the image. Mounted as a volume
at `/usr/share/nginx/html`.

**Ingress** — exposes HTTP routes from outside the cluster to Services inside.
Traefik watches all Ingress resources and builds its routing table from them.
Routes are matched by `Host` header, path, or both.

**Replicas** — multiple identical pods running simultaneously. App 2 runs 3 replicas.
Kubernetes distributes incoming traffic across all of them via the Service.

**Labels and Selectors** — the glue between Deployments, Services, and Ingress.
A Service finds its target pods by matching the `app: <name>` label defined in
the Deployment's pod template.

---

### References

- [Vagrant docs](https://developer.hashicorp.com/vagrant/docs)
- [K3s Quick Start](https://docs.k3s.io/quick-start)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Traefik Kubernetes Ingress](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)

---

## Part 3: K3d and Argo CD

_In progress_

## Bonus: Gitlab

_In progress_
