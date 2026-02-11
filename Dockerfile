# ============================================================
# CKA Practice Environment - Ubuntu 22.04 + Kubernetes v1.31
# ============================================================
# This image is intentionally privileged and is meant ONLY for
# local CKA exam practice. Do NOT run in production.
#
# What is installed:
#   - containerd (container runtime)
#   - kubeadm, kubelet, kubectl (v1.31)
#   - crictl (CRI debugging tool)
#   - OpenSSH server (for remote access via ssh)
#   - Common networking / debugging utilities
#
# What the user does manually (practice tasks):
#   - On machine-1 (control plane): kubeadm init
#   - On machine-2 (worker):        kubeadm join ...
# ============================================================

FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------------
# Stage 1 – Base system packages
# ------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # SSH access
        openssh-server \
        # Networking utilities (ping, ifconfig, netstat, ss, route)
        iputils-ping \
        net-tools \
        iproute2 \
        # Required by kubeadm / kubelet
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        # Needed to load kernel modules via modprobe
        kmod \
        # socat is required by kubeadm preflight checks
        socat \
        # conntrack is required by kubelet
        conntrack \
        # ebtables / ethtool used by kube-proxy
        ebtables \
        ethtool \
        # iptables – kubeadm and kube-proxy depend on it
        iptables \
        # ipset – used by kube-proxy in ipvs mode
        ipset \
        # Useful debugging tools for CKA practice
        vim \
        less \
        jq \
        wget \
        bash-completion \
        # nfs-common: allows mounting NFS PersistentVolumes
        nfs-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------
# Stage 2 – containerd (container runtime)
# ------------------------------------------------------------------
# Install containerd from the Docker apt repository so we get a
# maintained, up-to-date build that works well with Kubernetes.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
         https://download.docker.com/linux/ubuntu \
         $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
         > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends containerd.io && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Generate the default containerd config and patch it so that the
# systemd cgroup driver is used. This is required when kubelet also
# uses systemd cgroups (which is the default since K8s 1.22).
#
# Key change: SystemdCgroup = true inside
#   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
RUN containerd config default > /etc/containerd/config.toml
# NOTE: We keep SystemdCgroup = false (the default) because these
# containers do not run systemd. Both containerd and kubelet must
# use the same cgroup driver – cgroupfs in our case.

# ------------------------------------------------------------------
# Stage 3 – crictl (CRI CLI for debugging containerd)
# ------------------------------------------------------------------
# crictl is the recommended replacement for 'docker' when debugging
# pods running under containerd.
ARG CRICTL_VERSION=v1.31.1
RUN curl -fsSL \
        "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" \
        | tar -C /usr/local/bin -xz

# Point crictl at the containerd socket
RUN printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 10\ndebug: false\n' \
        > /etc/crictl.yaml

# ------------------------------------------------------------------
# Stage 4 – kubeadm, kubelet, kubectl v1.31
# ------------------------------------------------------------------
ARG K8S_VERSION=v1.31

RUN curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
         https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
         > /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        kubelet \
        kubeadm \
        kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Pin the Kubernetes packages so that an accidental 'apt upgrade'
# inside the container does not change the version mid-practice.
RUN apt-mark hold kubelet kubeadm kubectl

# Enable kubectl bash completion
RUN mkdir -p /etc/bash_completion.d && kubectl completion bash > /etc/bash_completion.d/kubectl

# ------------------------------------------------------------------
# Stage 5 – SSH server configuration
# ------------------------------------------------------------------
RUN mkdir -p /var/run/sshd

# Allow root login with password (practice environment only)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' \
        /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' \
        /etc/ssh/sshd_config

# ------------------------------------------------------------------
# Stage 6 – Root account
# ------------------------------------------------------------------
ARG ROOT_PASSWORD

RUN echo "root:${ROOT_PASSWORD}" | chpasswd

# Enable kubectl bash completion for root
RUN echo 'source /etc/bash_completion.d/kubectl' >> /root/.bashrc

# ------------------------------------------------------------------
# Stage 7 – Kernel module and sysctl setup (runtime entrypoint)
# ------------------------------------------------------------------
# Kernel modules (overlay, br_netfilter) cannot be loaded at image
# BUILD time because 'docker build' does not have access to the host
# kernel. They must be loaded at CONTAINER START time instead.
#
# The entrypoint script below:
#   1. Disables swap (there is usually none in a container, but we
#      make sure to satisfy kubeadm's preflight check).
#   2. Loads overlay and br_netfilter kernel modules.
#   3. Sets the sysctl parameters required by Kubernetes networking.
#   4. Starts containerd (so it is available when the user runs
#      kubeadm init / kubeadm join).
#   5. Enables and starts kubelet via systemd-compatible approach
#      (kubelet will crash-loop until kubeadm configures it, which
#      is expected and normal behavior for a practice environment).
#   6. Starts the SSH daemon so the user can connect.

# systemctl shim – translates systemctl commands into direct process
# management so that kubeadm can restart kubelet without systemd.
COPY systemctl-shim.sh /usr/local/bin/systemctl
RUN chmod +x /usr/local/bin/systemctl

# kubelet-start.sh – starts kubelet with the correct flags, reads
# kubeadm-generated config, and patches the cgroup driver.
COPY kubelet-start.sh /usr/local/bin/kubelet-start.sh
RUN chmod +x /usr/local/bin/kubelet-start.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ------------------------------------------------------------------
# Expose SSH port
# ------------------------------------------------------------------
EXPOSE 22

# ------------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------------
ENTRYPOINT ["/entrypoint.sh"]
