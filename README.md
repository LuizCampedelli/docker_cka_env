# Docker CKA Practice Environment

A two-node Docker Compose environment that runs Ubuntu 22.04 containers with
Kubernetes v1.31 tooling pre-installed (containerd, kubeadm, kubelet, kubectl).
Designed for hands-on CKA (Certified Kubernetes Administrator) exam preparation.

Both containers share a bridge network and are reachable by hostname. You SSH in,
then run `kubeadm init` and `kubeadm join` yourself — just like the real exam.

## Architecture

| Container       | Hostname  | Role            | Host SSH Port |
|-----------------|-----------|-----------------|---------------|
| `cka-machine-1` | `ubuntu1` | Control-plane   | `2221`        |
| `cka-machine-2` | `ubuntu2` | Worker node     | `2222`        |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) v24+
- [Docker Compose](https://docs.docker.com/compose/install/) v2+
- macOS, Linux, or Windows with WSL2

## Quick Start

### 1. Configure credentials

```bash
cp .env.example .env
# Edit .env to set passwords if desired (defaults are fine for local practice)
```

### 2. Build and start the environment

The first build downloads and installs ~500 MB of packages. Subsequent starts
are fast because the image is cached.

```bash
docker compose up --build -d
```

### 3. Connect via SSH

```bash
# Control-plane node
ssh root@localhost -p 2221

# Worker node
ssh root@localhost -p 2222
```

Default password for `root` is whatever you set in `.env` (`ROOT_PASSWORD`).

### 4. Initialise the cluster (practice task)

**On machine-1 (control-plane):**

```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=$(hostname -I | awk '{print $1}')
```

`--pod-network-cidr=10.244.0.0/16` matches the default for Flannel CNI.
The `--apiserver-advertise-address` flag ensures the API server listens on the
container's IP, not the loopback interface.

After `kubeadm init` completes, set up kubectl access:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
```

Verify the control-plane is up:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

**Install a CNI plugin (required before pods can be scheduled):**

```bash
# Flannel (simplest option, matches the pod CIDR we passed to kubeadm)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### 5. Join the worker node (practice task)

`kubeadm init` prints a `kubeadm join` command at the end. Copy it and run it
on machine-2:

```bash
# On machine-2 – paste the full command printed by kubeadm init, e.g.:
kubeadm join 172.20.0.2:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

If you missed the join command, regenerate it on machine-1:

```bash
kubeadm token create --print-join-command
```

Verify the worker joined:

```bash
# Back on machine-1
kubectl get nodes -o wide
```

### 6. Stop the environment

```bash
# Stop containers but keep cluster state (named volumes)
docker compose down

# Stop containers AND wipe all cluster state (start fresh next time)
docker compose down -v
```

## How to Use (End-to-End)

Below is the full workflow to go from zero to a running two-node Kubernetes cluster.

```bash
# 1. Build and start both containers
docker compose up --build -d

# 2. SSH into the control-plane node (machine-1)
ssh root@localhost -p 2221

# 3. Initialize the Kubernetes cluster
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=$(hostname -I | awk '{print $1}')

# 4. Configure kubectl
export KUBECONFIG=/etc/kubernetes/admin.conf

# 5. Install Flannel CNI (required for pod networking)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 6. Verify control-plane is Ready
kubectl get nodes
kubectl get pods -n kube-system
```

Now open a second terminal and join the worker node:

```bash
# 7. SSH into the worker node (machine-2)
ssh root@localhost -p 2222

# 8. Join the cluster (paste the command printed by kubeadm init)
kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Back on machine-1, confirm both nodes are ready:

```bash
# 9. Verify the cluster
kubectl get nodes -o wide
```

To reset and start over:

```bash
# Wipe everything (volumes included) and rebuild
docker compose down -v && docker compose up -d
```

## What Is Pre-installed

| Component          | Version        | Notes                                              |
|--------------------|----------------|----------------------------------------------------|
| `containerd`       | latest stable  | Configured with `SystemdCgroup = false` (cgroupfs)  |
| `kubeadm`          | v1.31.x        | For initialising and joining nodes                  |
| `kubelet`          | v1.31.x        | Pinned via `apt-mark hold`                          |
| `kubectl`          | v1.31.x        | Bash completion pre-configured                      |
| `crictl`           | v1.31.1        | CRI debug tool; points at containerd socket         |
| `openssh-server`   | —              | SSH root login                                      |
| Networking tools   | —              | ping, ifconfig, ip, ss, netstat, iptables           |
| Debug tools        | —              | vim, jq, wget, curl, bash-completion                |

## What the Entrypoint Does at Container Start

Every time a container starts, `/entrypoint.sh` runs and:

1. Runs `swapoff -a` (kubeadm preflight requirement)
2. `modprobe overlay` and `modprobe br_netfilter` (overlayfs + bridge netfilter)
3. Sets sysctl: `net.bridge.bridge-nf-call-iptables=1`, `ip_forward=1`
4. Starts `containerd` in the background
5. Starts `kubelet` in the background (it crash-loops until kubeadm configures it — this is normal)
6. Starts `sshd` in the foreground (keeps the container alive)

## Persistent State (Named Volumes)

| Volume                     | Mounted at             | Node       |
|----------------------------|------------------------|------------|
| `k8s-machine-1-etcd`       | `/var/lib/etcd`        | machine-1  |
| `k8s-machine-1-containerd` | `/var/lib/containerd`  | machine-1  |
| `k8s-machine-2-kubelet`    | `/var/lib/kubelet`     | machine-2  |
| `k8s-machine-2-containerd` | `/var/lib/containerd`  | machine-2  |

These volumes outlive `docker compose down`. Use `docker compose down -v` to
delete them when you want a completely clean cluster.

## Troubleshooting

**kubelet is in a crash loop on startup — is that normal?**

Yes. Before `kubeadm init` or `kubeadm join` runs, kubelet has no configuration.
It exits with an error and is restarted by the entrypoint. Once kubeadm writes
`/var/lib/kubelet/config.yaml`, the crash loop stops. You can check kubelet logs:

```bash
tail -f /var/log/kubernetes/kubelet.log
```

**containerd is not running:**

```bash
tail -f /var/log/containerd.log
# Restart it manually:
containerd &
```

**kubeadm preflight fails with "br_netfilter not loaded":**

This means `/lib/modules` from the host was not bind-mounted or the module does
not exist on the host kernel. Verify the volume mount is in place:

```bash
docker inspect cka-machine-1 | grep -A5 Mounts
```

**Nodes stay in NotReady after join:**

A CNI plugin must be installed. Run the Flannel step on machine-1 (see step 4).

**I need a fresh cluster:**

```bash
# On each node, reset kubeadm state
kubeadm reset -f
# Then on host:
docker compose down -v
docker compose up -d
# Now re-run kubeadm init / join
```

## Default Credentials

| User      | Default Password | `.env` Variable      | Notes                  |
|-----------|------------------|----------------------|------------------------|
| `root`    | see `.env`       | `ROOT_PASSWORD`      | SSH root login enabled |

## Networking

| Network              | Subnet           | Purpose                        |
|----------------------|------------------|--------------------------------|
| `docker-cka-network` | `172.20.0.0/24`  | Node-to-node communication     |
| Pod network (Flannel)| `10.244.0.0/16`  | Set via `--pod-network-cidr`   |

Containers communicate by hostname: `ping ubuntu2` from ubuntu1 (and vice versa).

## Project Structure

```text
.
├── .env                  # Passwords (git-ignored)
├── .env.example          # Example env file (safe to commit)
├── Dockerfile            # Ubuntu 22.04 + K8s v1.31 image
├── entrypoint.sh         # Runtime setup (modules, sysctl, services)
├── kubelet-start.sh      # Starts kubelet with correct flags & cgroup patching
├── systemctl-shim.sh     # Fake systemctl so kubeadm can restart kubelet
├── docker-compose.yml    # Two-node cluster definition
└── README.md
```

## Security Notes

- Both containers run in `--privileged` mode. Use only on a trusted local machine.
- Passwords are in `.env` which is git-ignored. Never commit `.env`.
- Everything runs as root for practice convenience. Not for production.

## License

This project is provided as-is for educational and CKA exam practice purposes.
