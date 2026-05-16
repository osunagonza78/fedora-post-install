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

set -Eeuo pipefail

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/verify.sh"
source "${SCRIPT_DIR}/../lib/runtime.sh"
require_fedora
source "${SCRIPT_DIR}/../lib/package_utils.sh"

###############################################################################
# Variables
###############################################################################

changes_made=0
errors=0

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

  # Pure predicate: report whether the file is present and let the caller
  # decide what to do — see main(). Avoids a surprising exit from inside a
  # callable helper.
  if [[ ! -f "$DNF_CONF" ]]; then
    log_error "DNF configuration file not found at $DNF_CONF"
    return 1
  fi
  return 0
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
        local escaped_key
        # shellcheck disable=SC2016  # single quotes intentional: literal sed regex
        escaped_key=$(printf '%s' "$key" | sed 's/[[\.*^$()+?{|]/\\&/g')
        if ! sudo sed -i "s/^${escaped_key}=.*/${key}=${value}/" "$DNF_CONF"; then
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
    # Plain assignments (not `((x++))`): a bare arithmetic command returns 1
    # when the pre-increment value is 0, which trips `set -e` on the first
    # setting. `var=$((var + 1))` always returns 0.
    if dnf_config_update "$key" "${configs[$key]}"; then
      changes_made=$((changes_made + 1))
    else
      errors=$((errors + 1))
    fi
  done

  log_info "DNF configuration: $changes_made settings applied, $errors errors"
}

# Function to install RPM Fusion
# Skips a side individually when its release RPM is already installed — re-runs
# of System Configuration no longer reinstall the repos.
install_rpm_fusion() {
  log_info "Installing RPM Fusion..."

  local fedora_release
  fedora_release=$(rpm -E %fedora)

  if rpm -q rpmfusion-free-release &>/dev/null; then
    log_info "rpmfusion-free-release already installed — skipping"
  else
    log_info "Installing rpmfusion-free-release..."
    if ! sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm"; then
      log_error "Failed to install rpmfusion-free-release"
      return 1
    fi
  fi

  if rpm -q rpmfusion-nonfree-release &>/dev/null; then
    log_info "rpmfusion-nonfree-release already installed — skipping"
  else
    log_info "Installing rpmfusion-nonfree-release..."
    if ! sudo dnf install -y \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"; then
      log_error "Failed to install rpmfusion-nonfree-release"
      return 1
    fi
  fi
}

# Function to perform updates and upgrades
perform_updates() {
  log_info "Performing upgrade and cleanup..."
  sudo dnf group upgrade core -y
  sudo dnf -y update
}

# Function to perform optimizations
# Returns non-zero only if a critical optimisation fails. Tolerates services
# that are already disabled or not present on minimal Fedora spins.
perform_optimizations() {
  log_info "Performing optimizations..."

  if systemctl list-unit-files NetworkManager-wait-online.service &>/dev/null; then
    if ! sudo systemctl disable NetworkManager-wait-online.service; then
      log_warning "Failed to disable NetworkManager-wait-online.service"
      return 1
    fi
  else
    log_info "NetworkManager-wait-online.service not present — skipping"
  fi
}

###############################################################################
# Main script
###############################################################################

main() {
  log_info "Starting system configuration..."

  # Preflight steps that must succeed before anything else is meaningful.
  # dnf_config_exists is a pure predicate — main decides that a missing
  # dnf.conf is fatal here. check_program_installed / dnf_config_backup
  # still abort on hard failure themselves.
  check_program_installed wget
  if ! dnf_config_exists; then
    log_error "Cannot continue without $DNF_CONF — aborting."
    exit 1
  fi
  dnf_config_backup

  local failures=0
  install_rpm_fusion     || failures=$((failures + 1))
  perform_optimizations  || failures=$((failures + 1))
  perform_updates        || failures=$((failures + 1))

  if [[ $failures -gt 0 ]]; then
    log_error "System configuration finished with $failures failed step(s) — review the log above."
    exit 1
  fi

  confirm_reboot "System configuration complete. A reboot is recommended to apply all changes."
}

main "$@"

