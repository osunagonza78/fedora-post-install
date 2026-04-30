#!/bin/bash

###############################################################################
# Package Utilities Library for Fedora
###############################################################################
# This library provides reusable functions for package management
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
###############################################################################

# Source logging library
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/logging.sh"

###############################################################################
# Functions
###############################################################################

# Function to check if a program is installed
# Verifies if a given program is available in the system PATH
# If not installed, attempts to install it using dnf package manager
#
# @param program The name of the program to check/install
# @return 0 if the program is already installed or successfully installed
# @return 1 if the program installation fails
# @example
#   check_program_installed wget
#   check_program_installed git
check_program_installed() {
  local program=$1
  if ! command -v "$program" &> /dev/null; then
    log_error "The $program program is not installed."
    log_info "Installing $program..."
    sudo dnf install "$program" -y || { log_error "Failed to install $program."; exit 1; }
  else
    log_info "The $program program is already installed."
  fi
}

# Function to install packages from a provided list
# Installs packages from the provided array, skipping already installed ones
# Tracks installation failures and reports them
#
# @param packages_array Array of package names to install
# @return 0 if all packages are installed successfully or already present
# @return 1 if any package installation fails
install_packages() {
  local packages_array=("$@")
  if [ ${#packages_array[@]} -eq 0 ]; then
    log_error "No packages provided to install_packages function"
    return 1
  fi

  log_info "Checking ${#packages_array[@]} packages..."
  local to_install=()

  for program in "${packages_array[@]}"; do
    if ! rpm -q "$program" &>/dev/null; then
      to_install+=("$program")
    else
      log_info "Already installed: $program"
    fi
  done

  if [ ${#to_install[@]} -eq 0 ]; then
    log_success "All packages are already installed"
    return 0
  fi

  log_info "Installing ${#to_install[@]} packages: ${to_install[*]}"
  if ! sudo dnf install -y "${to_install[@]}"; then
    log_error "Package installation failed"
    return 1
  fi

  log_success "All packages installed successfully"
}
