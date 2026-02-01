#!/bin/bash

# =============================================================================
# Secure Boot Configuration Script for Fedora
# =============================================================================
# This script configures Secure Boot on Fedora systems by installing required
# packages, generating Machine Owner Keys (MOK), and setting up the necessary
# certificates for kernel module signing.
#
# Secure Boot ensures that all kernel modules loaded are properly signed and
# trusted, providing additional security against malicious kernel modifications.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
# =============================================================================

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"

# =============================================================================
# SECURE BOOT FUNCTIONS
# =============================================================================

# Enables secure boot on the system
# 
# This function will:
# 1. Install required packages for secure boot (kmodtool, akmods, mokutil, openssl)
# 2. Generate a Certificate Authority key for kernel module signing
# 3. Import the generated key into the Machine Owner Key database
# 4. Prompt user for reboot to complete the secure boot enrollment process
#
# Note: After running this script, you will need to reboot and manually enroll
# the MOK in the BIOS/UEFI firmware interface when prompted during boot.
enable_secure_boot() {
	log_info "Enabling Secure Boot..."
	
	# Install required packages
	log_info "Installing required packages for Secure Boot..."
	sudo dnf install -y kmodtool akmods mokutil openssl
	check_command_status "Required packages installation" || return 1
	
	# Generate a CA key
	log_info "Generating Certificate Authority key for kernel module signing..."
	sudo kmodgenca -a
	check_command_status "CA key generation" || return 1
	
	# Copy the key to the certs folder and import into MOK database
	log_info "Importing generated CA key into Machine Owner Key database..."
	sudo mokutil --import /etc/pki/akmods/certs/public_key.der
	check_command_status "MOK import" || return 1
	
	log_success "Secure Boot configuration completed successfully"
}

# =============================================================================
# POST-INSTALLATION INSTRUCTIONS
# =============================================================================

# Display post-installation instructions for secure boot
display_secure_boot_instructions() {
	echo
	print_section_header "SECURE BOOT ENROLLMENT INSTRUCTIONS"
	
	echo -e "${BLUE}1. REBOOT REQUIRED:${NO_COLOR}"
	echo -e "   ${YELLOW}The system must be rebooted to complete Secure Boot enrollment${NO_COLOR}"
	echo
	echo -e "${BLUE}2. ENROLL MOK IN BIOS/UEFI:${NO_COLOR}"
	echo -e "   ${YELLOW}During boot, you will see a blue screen prompting to enroll the MOK${NO_COLOR}"
	echo -e "   ${YELLOW}Select 'Enroll MOK' and press Enter${NO_COLOR}"
	echo -e "   ${YELLOW}Select 'Continue' when prompted about the key${NO_COLOR}"
	echo -e "   ${YELLOW}Enter the password you set during the MOK import process${NO_COLOR}"
	echo
	echo -e "${BLUE}3. VERIFY SECURE BOOT STATUS:${NO_COLOR}"
	echo -e "   ${YELLOW}After reboot, verify Secure Boot status with:${NO_COLOR}"
	echo -e "   ${YELLOW}mokutil --sb-state${NO_COLOR}"
	echo
	echo -e "${BLUE}4. VERIFY NVIDIA DRIVERS:${NO_COLOR}"
	echo -e "   ${YELLOW}If using NVIDIA drivers, verify they load correctly:${NO_COLOR}"
	echo -e "   ${YELLOW}modinfo -F version nvidia${NO_COLOR}"
	echo
	echo -e "${ORANGE}IMPORTANT:${NO_COLOR}"
	echo -e "${ORANGE}- The MOK enrollment is a one-time process${NO_COLOR}"
	echo -e "${ORANGE}- You will need the password set during MOK import${NO_COLOR}"
	echo -e "${ORANGE}- If you forget the password, you may need to repeat this process${NO_COLOR}"
	echo
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
	log_info "Starting Secure Boot configuration..."
	
	# Enable Secure Boot
	enable_secure_boot
	local secure_boot_status=$?
	
	# Display post-installation instructions
	display_secure_boot_instructions
	
	# Report overall status
	if [ $secure_boot_status -eq 0 ]; then
		log_success "Secure Boot configuration completed successfully!"
		log_info "Please follow the enrollment instructions above after reboot."
	else
		log_error "Secure Boot configuration encountered errors."
		log_error "Please check the messages above and resolve any issues."
		exit 1
	fi
	
	# Sleep before rebooting
	log_info "Sleeping 5 seconds before system restart..."
	sleep 5
	
	# Reboot to complete the process
	log_info "Rebooting system to complete Secure Boot enrollment..."
	reboot
}

# Execute main function
main "$@"

