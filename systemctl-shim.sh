#!/bin/bash
# =============================================================================
# systemctl shim for Docker containers (no systemd)
# =============================================================================
# kubeadm expects systemctl to manage kubelet. This shim translates
# systemctl commands into direct process management so kubeadm init/join
# works inside a container that has no real init system.
#
# Installed at /usr/local/bin/systemctl (before /bin in PATH).
# =============================================================================

ACTION="$1"
UNIT="$2"

# Strip ".service" suffix if present (e.g. "kubelet.service" → "kubelet")
UNIT="${UNIT%.service}"

case "$ACTION" in
    # --- No-ops: kubeadm calls these but they have no meaning without systemd ---
    daemon-reload|enable|disable)
        exit 0
        ;;

    start|restart)
        if [ "$UNIT" = "kubelet" ]; then
            # Kill any existing kubelet process
            pkill -x kubelet 2>/dev/null || true
            sleep 0.5
            # Start kubelet via the wrapper script
            /usr/local/bin/kubelet-start.sh &
            exit 0
        fi
        ;;

    stop)
        if [ "$UNIT" = "kubelet" ]; then
            pkill -x kubelet 2>/dev/null || true
            exit 0
        fi
        ;;

    status)
        if [ "$UNIT" = "kubelet" ]; then
            if pgrep -x kubelet >/dev/null 2>&1; then
                echo "kubelet is running (PID $(pgrep -x kubelet | head -1))"
                exit 0
            else
                echo "kubelet is not running"
                exit 3
            fi
        fi
        ;;

    is-active)
        if [ "$UNIT" = "kubelet" ]; then
            if pgrep -x kubelet >/dev/null 2>&1; then
                echo "active"
                exit 0
            else
                echo "inactive"
                exit 3
            fi
        fi
        ;;

    *)
        echo "systemctl shim: unsupported action '$ACTION' for unit '$UNIT'" >&2
        exit 1
        ;;
esac

# If we reach here, the unit is not kubelet — just no-op
exit 0
