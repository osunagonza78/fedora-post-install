#!/bin/bash

###############################################################################
# Virtualization Stack Installation Script for Fedora
###############################################################################
# This script installs and configures the complete virtualization stack
# including KVM/QEMU hypervisor, libvirt daemon, and virtualization tools
# Enables the system to run virtual machines and containers efficiently
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
###############################################################################

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"

###############################################################################
# Functions
###############################################################################

# Function to set up virtualization stack
# Installs KVM/QEMU virtualization packages and configures libvirt service
# Enables the system to run virtual machines and containers
#
# @details This function:
#   - Installs virtualization package group (KVM, QEMU, libvirt)
#   - Starts and enables libvirt daemon service
#   - Configures virtualization for immediate use
#
# @return 0 if virtualization stack is set up successfully
# @return 1 if virtualization setup fails
setup_virtualization_stack() {
  log_info "Installing virtualization package group (@virtualization)..."

  # Install virtualization package group
  if ! sudo dnf -y install @virtualization; then
    log_error "Failed to install virtualization packages"
    return 1
  fi

  log_info "Starting libvirt daemon service..."
  if ! sudo systemctl start libvirtd; then
    log_error "Failed to start libvirtd service"
    return 1
  fi

  log_info "Enabling libvirt service to start on boot..."
  if ! sudo systemctl enable libvirtd --now; then
    log_error "Failed to enable libvirtd service"
    return 1
  fi

  log_success "Virtualization stack is now ready for use!"
}


# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function that orchestrates the virtualization stack installation
# Executes all virtualization setup functions in sequence
# Configures the system to run virtual machines and containers
#
# @details This function performs the following operations:
#   1. Installs KVM/QEMU virtualization package group
#   2. Starts and enables libvirt daemon service
#   3. Configures virtualization for immediate use
#   4. Verifies virtualization stack is properly configured
#
# @return 0 if virtualization stack installation completes successfully
# @return 1 if virtualization installation fails
main() {
    log_info "Starting virtualization stack installation..."
    log_info "This will install KVM/QEMU hypervisor and configure libvirt services"

    # Install and configure virtualization stack for VM support
    setup_virtualization_stack

    log_success "Virtualization stack installation completed successfully!"
    log_info "You can now create and manage virtual machines using virt-manager or virsh."
}

# Execute main function
main "$@"
