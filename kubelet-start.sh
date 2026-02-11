#!/bin/bash
# =============================================================================
# kubelet-start.sh – Start kubelet with the correct flags
# =============================================================================
# This script is called by both the entrypoint (initial boot) and the
# systemctl shim (when kubeadm restarts kubelet after writing config).
#
# It reads kubeadm's output files when they exist:
#   - /var/lib/kubelet/config.yaml      (kubelet configuration)
#   - /var/lib/kubelet/kubeadm-flags.env (extra flags set by kubeadm)
#
# It also patches config.yaml to:
#   - Use cgroupfs driver (containers have no systemd)
#   - Allow swap (Docker Desktop VMs expose host swap that cannot be disabled)
#
# It always passes --bootstrap-kubeconfig and --kubeconfig, which are
# normally provided by the 10-kubeadm.conf systemd dropin that does not
# exist in this container.
# =============================================================================

KUBELET_CONFIG="/var/lib/kubelet/config.yaml"
KUBELET_FLAGS_ENV="/var/lib/kubelet/kubeadm-flags.env"
KUBELET_LOG="/var/log/kubernetes/kubelet.log"

mkdir -p /var/lib/kubelet /var/log/kubernetes

# Build the kubelet argument list
ARGS=()

# Always tell kubelet where containerd is
ARGS+=(--container-runtime-endpoint=unix:///run/containerd/containerd.sock)

# These flags replicate what the 10-kubeadm.conf systemd dropin normally
# provides. Without them, kubelet runs in standalone mode and cannot
# authenticate to the API server.
ARGS+=(--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf)
ARGS+=(--kubeconfig=/etc/kubernetes/kubelet.conf)

if [ -f "$KUBELET_CONFIG" ]; then
    # Patch cgroupDriver: systemd → cgroupfs (kubeadm defaults to systemd,
    # but our container has no systemd so containerd uses cgroupfs)
    sed -i 's/cgroupDriver: systemd/cgroupDriver: cgroupfs/' "$KUBELET_CONFIG"

    # Allow swap – Docker Desktop VMs expose a swap file at /var/lib/swap
    # that cannot be disabled from inside the container. Without this patch
    # kubelet refuses to start.
    if grep -q 'failSwapOn' "$KUBELET_CONFIG"; then
        sed -i 's/failSwapOn: true/failSwapOn: false/' "$KUBELET_CONFIG"
    else
        echo 'failSwapOn: false' >> "$KUBELET_CONFIG"
    fi

    ARGS+=(--config="$KUBELET_CONFIG")
else
    # Pre-kubeadm state: no config.yaml yet, pass minimal flags
    ARGS+=(--cgroup-driver=cgroupfs)
    ARGS+=(--fail-swap-on=false)
fi

# Source kubeadm-flags.env if it exists (sets KUBELET_KUBEADM_ARGS)
KUBELET_KUBEADM_ARGS=""
if [ -f "$KUBELET_FLAGS_ENV" ]; then
    # shellcheck disable=SC1090
    source "$KUBELET_FLAGS_ENV"
fi

# Execute kubelet (replaces this script's process when called directly,
# or runs in background when called with &)
exec kubelet "${ARGS[@]}" $KUBELET_KUBEADM_ARGS >>"$KUBELET_LOG" 2>&1
