#!/bin/bash

###############################################################################
# System Configuration Script for Fedora
###############################################################################
# This script configures system settings, installs repositories, and performs
# system optimizations for Fedora Linux.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
###############################################################################

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/package_utils.sh"

###############################################################################
# Constants
###############################################################################

# DNF configuration file path
DNF_CONF="/etc/dnf/dnf.conf"
BACKUP_FILE="$DNF_CONF.backup"

# Array of configurations to add/update
declare -A configs=(
    ["fastestmirror"]="True"
    ["max_parallel_downloads"]="10"
    ["defaultyes"]="True"
    ["keepcache"]="True"
    ["deltarpm"]="True"
)

###############################################################################
# Functions
###############################################################################

# Function to check if the DNF configuration file exists
# @return 0 if the configuration file exists, 1 if it doesn't
dnf_config_exists() {
  log_info "Checking if DNF configuration file exists..."

  # Check if the DNF configuration file is present at the specified location
  if [[ ! -f "$DNF_CONF" ]]; then
    # If the file does not exist, print an error message and exit with a non-zero status code
    log_error "DNF configuration file not found at $DNF_CONF"
    exit 1
  fi
}

# Function to add or update configuration
# @param key The key of the configuration to add or update
# @param value The value of the configuration to add or update
dnf_config_update() {
    local key=$1
    local value=$2

    # Check if setting already exists with the same value
    if grep -q "^${key}=${value}$" "$DNF_CONF"; then
        log_info "Setting ${key}=${value} already exists"
        return 0
    fi

    if grep -q "^${key}=" "$DNF_CONF"; then
        # Update existing setting
        log_info "Updating existing setting: ${key}=${value}"
        if ! sudo sed -i "s/^${key}=.*/${key}=${value}/" "$DNF_CONF"; then
            log_error "Failed to update setting: ${key}"
            return 1
        fi
    else
        # Add new setting
        log_info "Adding new setting: ${key}=${value}"
        if ! echo "${key}=${value}" | sudo tee -a "$DNF_CONF" > /dev/null; then
            log_error "Failed to add setting: ${key}"
            return 1
        fi
    fi
}

# Function to create a backup of the original DNF configuration file
# @return 0 if the backup file is created successfully, 1 if it isn't
dnf_config_backup() {
  # Create backup only if it doesn't exist
  if [[ ! -f "$BACKUP_FILE" ]]; then
    log_info "Creating backup of original DNF configuration..."
    if ! sudo cp "$DNF_CONF" "$BACKUP_FILE"; then
        log_error "Failed to create backup file"
        exit 1
    fi
    log_info "Backup created at $BACKUP_FILE"
  else
    log_info "Backup file already exists at $BACKUP_FILE"
  fi

  log_info "Starting DNF configuration optimization..."

  # Add/Update DNF optimizations
  for key in "${!configs[@]}"; do
    dnf_config_update "$key" "${configs[$key]}" && ((changes_made++)) || ((errors++))
  done
}

# Function to install RPM Fusion
install_rpm_fusion() {
  log_info "Installing RPM Fusion..."

  # Get the free repository (most stuff you need)
  sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm

  # Get the nonfree repository (NVIDIA drivers, some codecs)
  sudo dnf install -y \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
}

# Function to perform updates and upgrades
perform_updates() {
  log_info "Performing upgrade and cleanup..."
  sleep 1
  sudo dnf group upgrade core -y
  sudo dnf4 group install core -y
  sudo dnf -y update
}

# Function to perform optimizations
perform_optimizations() {
  log_info "Performing optimizations..."

  sudo systemctl disable NetworkManager-wait-online.service
}

###############################################################################
# Main script
###############################################################################

# Check if wget is installed
check_program_installed wget

# Check if the DNF config file exists
dnf_config_exists

# Perform a DNF config file backup and update DNF config file
dnf_config_backup

# Install RPM Fusion
install_rpm_fusion

# Perform optimizations
perform_optimizations

# Perform updates
perform_updates

# Summary of changes
log_info "Sleeping 5 seconds before restart system."
sleep 5

# Reboot
reboot

