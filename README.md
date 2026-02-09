# Docker CKA Practice Environment

A lightweight Docker Compose environment that spins up multiple Ubuntu SSH-accessible containers on a shared bridge network. Designed for practicing Linux administration, networking, and CKA (Certified Kubernetes Administrator) exam preparation tasks.

## Architecture

| Container        | Hostname  | Host SSH Port | Internal IP (bridge) |
|------------------|-----------|---------------|----------------------|
| `cka-machine-1`  | `ubuntu1` | `2221`        | auto-assigned        |
| `cka-machine-2`  | `ubuntu2` | `2222`        | auto-assigned        |

Both containers run Ubuntu 22.04 with an OpenSSH server and are connected via the `docker-cka-network` bridge network, allowing inter-container communication by hostname.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20+ recommended)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2+)

## Quick Start

### 1. Build the SSH-enabled image

```bash
docker build -t ubuntu-ssh:22.04 .
```

### 2. Start the environment

```bash
docker compose up -d
```

### 3. Connect via SSH

```bash
# Machine 1
ssh devuser@localhost -p 2221

# Machine 2
ssh devuser@localhost -p 2222
```

### 4. Stop the environment

```bash
docker compose down
```

## Default Credentials

| User      | Password       | Notes                       |
|-----------|----------------|-----------------------------|
| `root`    | `password123`  | SSH root login enabled      |
| `devuser` | `devpass123`   | Has `sudo` privileges       |

> **Warning:** These credentials are for local practice only. Do not use this configuration in production or on publicly accessible machines.

## Networking

The containers share a Docker bridge network (`docker-cka-network`) and can reach each other by hostname:

```bash
# From ubuntu1, ping ubuntu2
ping ubuntu2

# From ubuntu2, ping ubuntu1
ping ubuntu1
```

Installed network utilities: `iputils-ping`, `net-tools`.

## Installed Packages

- `openssh-server` -- SSH daemon
- `sudo` -- privilege escalation
- `iputils-ping` -- `ping` command
- `net-tools` -- `ifconfig`, `netstat`, etc.

## Project Structure

```
.
├── Dockerfile            # Ubuntu 22.04 image with SSH server
├── docker-compose.yml    # Two-node environment definition
└── README.md
```

## Customization

**Add more nodes** -- duplicate a service block in `docker-compose.yml` with a unique container name, hostname, and host port:

```yaml
cka-ubuntu-machine-3:
  image: ubuntu-ssh:22.04
  container_name: cka-machine-3
  hostname: ubuntu3
  networks:
    - docker-cka-network
  ports:
    - "2223:22"
  stdin_open: true
  tty: true
```

**Install additional tools** -- add packages to the `apt-get install` line in the `Dockerfile`, then rebuild the image.

## Warning

This project has passwords hardcoded, never use in a cloud environement, it's use is restricted for local environements. If you fork it, and push to your own github account, an warning will be produced to advise you about this proposital flaw.

## License

This project is provided as-is for educational and practice purposes.
