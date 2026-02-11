#!/bin/bash
# =============================================================================
# CKA Practice Environment – Container Entrypoint
# =============================================================================
# This script runs every time a container starts. It prepares the node so
# that kubeadm init / kubeadm join can succeed without errors.
#
# Run order:
#   1. Disable swap
#   2. Load required kernel modules
#   3. Apply sysctl networking parameters
#   4. Start containerd
#   5. Start kubelet (will crash-loop until kubeadm configures it – normal)
#   6. Start SSH daemon (foreground, keeps the container alive)
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# Helper: print a timestamped banner
# ---------------------------------------------------------------------------
log() {
    echo "[entrypoint] $(date '+%H:%M:%S') -- $*"
}

# ---------------------------------------------------------------------------
# 1. Disable swap
# ---------------------------------------------------------------------------
# Kubernetes requires swap to be off. Containers typically have no swap, but
# we run swapoff -a defensively to satisfy the kubeadm preflight check.
log "Disabling swap..."
swapoff -a || true
# Remove swap entries from /etc/fstab so they do not re-enable across reboots
sed -i '/\bswap\b/d' /etc/fstab 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Load kernel modules
# ---------------------------------------------------------------------------
# overlay   – required by containerd for overlayfs storage driver
# br_netfilter – required for Kubernetes network bridge traffic to be visible
#               to iptables / netfilter (needed for kube-proxy and CNI)
log "Loading kernel modules: overlay, br_netfilter..."
modprobe overlay      || log "WARNING: could not load 'overlay' module (may already be built-in)"
modprobe br_netfilter || log "WARNING: could not load 'br_netfilter' module (may already be built-in)"

# Persist module loading across reboots (in case the container has a proper init)
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

# ---------------------------------------------------------------------------
# 3. Apply sysctl networking parameters required by Kubernetes
# ---------------------------------------------------------------------------
# net.bridge.bridge-nf-call-iptables  = 1
#   Ensures bridged IPv4 traffic is routed through iptables for kube-proxy.
# net.bridge.bridge-nf-call-ip6tables = 1
#   Same as above but for IPv6.
# net.ipv4.ip_forward                 = 1
#   Allows the node to route packets between pods and external networks.
log "Applying sysctl networking parameters..."
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system 2>&1 | grep -E "(Applying|net\.(bridge|ipv4))" || true

# ---------------------------------------------------------------------------
# 4. Start containerd
# ---------------------------------------------------------------------------
# containerd must be running before kubeadm init/join can pull images and
# before kubelet can start any pods.
log "Starting containerd..."
mkdir -p /run/containerd
containerd &>/var/log/containerd.log &
CONTAINERD_PID=$!

# Wait for the containerd socket to appear (up to 30 seconds)
WAIT=0
until [ -S /run/containerd/containerd.sock ] || [ $WAIT -ge 30 ]; do
    sleep 1
    WAIT=$((WAIT + 1))
done

if [ -S /run/containerd/containerd.sock ]; then
    log "containerd is running (PID=${CONTAINERD_PID})"
else
    log "WARNING: containerd socket did not appear within 30s. kubeadm may fail."
fi

# ---------------------------------------------------------------------------
# 5. Start kubelet
# ---------------------------------------------------------------------------
# kubelet is started here so it is available when the user runs kubeadm
# init or kubeadm join. Before kubeadm runs, kubelet has no configuration
# and will crash-loop with exit code 1. This is EXPECTED behavior and does
# NOT indicate a problem. kubeadm init/join will write the kubelet config
# and the crash loop will stop.
#
# kubelet-start.sh handles flag selection and cgroup driver patching.
# The systemctl shim (installed at /usr/local/bin/systemctl) allows
# kubeadm to restart kubelet after writing its config.
log "Starting kubelet (will crash-loop until kubeadm init/join is run – this is normal)..."
/usr/local/bin/kubelet-start.sh &

log "kubelet started in background (crash-loop is normal pre-kubeadm)"

# ---------------------------------------------------------------------------
# 6. Start SSH daemon (foreground – keeps the container alive)
# ---------------------------------------------------------------------------
log "Starting SSH daemon (foreground)..."
log "============================================================"
log "Node is ready. Connect via SSH and run:"
log "  On control-plane (machine-1): sudo kubeadm init ..."
log "  On worker        (machine-2): sudo kubeadm join ..."
log "============================================================"

exec /usr/sbin/sshd -D
