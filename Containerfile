# Containerfile for BTS Raspberry Pi Base Template Builds
# Author: Joshua D. Boyd
#
# This container provides a consistent build environment for creating
# Raspberry Pi images using Packer, regardless of the host system.

FROM ubuntu:22.04

LABEL maintainer="Joshua D. Boyd"
LABEL description="Build environment for BTS Raspberry Pi Packer template"
LABEL version="1.0"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Core build tools
    curl \
    wget \
    unzip \
    xz-utils \
    rsync \
    git \
    # QEMU for ARM emulation
    qemu-user-static \
    qemu-system-arm \
    # Python and build essentials
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    # Networking and utilities
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    # Cleanup in same layer
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Packer
ARG PACKER_VERSION=1.14.1
RUN cd /tmp && \
    wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip && \
    unzip packer_${PACKER_VERSION}_linux_amd64.zip && \
    mv packer /usr/local/bin/ && \
    chmod +x /usr/local/bin/packer && \
    rm packer_${PACKER_VERSION}_linux_amd64.zip

# Install UV using official container method
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Create build user (non-root for security)
RUN useradd -m -s /bin/bash -G sudo builder && \
    echo 'builder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/builder

# Set up build environment and workspace
RUN mkdir -p /workspace/{input,output,logs} && \
    chown -R builder:builder /workspace

# Set up build environment
USER builder
WORKDIR /workspace

# Copy QEMU static binaries (needed for ARM emulation)
USER root
RUN cp /usr/bin/qemu-arm-static /usr/bin/qemu-aarch64-static /usr/local/bin/ || true
USER builder

# Verify installations
RUN packer version && \
    uv --version && \
    qemu-arm-static -version | head -1 && \
    python3 --version

# Default command
CMD ["/bin/bash"]

# Build instructions:
# podman build -t bts-rpi-builder -f Containerfile .
# docker build -t bts-rpi-builder -f Containerfile .
