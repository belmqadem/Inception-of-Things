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

| Machine      | Role       | IP             |
| ------------ | ---------- | -------------- |
| `abel-mqaS`  | Controller | 192.168.56.110 |
| `abel-mqaSW` | Agent      | 192.168.56.111 |

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
2. Install K3s on the controller (`abel-mqaS`)
3. Share the cluster token via `/vagrant/node-token`
4. Install K3s agent on the worker (`abel-mqaSW`) and join the cluster

#### SSH into a machine

```bash
vagrant ssh abel-mqaS   # controller
vagrant ssh abel-mqaSW  # agent
```

#### Verify the cluster

```bash
vagrant ssh abel-mqaS
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
abel-mqas     Ready    control-plane,master   Xm    v1.xx.x+k3s1
abel-mqasw    Ready    <none>                 Xm    v1.xx.x+k3s1
```

> **Note:** Linux lowercases hostnames automatically — `abel-mqaS` displays as
> `abel-mqas` and `abel-mqaSW` as `abel-mqasw`. This is expected behavior.

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

> All routing is handled by a **single** Ingress object in `ingress.yaml`.

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

### Single Ingress with a Catch-All Rule

All routing is handled by a single Ingress object with three rules:

- `host: app1.com` → routes to `app1-service`
- `host: app2.com` → routes to `app2-service`
- no `host` field → catch-all, routes everything else to `app3-service`

Traefik matches rules top to bottom. Named host rules take priority over the
catch-all, so `app1.com` and `app2.com` always route correctly, and any other
request falls through to app3.

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

1. Create and boot the VM (`abel-mqaS`) at `192.168.56.110`
2. Install K3s in server mode
3. Wait for the API server to be ready
4. Apply all manifests from `confs/`

### SSH into the VM

```bash
vagrant ssh abel-mqaS
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
vagrant ssh abel-mqaS -c "kubectl get nodes"
```

Expected:

```
NAME        STATUS   ROLES                  AGE   VERSION
abel-mqas   Ready    control-plane,master   Xm    v1.xx.x+k3s1
```

---

#### 2. Verify all pods are Running

```bash
vagrant ssh abel-mqaS -c "kubectl get pods -o wide"
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
vagrant ssh abel-mqaS -c "kubectl get deployment app2"
```

Expected:

```
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
app2   3/3     3            3           Xm
```

---

#### 4. Verify the Ingress is configured

```bash
vagrant ssh abel-mqaS -c "kubectl get ingress"
```

Expected:

```
NAME            CLASS     HOSTS                ADDRESS          PORTS   AGE
ingress-rules   traefik   app1.com,app2.com    192.168.56.110   80      Xm
```

> The catch-all rule (for app3) has no host field so it does not appear in the
> HOSTS column, but it is part of the same `ingress-rules` object.

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
vagrant ssh abel-mqaS -c "kubectl logs -l app=app2 --prefix=true"
```

---

### Expected Final State

| Check                         | Expected                     |
| ----------------------------- | ---------------------------- |
| `kubectl get nodes`           | 1 node `Ready`               |
| `kubectl get pods`            | 5 pods `Running` (1 + 3 + 1) |
| `kubectl get deployment app2` | `READY 3/3`                  |
| `kubectl get ingress`         | 1 ingress object             |
| `curl -H "Host: app1.com"`    | App 1 — green page           |
| `curl -H "Host: app2.com"`    | App 2 — blue page            |
| `curl` (no host)              | App 3 — orange page          |
| `curl -H "Host: anything"`    | App 3 — orange page          |

---

### Troubleshooting

**Pods stuck in `ContainerCreating`**
The nginx image is being pulled. Wait 30–60 seconds and check again:

```bash
vagrant ssh abel-mqaS -c "kubectl describe pod <pod-name>"
```

**curl returns 404**
The catch-all rule in `ingress-rules` should handle all unmatched hosts. Verify
the ingress is correctly applied:

```bash
vagrant ssh abel-mqaS -c "kubectl describe ingress ingress-rules"
```

**curl returns connection refused**
K3s or Traefik may still be starting. Wait a minute and retry. You can check:

```bash
vagrant ssh abel-mqaS -c "sudo systemctl status k3s"
vagrant ssh abel-mqaS -c "kubectl get pods -n kube-system"
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

### Overview

K3d runs K3s inside Docker containers — no VMs needed. This part sets up a K3d
cluster with Argo CD watching a public GitHub repository. Any change pushed to the
repo is automatically deployed to the cluster.

| Namespace | Contents                        |
| --------- | ------------------------------- |
| `argocd`  | Argo CD components              |
| `dev`     | Application deployed by Argo CD |

---

### Project Structure

```
p3/
├── scripts/
│   ├── install.sh       ← installs dependencies
│   └── setup.sh         ← creates cluster and deploys everything
└── confs/
    └── dev-app.yaml     ← Argo CD Application manifest
```

The application manifests live in a separate public GitHub repository:
[github.com/belmqadem/abel-mqa-iot](https://github.com/belmqadem/abel-mqa-iot)

```
abel-mqa-iot/
└── manifests/
    └── deployment.yaml  ← Deployment + Service for valarmo3/playground
```

---

### How It Works

#### GitOps Flow

```
GitHub repo (abel-mqa-iot)
        │
        │  Argo CD watches for changes (every 3 min)
        ▼
   Argo CD (argocd namespace)
        │
        │  applies manifests automatically
        ▼
   valarmo-playground pod (dev namespace)
        │
        ▼
   http://localhost:8888
```

#### K3d Cluster

The cluster is created with a single port mapping: `8888:8888@loadbalancer`. This
forwards port 8888 on your machine directly to port 8888 inside the cluster, where the
app's LoadBalancer Service listens.

#### Argo CD Application

The `dev-app.yaml` manifest tells Argo CD:

- **Where to look:** `github.com/belmqadem/abel-mqa-iot`, path `manifests/`
- **Where to deploy:** `dev` namespace
- **Sync policy:** automated with `prune` and `selfHeal` — the cluster always
  mirrors the repo, and drifted resources are corrected automatically

---

### Usage

#### Install dependencies

```bash
cd p3
./scripts/install.sh
```

#### Start the cluster and deploy everything

```bash
./scripts/setup.sh
```

This will:

1. Create a K3d cluster named `iot-cluster`
2. Create `argocd` and `dev` namespaces
3. Install Argo CD and wait for it to be ready
4. Apply `confs/dev-app.yaml` to register the app with Argo CD
5. Wait until the pod is running in `dev`

#### Tear down

```bash
k3d cluster delete iot-cluster
```

---

### Testing

#### 1. Verify the cluster is running

```bash
k3d cluster list
```

Expected:

```
NAME          SERVERS   AGENTS   LOADBALANCER
iot-cluster   1/1       0/0      true
```

---

#### 2. Verify namespaces exist

```bash
kubectl get ns
```

Expected output includes:

```
argocd   Active
dev      Active
```

---

#### 3. Verify Argo CD is running

```bash
kubectl get pods -n argocd
```

All pods should show `Running` or `Completed`.

---

#### 4. Verify the app is synced and healthy

```bash
kubectl get applications -n argocd
```

Expected:

```
NAME                 SYNC STATUS   HEALTH STATUS
valarmo-playground   Synced        Healthy
```

---

#### 5. Verify the pod is running in dev

```bash
kubectl get pods -n dev
```

Expected:

```
NAME                                  READY   STATUS    RESTARTS   AGE
valarmo-playground-xxxxxxxxxx-xxxxx   1/1     Running   0          Xm
```

---

#### 6. Verify the app is reachable

```bash
curl http://localhost:8888/
```

Expected:

```json
{ "status": "ok", "message": "v1" }
```

---

#### 7. Test GitOps — switch versions

Update the image tag in the GitHub repo:

```bash
cd abel-mqa-iot
# Switch to v2
sed -i 's/valarmo3\/playground:v1/valarmo3\/playground:v2/g' manifests/deployment.yaml
git add . && git commit -m "switch to v2" && git push

# Wait ~3 minutes for Argo CD to sync, then:
curl http://localhost:8888/
# {"status":"ok", "message": "v2"}

# Switch back to v1
sed -i 's/valarmo3\/playground:v2/valarmo3\/playground:v1/g' manifests/deployment.yaml
git add . && git commit -m "switch back to v1" && git push
```

---

### Expected Final State

| Check                                | Expected              |
| ------------------------------------ | --------------------- |
| `k3d cluster list`                   | `iot-cluster` running |
| `kubectl get ns`                     | `argocd`, `dev` exist |
| `kubectl get applications -n argocd` | `Synced` + `Healthy`  |
| `kubectl get pods -n dev`            | 1 pod `Running`       |
| `curl http://localhost:8888/`        | `{"status":"ok",...}` |

---

### Argo CD UI (optional)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get admin password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode && echo
```

Open `https://localhost:8080` — login with `admin` and the password above.

---

### Key Concepts

**K3d** — runs K3s nodes as Docker containers on your machine. Faster to spin up
than VMs, ideal for local development and CI.

**Argo CD** — a GitOps continuous delivery tool. It continuously compares the
desired state (your Git repo) with the actual state (your cluster) and syncs them.

**GitOps** — the practice of using Git as the single source of truth for
infrastructure and application configuration. No manual `kubectl apply` needed —
push to Git and the cluster updates itself.

---

### References

- [K3d docs](https://k3d.io)
- [Argo CD docs](https://argo-cd.readthedocs.io)
- [Argo CD Application CRD](https://argo-cd.readthedocs.io/en/stable/operator-manual/application.yaml)

---

## Bonus: GitLab

### Overview

This part extends Part 3 by replacing GitHub with a **self-hosted GitLab instance**
running inside the same K3d cluster. Argo CD now watches the local GitLab repo
instead of GitHub — everything stays on your machine.

| Namespace | Contents                        |
| --------- | ------------------------------- |
| `argocd`  | Argo CD components              |
| `dev`     | Application deployed by Argo CD |
| `gitlab`  | Self-hosted GitLab CE instance  |

---

### Project Structure

```
bonus/
├── scripts/
│   ├── install.sh          ← installs dependencies
│   └── setup.sh            ← creates cluster, installs GitLab + Argo CD
├── confs/
│   ├── gitlab-values.yaml  ← GitLab Helm chart configuration
│   └── dev-app.yaml        ← Argo CD Application (points to local GitLab)
└── manifests/
    └── deployment.yaml     ← app manifest (pushed to local GitLab)
```

---

### How It Works

#### GitOps Flow (with local GitLab)

```
Local GitLab (gitlab namespace, port 8181)
        │
        │  Argo CD watches via in-cluster DNS
        ▼
   Argo CD (argocd namespace)
        │
        │  applies manifests automatically
        ▼
   valarmo-playground pod (dev namespace)
        │
        ▼
   http://localhost:8888
```

#### Why In-Cluster DNS for Argo CD → GitLab

Argo CD runs inside the cluster and cannot use `localhost:8181` (that's only your
machine's port-forward). Instead it uses the Kubernetes internal service DNS name:

```
http://gitlab-webservice-default.gitlab.svc.cluster.local:8181
```

This resolves directly to the GitLab webservice pod from anywhere inside the cluster.

#### GitLab Installation

GitLab is installed via its official Helm chart with a minimal configuration:

- Community Edition (`ce`)
- No HTTPS (local dev only)
- cert-manager, nginx-ingress, prometheus, and gitlab-runner all disabled
- Resource requests reduced to fit comfortably within 16 GB RAM alongside the
  rest of the cluster

#### Setup Flow

The `setup.sh` script pauses after GitLab is ready and asks you to manually create
the project and push the manifests. This is necessary because creating a GitLab
project and generating an access token cannot be fully automated without the API,
which requires the instance to be fully initialized first.

---

### Usage

#### Install dependencies

```bash
cd bonus
./scripts/install.sh
```

#### Start everything

```bash
./scripts/setup.sh
```

The script will:

1. Create a K3d cluster named `iot-cluster-bonus`
2. Create `argocd`, `dev`, and `gitlab` namespaces
3. Install GitLab via Helm and wait for it to be ready
4. **Pause** — print the GitLab URL, credentials, and instructions to push manifests
5. Install Argo CD and wait for it to be ready
6. Register the local GitLab repo with Argo CD
7. Apply `confs/dev-app.yaml` and wait for the app to be running

#### During the pause (step 4)

Open `http://localhost:8181` in your browser, login as `root` with the printed
password, and:

1. Create a new **Public** project named `abel-mqa-iot`
2. In a new terminal, run the exact commands printed by the script:

```bash
# From the root of your Iot repository
git remote add gitlab http://root:<GITLAB_PASSWORD>@localhost:8181/root/abel-mqa-iot.git
git subtree push --prefix bonus/manifests gitlab main
```

> The script prints the exact command with the password already filled in — just copy and paste it.

3. Press ENTER in the setup terminal to continue.

#### Tear down

```bash
k3d cluster delete iot-cluster-bonus
```

---

### Testing

#### 1. Verify all three namespaces exist

```bash
kubectl get ns
```

Expected output includes:

```
argocd   Active
dev      Active
gitlab   Active
```

---

#### 2. Verify GitLab is running

```bash
kubectl get pods -n gitlab
```

All pods should show `Running` or `Completed`. Key pods to check:

```
gitlab-webservice-default-xxx   2/2   Running
gitlab-sidekiq-xxx              1/1   Running
gitlab-gitaly-0                 1/1   Running
gitlab-postgresql-0             2/2   Running
gitlab-redis-master-0           2/2   Running
```

---

#### 3. Access GitLab UI

```bash
kubectl port-forward svc/gitlab-webservice-default -n gitlab 8181:8181 &
```

Open `http://localhost:8181` — login with `root` and the password from:

```bash
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab \
  -o jsonpath='{.data.password}' | base64 --decode && echo
```

---

#### 4. Verify Argo CD is syncing from local GitLab

```bash
kubectl get applications -n argocd
```

Expected:

```
NAME                 SYNC STATUS   HEALTH STATUS
valarmo-playground   Synced        Healthy
```

---

#### 5. Verify the pod is running in dev

```bash
kubectl get pods -n dev
```

Expected:

```
NAME                                  READY   STATUS    RESTARTS   AGE
valarmo-playground-xxxxxxxxxx-xxxxx   1/1     Running   0          Xm
```

---

#### 6. Verify the app is reachable

```bash
curl http://localhost:8888/
```

Expected:

```json
{ "status": "ok", "message": "v2" }
```

---

#### 7. Test GitOps — switch versions via local GitLab

```bash
# From the root of your Iot repository

# Switch to v2
sed -i 's/valarmo3\/playground:v1/valarmo3\/playground:v2/g' bonus/manifests/deployment.yaml
git add bonus/manifests/deployment.yaml && git commit -m "v2"
git subtree push --prefix bonus/manifests gitlab main

# Wait ~3 minutes for Argo CD to auto-sync, then:
curl http://localhost:8888/
# {"status":"ok", "message": "v2"}
```

You can also watch the sync happen live in the Argo CD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Open `https://localhost:8080` — the app status will change from `Synced` to
`OutOfSync` and back to `Synced` as Argo CD picks up the change.

---

### Expected Final State

| Check                                | Expected                     |
| ------------------------------------ | ---------------------------- |
| `kubectl get ns`                     | `argocd`, `dev`, `gitlab`    |
| `kubectl get pods -n gitlab`         | All `Running` or `Completed` |
| `kubectl get pods -n argocd`         | All `Running`                |
| `kubectl get pods -n dev`            | 1 pod `Running`              |
| `kubectl get applications -n argocd` | `Synced` + `Healthy`         |
| GitLab UI at `localhost:8181`        | Accessible, repo visible     |
| `curl http://localhost:8888/`        | `{"status":"ok",...}`        |
| Push v2 to GitLab → curl             | Message changes to `v2`      |

---

### Key Concepts

**Self-hosted GitLab** — a fully featured Git platform running inside your own
infrastructure. Used here as a drop-in replacement for GitHub, keeping everything
local.

**Helm** — a package manager for Kubernetes. GitLab's official Helm chart handles
all the complexity of deploying GitLab's many components (webservice, sidekiq,
gitaly, postgresql, redis, minio, registry) as a single release.

**In-cluster DNS** — Kubernetes automatically creates DNS entries for every Service
in the format `<service>.<namespace>.svc.cluster.local`. Used here so Argo CD can
reach GitLab without going through your Mac's network.

**Root password authentication** — Argo CD authenticates to the local GitLab instance using the `root` user and its auto-generated password, retrieved from the `gitlab-gitlab-initial-root-password` Kubernetes secret. The same credentials are used when pushing manifests via `git subtree`.

---

### References

- [GitLab Helm chart docs](https://docs.gitlab.com/charts/)
- [GitLab Helm chart values](https://gitlab.com/gitlab-org/charts/gitlab)
- [Argo CD private repo docs](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/)
- [K3d docs](https://k3d.io)
