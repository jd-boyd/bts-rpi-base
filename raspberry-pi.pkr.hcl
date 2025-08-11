# BTS Raspberry Pi Packer Template
# Author: Joshua D. Boyd
#
# Builds custom Raspberry Pi images with Python applications,
# systemd services, and read-only root filesystem using overlayfs.

# Variables
variable "base_image_url" {
  type        = string
  default     = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2025-05-07/2025-05-06-raspios-bookworm-arm64-lite.img.xz"
  description = "URL to the base Raspberry Pi OS image"
}

variable "image_checksum" {
  type        = string
  default     = "sha256:PLACEHOLDER_UPDATE_WITH_ACTUAL_CHECKSUM"
  description = "SHA256 checksum of the base image"
}

variable "ssh_public_key" {
  type        = string
  default     = env("SSH_PUBLIC_KEY")
  description = "SSH public key for pi user access"
}

# Packer configuration
packer {
  required_version = ">= 1.14.0"
  required_plugins {
    arm = {
      version = ">= 1.0.0"
      source  = "github.com/solo-io/arm"
    }
  }
}

# ARM builder configuration
source "arm" "raspberry_pi" {
  file_urls                = [var.base_image_url]
  file_checksum            = var.image_checksum
  file_target_extension    = "xz"
  file_unarchive_cmd       = ["xz", "-d", "$ARCHIVE_PATH"]
  image_build_method       = "resize"
  image_path               = "raspberry-pi-custom.img"
  image_size               = "4G"
  image_type               = "dos"

  image_partitions {
    name            = "boot"
    type            = "c"
    start_sector    = "8192"
    filesystem      = "vfat"
    size            = "256M"
    mountpoint      = "/boot"
  }

  image_partitions {
    name            = "root"
    type            = "83"
    start_sector    = "532480"
    filesystem      = "ext4"
    size            = "3G"
    mountpoint      = "/"
  }

  image_partitions {
    name            = "app"
    type            = "83"
    start_sector    = "6823936"
    filesystem      = "ext4"
    size            = "0"
    mountpoint      = "/opt/app"
  }

  image_chroot_env         = ["PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"]
  qemu_binary_source_path      = "/usr/bin/qemu-arm-static"
  qemu_binary_destination_path = "/usr/bin/qemu-arm-static"
}

# Build configuration
build {
  name = "raspberry-pi-custom"
  sources = ["source.arm.raspberry_pi"]

  # Install system packages and UV
  provisioner "shell" {
    inline = [
      "sleep 10",
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y python3 python3-venv systemd overlayroot curl",
      "",
      "# Install uv for fast Python package management",
      "curl -LsSf https://astral.sh/uv/install.sh | sh",
      "mv /root/.cargo/bin/uv /usr/local/bin/",
      "chmod +x /usr/local/bin/uv"
    ]
  }

  # Copy application files
  provisioner "file" {
    source      = "files/app.py"
    destination = "/opt/app/app.py"
  }

  provisioner "file" {
    source      = "files/app.service"
    destination = "/etc/systemd/system/app.service"
  }

  provisioner "file" {
    source      = "files/requirements.txt"
    destination = "/opt/app/requirements.txt"
  }

  provisioner "file" {
    source      = "files/app-update.sh"
    destination = "/usr/local/bin/app-update"
  }

  # Configure the system
  provisioner "shell" {
    inline = [
      "# Create Python virtual environment with uv",
      "cd /opt/app && /usr/local/bin/uv venv venv",
      "",
      "# Install Python dependencies using uv",
      "cd /opt/app && /usr/local/bin/uv pip install -r requirements.txt",
      "",
      "# Set up the application",
      "chmod +x /opt/app/app.py",
      "chown -R pi:pi /opt/app",
      "",
      "# Make app update script executable",
      "chmod +x /usr/local/bin/app-update",
      "",
      "# Add pi user to sudo group for app updates",
      "usermod -aG sudo pi",
      "",
      "# Create sudoers rule for app updates",
      "echo 'pi ALL=(ALL) NOPASSWD: /usr/local/bin/app-update, /bin/mount /opt/app, /bin/umount /opt/app, /bin/systemctl restart app, /bin/systemctl stop app, /bin/systemctl start app' > /etc/sudoers.d/app-updates",
      "",
      "# Generate proper fstab with actual PARTUUIDs",
      "echo '# Generating fstab with actual partition UUIDs'",
      "",
      "# Detect partition UUIDs with multiple fallback methods",
      "BOOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p1 2>/dev/null || blkid -s PARTUUID -o value $(findmnt -n -o SOURCE /boot 2>/dev/null) 2>/dev/null || echo '')",
      "ROOT_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p2 2>/dev/null || blkid -s PARTUUID -o value $(findmnt -n -o SOURCE / 2>/dev/null) 2>/dev/null || echo '')",
      "APP_PARTUUID=$(blkid -s PARTUUID -o value /dev/mmcblk0p3 2>/dev/null || blkid -s PARTUUID -o value $(findmnt -n -o SOURCE /opt/app 2>/dev/null) 2>/dev/null || echo '')",
      "",
      "# Fallback to device names if PARTUUIDs not available",
      "BOOT_MOUNT=\"PARTUUID=${BOOT_PARTUUID}\"",
      "ROOT_MOUNT=\"PARTUUID=${ROOT_PARTUUID}\"",
      "APP_MOUNT=\"PARTUUID=${APP_PARTUUID}\"",
      "",
      "if [ -z \"$BOOT_PARTUUID\" ]; then",
      "    echo 'Warning: Could not detect boot PARTUUID, using device name'",
      "    BOOT_MOUNT='/dev/mmcblk0p1'",
      "fi",
      "",
      "if [ -z \"$ROOT_PARTUUID\" ]; then",
      "    echo 'Warning: Could not detect root PARTUUID, using device name'",
      "    ROOT_MOUNT='/dev/mmcblk0p2'",
      "fi",
      "",
      "if [ -z \"$APP_PARTUUID\" ]; then",
      "    echo 'Warning: Could not detect app PARTUUID, using device name'",
      "    APP_MOUNT='/dev/mmcblk0p3'",
      "fi",
      "",
      "# Create new fstab with detected identifiers",
      "cat > /etc/fstab << EOF",
      "proc            /proc           proc    defaults          0       0",
      "${BOOT_MOUNT}  /boot           vfat    defaults          0       2",
      "${ROOT_MOUNT}  /               ext4    defaults,noatime  0       1",
      "${APP_MOUNT}   /opt/app        ext4    defaults,noatime,ro  0    2",
      "",
      "# tmpfs for logs and temporary data",
      "tmpfs           /tmp            tmpfs   defaults,noatime,mode=1777    0   0",
      "tmpfs           /var/tmp        tmpfs   defaults,noatime,mode=1777    0   0",
      "EOF",
      "",
      "echo \"Generated fstab - boot: ${BOOT_MOUNT}, root: ${ROOT_MOUNT}, app: ${APP_MOUNT}\"",
      "cat /etc/fstab",
      "",
      "# Enable the systemd service",
      "systemctl enable app.service",
      "",
      "# Configure SSH for pi user",
      "mkdir -p /home/pi/.ssh",
      "echo '${var.ssh_public_key}' > /home/pi/.ssh/authorized_keys",
      "chown -R pi:pi /home/pi/.ssh",
      "chmod 700 /home/pi/.ssh",
      "chmod 600 /home/pi/.ssh/authorized_keys",
      "",
      "# Enable SSH service",
      "systemctl enable ssh",
      "",
      "# Configure overlayfs for read-only root filesystem",
      "echo 'overlayroot=tmpfs:swap=1,recurse=0' >> /etc/overlayroot.conf",
      "",
      "# Create directories that need to be writable",
      "mkdir -p /var/log/app",
      "",
      "# Update /boot/cmdline.txt for read-only filesystem support",
      "sed -i 's/$/ fastboot noswap ro/' /boot/cmdline.txt",
      "",
      "# Clean up",
      "apt-get autoremove -y",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*"
    ]
  }

  # Compress the final image
  post-processor "compress" {
    output             = "raspberry-pi-custom-{{timestamp}}.img.gz"
    compression_level  = 6
  }
}
