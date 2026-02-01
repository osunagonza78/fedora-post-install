#!/bin/bash

# =============================================================================
# NVIDIA Drivers and Hardware Acceleration Setup Script for Fedora
# =============================================================================
# This script installs NVIDIA drivers and configures hardware acceleration
# for video playback and GPU computing on Fedora Linux.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
# =============================================================================

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"

###############################################################################
# Functions
###############################################################################

# =============================================================================
# HARDWARE ACCELERATION SETUP
# =============================================================================

# Setup hardware acceleration for video playback
# Installs VA-API drivers, VDPAU utilities, and multimedia codecs
hardware_acceleration_setup() {
    log_info "Setting up hardware acceleration for video playback..."
    
    # Install NVIDIA VA-API driver and utilities
    log_info "Installing NVIDIA driver and video acceleration utilities..."
    sudo dnf install -y libva-utils vdpauinfo
    check_command_status "VA-API driver installation" || return 1
    
    # Enable Cisco OpenH264 repository
    log_info "Enabling Cisco OpenH264 repository..."
    sudo dnf config-manager --enable fedora-cisco-openh264 -y
    check_command_status "OpenH264 repository enablement" || return 1
    
    # Install multimedia codecs and players
    log_info "Installing multimedia codecs and video players..."
    sudo dnf install -y \
        openh264 \
        mozilla-openh264 \
        libavcodec-freeworld \
        ffmpeg \
        mpv \
        vlc \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly
    check_command_status "Multimedia codecs installation" || return 1
    
    log_info "Hardware acceleration setup completed successfully"
    return 0
}

# =============================================================================
# NVIDIA DRIVERS INSTALLATION
# =============================================================================

# Install NVIDIA proprietary drivers and CUDA support
# Uses akmod for automatic kernel module rebuilding
install_nvidia_drivers() {
    log_info "Installing NVIDIA proprietary drivers and CUDA support..."
    
    # Install NVIDIA drivers using akmod for automatic kernel module rebuilding
    # akmod-nvidia: Automatically rebuilds NVIDIA kernel modules when kernel updates
    # xorg-x11-drv-nvidia-cuda: NVIDIA driver with CUDA support
    log_info "Installing NVIDIA drivers with akmod for automatic kernel module rebuilding..."
    sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
    check_command_status "NVIDIA drivers installation" || return 1
    
    log_info "NVIDIA drivers installation completed successfully"
    return 0
}

# =============================================================================
# VERIFICATION AND POST-INSTALLATION STEPS
# =============================================================================

# Verify NVIDIA kernel module installation
verify_nvidia_installation() {
    log_info "Verifying NVIDIA kernel module installation..."
    
    # Check if NVIDIA kernel module is loaded
    if modinfo -F version nvidia >/dev/null 2>&1; then
        local nvidia_version=$(modinfo -F version nvidia 2>/dev/null)
        log_info "NVIDIA kernel module is loaded (version: $nvidia_version)"
        return 0
    else
        log_warning "NVIDIA kernel module is not yet loaded. This is normal immediately after installation."
        log_warning "The kernel module will be built and loaded after reboot."
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting NVIDIA drivers and hardware acceleration setup..."
    
    # Perform hardware acceleration setup
    hardware_acceleration_setup
    local hw_accel_status=$?
    
    # Install NVIDIA drivers
    install_nvidia_drivers
    local nvidia_status=$?
    
    # Verify installation
    verify_nvidia_installation
    
    # Display post-installation instructions
    echo
    print_section_header "POST-INSTALLATION INSTRUCTIONS"
    
    echo -e "${BLUE}1. Verify NVIDIA module configuration:${NO_COLOR}"
    echo -e "   ${YELLOW}modinfo -F version nvidia${NO_COLOR}"
    echo
    echo -e "${BLUE}2. Check NVIDIA driver status:${NO_COLOR}"
    echo -e "   ${YELLOW}nvidia-smi${NO_COLOR}"
    echo
    echo -e "${BLUE}3. Reboot the system:${NO_COLOR}"
    echo -e "   ${YELLOW}sudo reboot${NO_COLOR}"
    echo -e "   ${ORANGE}Note: Wait at least 5 minutes after installation before rebooting${NO_COLOR}"
    echo -e "   ${ORANGE}      to allow the kernel module to be built properly.${NO_COLOR}"
    echo
    echo -e "${BLUE}4. After reboot, verify installation:${NO_COLOR}"
    echo -e "   ${YELLOW}nvidia-settings${NO_COLOR}"
    echo -e "   ${YELLOW}glxinfo | grep \"OpenGL renderer\"${NO_COLOR}"
    echo
    
    # Report overall status
    if [ $hw_accel_status -eq 0 ] && [ $nvidia_status -eq 0 ]; then
        log_info "Setup completed successfully! Please follow the post-installation instructions above."
        exit 0
    else
        log_error "Setup encountered errors. Please check the messages above and resolve any issues."
        exit 1
    fi
}

# Execute main function
main "$@"

