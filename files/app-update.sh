#!/bin/bash
#
# Application Update Script for Raspberry Pi
# Author: Joshua D. Boyd
#
# This script handles safe application updates by:
# 1. Stopping the service
# 2. Mounting app partition as read-write
# 3. Performing the update
# 4. Remounting as read-only
# 5. Restarting the service
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_PARTITION="/opt/app"
SERVICE_NAME="app"
BACKUP_DIR="/var/backups/app"
LOG_FILE="/var/log/app-updates.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    echo -e "${RED}Error: $1${NC}" >&2

    # Attempt cleanup
    if mountpoint -q "$APP_PARTITION"; then
        log "Attempting to remount $APP_PARTITION as read-only after error"
        mount -o remount,ro "$APP_PARTITION" 2>/dev/null || true
    fi

    # Restart service if it was stopped
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Restarting service after error"
        systemctl start "$SERVICE_NAME" 2>/dev/null || true
    fi

    exit 1
}

# Check if running as root (via sudo)
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run with sudo"
fi

# Usage function
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  install <source_dir>  - Install app from source directory"
    echo "  backup               - Create backup of current app"
    echo "  restore <backup>     - Restore from backup"
    echo "  status               - Show current app status"
    echo "  mount-rw             - Mount app partition read-write"
    echo "  mount-ro             - Mount app partition read-only"
    echo ""
    echo "Examples:"
    echo "  sudo app-update install /tmp/new-app"
    echo "  sudo app-update backup"
    echo "  sudo app-update restore /var/backups/app/backup-20240101-120000"
    exit 1
}

# Create backup
create_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    log "Creating backup: $backup_name"
    mkdir -p "$BACKUP_DIR"

    if cp -r "$APP_PARTITION" "$backup_path"; then
        log "Backup created successfully: $backup_path"
        echo -e "${GREEN}Backup created: $backup_path${NC}"

        # Keep only last 5 backups
        cd "$BACKUP_DIR"
        ls -1t | tail -n +6 | xargs rm -rf 2>/dev/null || true

        echo "$backup_path"
    else
        error_exit "Failed to create backup"
    fi
}

# Install new app version
install_app() {
    local source_dir="$1"

    if [ ! -d "$source_dir" ]; then
        error_exit "Source directory does not exist: $source_dir"
    fi

    log "Starting app installation from: $source_dir"
    echo -e "${BLUE}Installing application update...${NC}"

    # Create backup first
    local backup_path=$(create_backup)

    # Stop the service
    log "Stopping $SERVICE_NAME service"
    systemctl stop "$SERVICE_NAME" || error_exit "Failed to stop service"

    # Mount as read-write
    log "Mounting $APP_PARTITION as read-write"
    mount -o remount,rw "$APP_PARTITION" || error_exit "Failed to remount as read-write"

    # Install new version
    log "Copying new application files"
    if rsync -av --exclude='.git' --exclude='__pycache__' "$source_dir/" "$APP_PARTITION/"; then
        log "Files copied successfully"

        # Set proper ownership
        chown -R pi:pi "$APP_PARTITION"
        chmod +x "$APP_PARTITION/app.py"

        # Install Python dependencies if requirements.txt exists
        if [ -f "$APP_PARTITION/requirements.txt" ]; then
            log "Creating/updating virtual environment with uv"
            cd "$APP_PARTITION"

            # Create or recreate virtual environment
            if [ -d "$APP_PARTITION/venv" ]; then
                log "Removing existing virtual environment"
                rm -rf "$APP_PARTITION/venv"
            fi

            # Create new venv with uv
            /usr/local/bin/uv venv venv || {
                log "Warning: Failed to create virtual environment with uv"
                echo -e "${YELLOW}Warning: Virtual environment creation failed${NC}"
            }

            # Install dependencies
            log "Installing Python dependencies with uv"
            /usr/local/bin/uv pip install -r requirements.txt || {
                log "Warning: Failed to install some dependencies"
                echo -e "${YELLOW}Warning: Some Python dependencies failed to install${NC}"
            }
        else
            log "No requirements.txt found, creating empty virtual environment"
            cd "$APP_PARTITION"
            /usr/local/bin/uv venv venv || {
                log "Warning: Failed to create virtual environment"
            }
        fi

        # Mount as read-only
        log "Remounting $APP_PARTITION as read-only"
        mount -o remount,ro "$APP_PARTITION" || error_exit "Failed to remount as read-only"

        # Start the service
        log "Starting $SERVICE_NAME service"
        systemctl start "$SERVICE_NAME" || error_exit "Failed to start service"

        # Wait a moment and check service status
        sleep 3
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log "Application update completed successfully"
            echo -e "${GREEN}✓ Application updated successfully!${NC}"
            echo -e "${GREEN}✓ Service is running${NC}"
            echo -e "${BLUE}Backup available at: $backup_path${NC}"
        else
            error_exit "Service failed to start after update. Check logs with: journalctl -u $SERVICE_NAME"
        fi

    else
        error_exit "Failed to copy application files"
    fi
}

# Restore from backup
restore_app() {
    local backup_path="$1"

    if [ ! -d "$backup_path" ]; then
        error_exit "Backup directory does not exist: $backup_path"
    fi

    log "Restoring from backup: $backup_path"
    echo -e "${BLUE}Restoring application from backup...${NC}"

    # Stop the service
    systemctl stop "$SERVICE_NAME" || error_exit "Failed to stop service"

    # Mount as read-write
    mount -o remount,rw "$APP_PARTITION" || error_exit "Failed to remount as read-write"

    # Clear current app and restore
    rm -rf "$APP_PARTITION"/*
    if cp -r "$backup_path"/* "$APP_PARTITION/"; then
        chown -R pi:pi "$APP_PARTITION"
        chmod +x "$APP_PARTITION/app.py"

        # Mount as read-only
        mount -o remount,ro "$APP_PARTITION" || error_exit "Failed to remount as read-only"

        # Start service
        systemctl start "$SERVICE_NAME" || error_exit "Failed to start service"

        log "Application restored successfully"
        echo -e "${GREEN}✓ Application restored successfully!${NC}"
    else
        error_exit "Failed to restore from backup"
    fi
}

# Show status
show_status() {
    echo -e "${BLUE}Application Status:${NC}"
    echo "Service Status: $(systemctl is-active $SERVICE_NAME)"
    echo "App Partition: $(mount | grep $APP_PARTITION | awk '{print $6}' | tr -d '()')"
    echo "App Directory: $APP_PARTITION"
    echo "Python Venv: $APP_PARTITION/venv"
    echo "Last Modified: $(stat -c %y $APP_PARTITION/app.py 2>/dev/null || echo 'Not found')"

    # Check virtual environment
    if [ -f "$APP_PARTITION/venv/bin/python" ]; then
        echo "Python Version: $($APP_PARTITION/venv/bin/python --version 2>/dev/null || echo 'Unknown')"
        echo "UV Available: $(command -v uv >/dev/null && echo 'Yes' || echo 'No')"
    else
        echo "Virtual Environment: Not found"
    fi

    echo ""
    echo -e "${BLUE}Available Backups:${NC}"
    ls -lt "$BACKUP_DIR" 2>/dev/null | head -6 || echo "No backups found"
    echo ""
    echo -e "${BLUE}Recent Update Log:${NC}"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "No update log found"
}

# Mount controls
mount_rw() {
    log "Mounting $APP_PARTITION as read-write (manual)"
    mount -o remount,rw "$APP_PARTITION" || error_exit "Failed to remount as read-write"
    echo -e "${YELLOW}⚠️  App partition is now READ-WRITE${NC}"
    echo -e "${YELLOW}   Remember to remount as read-only when done!${NC}"
}

mount_ro() {
    log "Mounting $APP_PARTITION as read-only (manual)"
    mount -o remount,ro "$APP_PARTITION" || error_exit "Failed to remount as read-only"
    echo -e "${GREEN}✓ App partition is now read-only${NC}"
}

# Main command processing
case "$1" in
    install)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Source directory required${NC}"
            usage
        fi
        install_app "$2"
        ;;
    backup)
        create_backup > /dev/null
        ;;
    restore)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Backup path required${NC}"
            usage
        fi
        restore_app "$2"
        ;;
    status)
        show_status
        ;;
    mount-rw)
        mount_rw
        ;;
    mount-ro)
        mount_ro
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}"
        usage
        ;;
esac
