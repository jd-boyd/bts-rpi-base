#!/bin/bash
#
# Container Build Script for BTS Raspberry Pi Template
# Author: Joshua D. Boyd
#
# Builds Raspberry Pi images using containerized Packer environment
# Supports both Podman and Docker
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_ENGINE=""
IMAGE_NAME="bts-rpi-builder"
PROJECT_NAME="raspberry-pi-custom"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

# Detect container engine
detect_container_engine() {
    if command -v podman &> /dev/null; then
        CONTAINER_ENGINE="podman"
        echo -e "${GREEN}Using Podman${NC}"
    elif command -v docker &> /dev/null; then
        CONTAINER_ENGINE="docker"
        echo -e "${GREEN}Using Docker${NC}"
    else
        echo -e "${RED}Error: Neither Podman nor Docker found${NC}"
        echo "Please install either Podman or Docker to continue"
        echo ""
        echo "Install Podman (recommended):"
        echo "  sudo apt-get install podman"
        echo ""
        echo "Install Docker:"
        echo "  curl -fsSL https://get.docker.com | sh"
        echo "  sudo usermod -aG docker \$USER"
        exit 1
    fi
}

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build-image     Build the container image"
    echo "  build-rpi       Build Raspberry Pi image using container"
    echo "  shell          Open interactive shell in container"
    echo "  clean          Remove container image"
    echo ""
    echo "Options:"
    echo "  -e, --engine ENGINE    Force container engine (podman/docker)"
    echo "  -k, --ssh-key PATH     SSH public key path (default: ~/.ssh/id_rsa.pub)"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 build-image                    # Build container image"
    echo "  $0 build-rpi                      # Build Raspberry Pi image"
    echo "  $0 shell                          # Interactive container shell"
    echo "  $0 -e docker build-rpi            # Force Docker usage"
    exit 1
}

# Build container image
build_container_image() {
    echo -e "${BLUE}Building container image: $IMAGE_NAME${NC}"
    
    if ! $CONTAINER_ENGINE build -t "$IMAGE_NAME" -f Containerfile .; then
        echo -e "${RED}Failed to build container image${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Container image built successfully${NC}"
}

# Build Raspberry Pi image
build_rpi_image() {
    echo -e "${BLUE}Building Raspberry Pi image using container${NC}"
    
    # Check if SSH key exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${RED}Error: SSH public key not found at $SSH_KEY_PATH${NC}"
        echo "Generate one with: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
    
    # Check if container image exists
    if ! $CONTAINER_ENGINE image exists "$IMAGE_NAME"; then
        echo -e "${YELLOW}Container image not found, building it first...${NC}"
        build_container_image
    fi
    
    # Prepare SSH key content
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH")
    
    # Create output directory
    mkdir -p output
    
    # Run Packer build in container
    echo -e "${YELLOW}Starting containerized build...${NC}"
    
    # Container run arguments
    CONTAINER_ARGS=(
        "run"
        "--rm"
        "-it"
        "--privileged"
        "-v" "$(pwd):/workspace"
        "-v" "$(pwd)/output:/workspace/output"
        "-e" "SSH_PUBLIC_KEY=$SSH_PUBLIC_KEY"
        "-e" "PACKER_LOG=1"
        "-w" "/workspace"
        "$IMAGE_NAME"
    )
    
    # Add Docker-specific arguments
    if [ "$CONTAINER_ENGINE" = "docker" ]; then
        CONTAINER_ARGS+=("--security-opt" "apparmor:unconfined")
    fi
    
    # Run the build
    if $CONTAINER_ENGINE "${CONTAINER_ARGS[@]}" packer build raspberry-pi.json; then
        echo -e "${GREEN}Raspberry Pi image built successfully!${NC}"
        echo -e "${GREEN}Output files:${NC}"
        ls -la *.img.gz 2>/dev/null || echo "No compressed images found"
        ls -la output/ 2>/dev/null || echo "No output directory files"
    else
        echo -e "${RED}Build failed${NC}"
        echo -e "${YELLOW}Check logs at: packer.log${NC}"
        exit 1
    fi
}

# Open interactive shell
open_shell() {
    echo -e "${BLUE}Opening interactive shell in container${NC}"
    
    # Check if container image exists
    if ! $CONTAINER_ENGINE image exists "$IMAGE_NAME"; then
        echo -e "${YELLOW}Container image not found, building it first...${NC}"
        build_container_image
    fi
    
    # SSH key setup
    SSH_PUBLIC_KEY=""
    if [ -f "$SSH_KEY_PATH" ]; then
        SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH")
    fi
    
    # Container run arguments
    CONTAINER_ARGS=(
        "run"
        "--rm"
        "-it"
        "--privileged"
        "-v" "$(pwd):/workspace"
        "-v" "$(pwd)/output:/workspace/output"
        "-e" "SSH_PUBLIC_KEY=$SSH_PUBLIC_KEY"
        "-e" "PACKER_LOG=1"
        "-w" "/workspace"
        "$IMAGE_NAME"
        "/bin/bash"
    )
    
    # Add Docker-specific arguments
    if [ "$CONTAINER_ENGINE" = "docker" ]; then
        CONTAINER_ARGS+=("--security-opt" "apparmor:unconfined")
    fi
    
    $CONTAINER_ENGINE "${CONTAINER_ARGS[@]}"
}

# Clean up container image
clean_image() {
    echo -e "${BLUE}Removing container image: $IMAGE_NAME${NC}"
    
    if $CONTAINER_ENGINE image exists "$IMAGE_NAME"; then
        $CONTAINER_ENGINE rmi "$IMAGE_NAME"
        echo -e "${GREEN}Container image removed${NC}"
    else
        echo -e "${YELLOW}Container image not found${NC}"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--engine)
            CONTAINER_ENGINE="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        build-image)
            COMMAND="build-image"
            shift
            ;;
        build-rpi)
            COMMAND="build-rpi"
            shift
            ;;
        shell)
            COMMAND="shell"
            shift
            ;;
        clean)
            COMMAND="clean"
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

echo -e "${GREEN}BTS Raspberry Pi Container Builder${NC}"
echo -e "${GREEN}Author: Joshua D. Boyd${NC}"

# Detect container engine if not specified
if [ -z "$CONTAINER_ENGINE" ]; then
    detect_container_engine
elif [ "$CONTAINER_ENGINE" != "podman" ] && [ "$CONTAINER_ENGINE" != "docker" ]; then
    echo -e "${RED}Error: Invalid container engine '$CONTAINER_ENGINE'${NC}"
    echo "Supported engines: podman, docker"
    exit 1
fi

echo -e "${BLUE}Container Engine: $CONTAINER_ENGINE${NC}"

# Verify container engine is available
if ! command -v "$CONTAINER_ENGINE" &> /dev/null; then
    echo -e "${RED}Error: $CONTAINER_ENGINE not found${NC}"
    if [ "$CONTAINER_ENGINE" = "podman" ]; then
        echo "Install with: sudo apt-get install podman"
    else
        echo "Install with: curl -fsSL https://get.docker.com | sh"
    fi
    exit 1
fi

echo ""

# Execute command
case "${COMMAND:-}" in
    build-image)
        build_container_image
        ;;
    build-rpi)
        build_rpi_image
        ;;
    shell)
        open_shell
        ;;
    clean)
        clean_image
        ;;
    *)
        echo -e "${YELLOW}No command specified. Use --help for usage information.${NC}"
        echo ""
        echo "Quick start:"
        echo "  $0 build-image     # Build container"
        echo "  $0 build-rpi       # Build Raspberry Pi image"
        ;;
esac
