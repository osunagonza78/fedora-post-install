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

set -Eeuo pipefail

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/verify.sh"
source "${SCRIPT_DIR}/../lib/runtime.sh"
require_fedora

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
    check_command_status $? "VA-API driver installation" || return 1
    
    # Enable Cisco OpenH264 repository
    log_info "Enabling Cisco OpenH264 repository..."
    sudo dnf config-manager --enable fedora-cisco-openh264 -y
    check_command_status $? "OpenH264 repository enablement" || return 1
    
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
    check_command_status $? "Multimedia codecs installation" || return 1
    
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
    check_command_status $? "NVIDIA drivers installation" || return 1
    
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
        local nvidia_version
        nvidia_version=$(modinfo -F version nvidia 2>/dev/null)
        log_info "NVIDIA kernel module is loaded (version: $nvidia_version)"
        return 0
    else
        log_warning "NVIDIA kernel module is not yet loaded. This is normal immediately after installation."
        log_warning "The kernel module will be built and loaded after reboot."
        return 1
    fi
}

# Build the NVIDIA kernel module now and wait for it, instead of telling the
# user to guess at a 5-minute wait before rebooting.
#
# akmod-nvidia builds the module asynchronously after install (an RPM scriptlet
# kicks off akmods in the background). Forcing the build synchronously and then
# polling `modinfo` means the reboot guidance reflects the real module state
# rather than a hard-coded timer.
#
# Skipped under FPI_DRY_RUN — nothing was installed, so there is nothing to
# build or poll for.
#
# @return 0 once the module is built, 1 on timeout/failure.
wait_for_nvidia_module() {
    if [[ "${FPI_DRY_RUN:-0}" = "1" ]]; then
        log_info "[dry-run] Skipping NVIDIA kernel module build wait"
        return 0
    fi

    log_info "Building the NVIDIA kernel module (this can take a few minutes)..."

    local running_kernel
    running_kernel="$(uname -r)"

    # Force a synchronous akmod build so we don't depend on the post-install
    # scriptlet's background timing. akmods is pulled in as a dependency of
    # akmod-nvidia, so it should be present by now.
    if command -v akmods &>/dev/null; then
        sudo akmods --force --kernels "$running_kernel" \
            || log_warning "akmods reported an issue — will poll for the module anyway"
    else
        log_warning "akmods not found — relying on the background post-install build"
    fi

    # Poll for the built module. 10-minute ceiling: a normal nvidia akmod
    # build is 1-3 minutes; slow disks/CPUs can push it longer.
    local deadline=$(( $(date +%s) + 600 ))
    while (( $(date +%s) < deadline )); do
        if modinfo -F version nvidia &>/dev/null; then
            log_success "NVIDIA kernel module built (version: $(modinfo -F version nvidia 2>/dev/null))"
            return 0
        fi
        sleep 15
    done

    log_warning "NVIDIA kernel module still not present after 10 minutes."
    log_warning "Inspect the build log before rebooting:  sudo journalctl -u akmods"
    return 1
}

# =============================================================================
# GPU DETECTION
# =============================================================================

# Check whether an NVIDIA GPU is present in the system.
# Uses lspci — installs pciutils if missing.
check_nvidia_gpu() {
    log_info "Checking for NVIDIA GPU..."

    if ! command -v lspci &>/dev/null; then
        log_info "Installing pciutils (provides lspci)..."
        sudo dnf -y install pciutils &>/dev/null
    fi

    # Capture lspci output once. Piping straight into `grep -q` is unsafe
    # under `set -o pipefail`: grep -q exits on the first match, lspci then
    # dies with SIGPIPE (141), and pipefail reports the pipeline as failed —
    # so detection wrongly fails exactly when an NVIDIA GPU *is* present.
    local pci_devices
    pci_devices=$(lspci 2>/dev/null) || true

    if ! grep -iq nvidia <<<"$pci_devices"; then
        log_error "No NVIDIA GPU detected (lspci found no NVIDIA device)"
        log_error "This script should only be run on systems with an NVIDIA graphics card"
        return 1
    fi

    local gpu_desc
    gpu_desc=$(grep -i -m1 nvidia <<<"$pci_devices")
    log_success "NVIDIA GPU detected: $gpu_desc"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting NVIDIA drivers and hardware acceleration setup..."

    if ! check_nvidia_gpu; then
        log_error "Aborting NVIDIA driver installation — no compatible GPU found"
        exit 1
    fi

    local failures=0

    hardware_acceleration_setup || failures=$((failures + 1))
    install_nvidia_drivers      || failures=$((failures + 1))

    # Actively build + wait for the kernel module rather than telling the user
    # to guess at a 5-minute wait. The result gates the reboot guidance below.
    local module_ready=0
    if wait_for_nvidia_module; then
        module_ready=1
    fi

    # Verification is informational only — kernel module won't be loaded
    # until reboot, so a non-zero exit here is expected and not a failure.
    verify_nvidia_installation || true

    echo
    print_section_header "POST-INSTALLATION INSTRUCTIONS"

    echo -e "${BLUE}1. Verify NVIDIA module configuration:${NO_COLOR}"
    echo -e "   ${YELLOW}modinfo -F version nvidia${NO_COLOR}"
    echo
    echo -e "${BLUE}2. Check NVIDIA driver status:${NO_COLOR}"
    echo -e "   ${YELLOW}nvidia-smi${NO_COLOR}"
    echo
    echo -e "${BLUE}3. Reboot the system:${NO_COLOR}"
    if [[ $module_ready -eq 1 ]]; then
        echo -e "   ${GREEN}The NVIDIA kernel module is built — it is safe to reboot now:${NO_COLOR}"
        echo -e "   ${YELLOW}sudo reboot${NO_COLOR}"
    else
        echo -e "   ${ORANGE}Do NOT reboot yet — the NVIDIA kernel module is not built.${NO_COLOR}"
        echo -e "   ${ORANGE}Watch the build:   sudo journalctl -u akmods -f${NO_COLOR}"
        echo -e "   ${ORANGE}When 'modinfo -F version nvidia' prints a version, reboot:${NO_COLOR}"
        echo -e "   ${YELLOW}sudo reboot${NO_COLOR}"
    fi
    echo
    echo -e "${BLUE}4. After reboot, verify installation:${NO_COLOR}"
    echo -e "   ${YELLOW}nvidia-settings${NO_COLOR}"
    echo -e "   ${YELLOW}glxinfo | grep \"OpenGL renderer\"${NO_COLOR}"
    echo

    if [[ $failures -gt 0 ]]; then
        log_error "NVIDIA setup finished with $failures failed step(s) — review the log above."
        exit 1
    fi

    log_success "Setup completed successfully! Please follow the post-installation instructions above."
}

# Execute main function
main "$@"

