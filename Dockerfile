FROM ubuntu:22.04

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update and install SSH server
RUN apt-get update && \
    apt-get install -y openssh-server sudo iputils-ping net-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create SSH directory
RUN mkdir /var/run/sshd

# Configure SSH to allow root login (for testing - not recommended for production)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Accept passwords as build arguments
ARG ROOT_PASSWORD
ARG DEV_USER_PASSWORD

# Set root password
RUN echo "root:${ROOT_PASSWORD}" | chpasswd

# Create a non-root user (recommended)
RUN useradd -m -s /bin/bash devuser && \
    echo "devuser:${DEV_USER_PASSWORD}" | chpasswd && \
    usermod -aG sudo devuser

# Expose SSH port
EXPOSE 22

# Start SSH service
CMD ["/usr/sbin/sshd", "-D"]