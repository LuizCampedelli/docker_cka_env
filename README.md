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

### 1. Configure credentials

Copy the example environment file and adjust the passwords if needed:

```bash
cp .env.example .env
```

The `.env` file contains the passwords used during the image build:

```
ROOT_PASSWORD=your_root_password
DEV_USER_PASSWORD=your_dev_password
```

### 2. Build and start the environment

```bash
docker compose up --build -d
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

Credentials are defined in the `.env` file and injected at build time:

| User      | Default Password   | `.env` Variable      | Notes                  |
|-----------|--------------------|----------------------|------------------------|
| `root`    | `in .env`          | `ROOT_PASSWORD`      | SSH root login enabled |
| `devuser` | `in .env`          | `DEV_USER_PASSWORD`  | Has `sudo` privileges  |

To change a password, edit `.env` and rebuild:

```bash
docker compose up --build -d
```

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
├── .env                  # Passwords (git-ignored)
├── .env.example          # Example env file (safe to commit)
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

## Security Notes

- Passwords are stored in `.env` which is git-ignored to avoid leaking credentials.
- A `.env.example` file with placeholder values is provided for reference.
- Never use this setup in a cloud environment or on publicly accessible machines.
- If you fork this repo, make sure `.env` is not committed.

## License

This project is provided as-is for educational and practice purposes.
