#!/bin/bash

###############################################################################
# Packages Installation Script for Fedora
###############################################################################
# This script installs essential packages, multimedia codecs, etc.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
###############################################################################

# Source logging and package utilities libraries
SCRIPT_DIR="$(dirname "$0")"

source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/package_utils.sh"


# Global variables
PROGRAMS_TO_INSTALL_DNF=(
  p7zip
  p7zip-plugins
  unrar
  bzip2
  unzip
  tar
  make
  gcc
  ntfs-3g
  btop
  tmux
  vim
  firewall-config
  git
  curl
  wget
  steam
  steam-devices
  fastfetch
  vlc
  gimp
  fuse
  deja-dup
  dnf-plugins-core
  rocminfo
  rocm-opencl
  rocm-clinfo
  rocm-hip
  gparted
  libxcrypt-compat
  libfreeaptx
  libldac
  fdk-aac
  kate
)

###############################################################################
# Functions
###############################################################################

# Function to perform system firmware updates
# Updates system firmware using the Linux Vendor Firmware Service (LVFS)
# This function ensures that hardware components have the latest firmware
# for improved security, performance, and compatibility
#
# @see https://fwupd.org/
# @see https://wiki.archlinux.org/title/Firmware#Updating_firmware
# @return 0 if firmware updates complete successfully
# @return 1 if critical firmware update operations fail
update_system_firmware() {
  log_info "Performing firmware updates..."

  # Refresh the firmware database
  if ! sudo fwupdmgr refresh --force; then
    log_error "Failed to refresh firmware database"
    return 1
  fi

  # Display available devices
  if ! sudo fwupdmgr get-devices; then
    log_warning "Could not get device list"
  fi

  # Check for available updates
  if ! sudo fwupdmgr get-updates; then
    log_warning "Could not check for updates"
  fi

  # Apply available firmware updates
  if ! sudo fwupdmgr update; then
    log_error "Failed to apply firmware updates"
    return 1
  fi
  
  log_success "Firmware updates completed"
}

# Function to configure Flatpak support
# Sets up Flatpak sandboxed application framework with Flathub repository
# Enables theme integration and updates the application metadata
#
# @return 0 if Flatpak setup completes successfully
# @return 1 if critical Flatpak configuration fails
setup_flatpak_environment() {
  log_info "Performing flatpak setup..."

  # Add Flathub repository if not already present
  if ! flatpak remote-list | grep -q "flathub"; then
    log_info "Installing Flathub repository..."
    if ! flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
      log_error "Failed to add Flathub repository"
      return 1
    fi
  else
    log_info "Flathub repository is already added."
  fi

  # Enable filesystem access for user themes in Flatpak apps
  if ! sudo flatpak override --filesystem=~/.themes; then
    log_warning "Failed to set flatpak theme override"
  fi

  # Update Flatpak application metadata
  if ! flatpak update --appstream; then
    log_warning "Failed to update flatpak appstream"
  fi
  
  log_success "Flatpak setup completed"
}

# Function to install multimedia codecs and support
# Installs comprehensive multimedia support including codecs, GStreamer plugins,
# and replaces the limited ffmpeg-free with the full ffmpeg package
#
# @details This function:
#   - Installs multimedia package group for broad codec support
#   - Replaces ffmpeg-free with full ffmpeg for complete format support
#   - Installs all GStreamer plugins for media playback
#   - Installs sound and video package groups
#
# @return 0 if multimedia codecs installation completes successfully
# @return 1 if critical multimedia package installation fails
install_multimedia_codecs() {
  log_info "Performing media codecs setup..."

  # Install multimedia package group
  if ! sudo dnf group install -y multimedia; then
    log_error "Failed to install multimedia group"
    return 1
  fi

  # Replace ffmpeg-free with full ffmpeg package
  if ! sudo dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing; then
    log_error "Failed to swap ffmpeg packages"
    return 1
  fi

  # Install comprehensive GStreamer plugins
  if ! sudo dnf upgrade -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin; then
    log_warning "Failed to upgrade multimedia packages"
  fi

  # Install sound and video package groups
  if ! sudo dnf group install -y sound-and-video; then
    log_error "Failed to install sound and video group"
    return 1
  fi
  
  log_success "Multimedia codecs installation completed"
}


# Function to configure Firefox video codecs
# Installs Cisco OpenH264 codecs for Firefox video playback
# Enables the Cisco OpenH264 repository for future updates
#
# @details This function:
#   - Installs OpenH264 GStreamer plugin for Firefox
#   - Installs Mozilla OpenH264 for WebRTC support
#   - Enables the Cisco OpenH264 repository
#
# @return 0 if Firefox codecs are configured successfully
# @return 1 if critical codec installation fails
configure_firefox_codecs() {
  log_info "Performing Firefox video setup..."

  # Install Cisco OpenH264 codecs (free but with special licensing)
  if ! sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264; then
    log_error "Failed to install Cisco codecs"
    return 1
  fi

  # Enable the Cisco OpenH264 repository for updates
  if ! sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1; then
    log_warning "Failed to enable Cisco repository"
  fi
  
  log_success "Firefox codecs configured"
}

# Function to install Microsoft TrueType fonts
# Downloads and installs Microsoft Core Fonts for better web compatibility
# Includes fonts like Arial, Times New Roman, and Verdana
#
# @details This function:
#   - Installs font dependencies (curl, cabextract, font utilities)
#   - Downloads Microsoft Core Fonts installer from SourceForge
#   - Updates system font cache
#
# @return 0 if Microsoft fonts are installed successfully
# @return 1 if font installation fails
install_microsoft_fonts() {
  log_info "Performing fonts setup..."

  # Install font management dependencies
  if ! sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig; then
    log_error "Failed to install font dependencies"
    return 1
  fi

  # Install Microsoft Core Fonts package
  if ! sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm; then
    log_error "Failed to install Microsoft fonts"
    return 1
  fi

  # Update system font cache to recognize new fonts
  if ! sudo fc-cache -fv; then
    log_warning "Failed to update font cache"
  fi
  
  log_success "Microsoft fonts installed"
}

# Function to install Brave Browser
# Adds Brave Browser repository and installs the privacy-focused web browser
# Brave is based on Chromium with built-in ad and tracker blocking
#
# @return 0 if Brave Browser is installed successfully
# @return 1 if Brave Browser installation fails
install_brave_browser() {
  log_info "Performing brave browser installation..."
  
  # Install required DNF plugins for repository management
  if ! sudo dnf install dnf-plugins-core; then
    log_error "Failed to install dnf-plugins-core"
    return 1
  fi
  
  # Add Brave Browser official repository
  if ! sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo; then
    log_error "Failed to add Brave repository"
    return 1
  fi

  # Install Brave Browser package
  if ! sudo dnf install -y brave-browser; then
    log_error "Failed to install Brave browser"
    return 1
  fi
  
  log_success "Brave browser installed"
}

# Function to install Wine compatibility layer
# Adds WineHQ repository and installs Wine for running Windows applications
# Wine provides a compatibility layer for Windows programs on Linux
#
# @return 0 if Wine is installed successfully
# @return 1 if Wine installation fails
install_wine() {
  log_info "Performing wine installation..."

  # Add WineHQ official repository for Fedora
  if ! sudo dnf config-manager addrepo --from-repofile=https://dl.winehq.org/wine-builds/fedora/43/winehq.repo; then
    log_error "Failed to add Wine repository"
    return 1
  fi

  # Install Wine stable release
  if ! sudo dnf install -y winehq-stable; then
    log_error "Failed to install Wine"
    return 1
  fi
  
  log_success "Wine installed"
}

# Function to set up Oh My Posh shell prompt
# Installs Oh My Posh cross-platform prompt engine with themes and fonts
# Configures a modern, customizable shell prompt with Git integration
#
# @details This function:
#   - Downloads and installs Oh My Posh binary to /usr/local/bin
#   - Downloads and installs FiraCode Nerd Font for prompt rendering
#   - Downloads and installs Oh My Posh themes
#   - Updates system font cache and sets proper permissions
#
# @return 0 if Oh My Posh is set up successfully
# @return 1 if Oh My Posh setup fails
setup_oh_my_posh_shell() {
  log_info "Performing Oh My Posh installation..."
  local posh_bin="/usr/local/bin/oh-my-posh"
  local fonts_dir="$HOME/.local/share/fonts"
  local themes_dir="$HOME/.poshthemes"
  local downloads_dir="$HOME/Downloads"
  
  # Download Oh My Posh binary
  if ! sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O "$posh_bin"; then
    log_error "Failed to download Oh My Posh"
    return 1
  fi
  
  # Make Oh My Posh binary executable
  if ! sudo chmod +x "$posh_bin"; then
    log_error "Failed to make Oh My Posh executable"
    return 1
  fi
  
  # Create fonts directory for FiraCode
  if ! mkdir -p "$fonts_dir"; then
    log_error "Failed to create fonts directory"
    return 1
  fi
  
  # Download FiraCode Nerd Font
  if ! wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip -O "$downloads_dir/firacode.zip"; then
    log_error "Failed to download FiraCode font"
    return 1
  fi
  
  # Extract FiraCode font to fonts directory
  if ! unzip "$downloads_dir/firacode.zip" -d "$fonts_dir"; then
    log_error "Failed to extract FiraCode font"
    return 1
  fi

  # Update system font cache
  if ! fc-cache -f -v; then
    log_warning "Failed to update font cache"
  fi

  # Create themes directory
  if ! mkdir -p "$themes_dir"; then
    log_error "Failed to create themes directory"
    return 1
  fi
  
  # Download Oh My Posh themes
  if ! wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O "$themes_dir/themes.zip"; then
    log_error "Failed to download Oh My Posh themes"
    return 1
  fi
  
  # Extract themes to themes directory
  if ! unzip "$themes_dir/themes.zip" -d "$themes_dir"; then
    log_error "Failed to extract Oh My Posh themes"
    return 1
  fi
  
  # Set proper permissions on theme files
  if ! chmod u+rw "$themes_dir"/*.json; then
    log_warning "Failed to set permissions on theme files"
  fi
  
  # Clean up themes zip file
  if ! rm "$themes_dir/themes.zip"; then
    log_warning "Failed to clean up themes zip file"
  fi
  
  log_success "Oh My Posh shell setup completed"
}

# Function to configure shell environment
# Configures .bashrc to include fastfetch and Oh My Posh prompt
# Creates backup of existing .bashrc before making changes
#
# @details This function:
#   - Checks if configuration already exists to avoid duplication
#   - Creates timestamped backup of .bashrc
#   - Adds fastfetch command for system info display
#   - Adds Oh My Posh initialization with jandedobbeleer theme
#
# @return 0 if shell environment is configured successfully
# @return 1 if shell configuration fails
configure_shell_environment() {
  local bashrc_path="$HOME/.bashrc"
  local config_block="\n# fastfetch and poshtheme\n"
  local fastfetch_line="fastfetch\n"
  local poshtheme_line="eval \"\$(oh-my-posh init bash --config ~/.poshthemes/jandedobbeleer.omp.json)\n\""

  # Check if configuration already exists in .bashrc
  if grep -q "fastfetch and poshtheme" "$bashrc_path" 2>/dev/null; then
    log_info "Shell configuration already exists in .bashrc"
    return 0
  fi

  # Create backup of existing .bashrc with timestamp
  if ! cp "$bashrc_path" "${bashrc_path}.backup.$(date +%Y%m%d_%H%M%S)"; then
    log_warning "Failed to backup .bashrc"
  fi

  # Add configuration section header
  if ! echo -e "$config_block" >> "$bashrc_path"; then
    log_error "Failed to add configuration block to .bashrc"
    return 1
  fi
  
  # Add fastfetch command for system information display
  if ! echo -e "$fastfetch_line" >> "$bashrc_path"; then
    log_error "Failed to add fastfetch line to .bashrc"
    return 1
  fi
  
  # Add Oh My Posh initialization command
  if ! echo -e "$poshtheme_line" >> "$bashrc_path"; then
    log_error "Failed to add Oh My Posh line to .bashrc"
    return 1
  fi
  
  log_success "Shell environment configured successfully"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function that orchestrates the entire package installation process
# Executes all installation and configuration functions in sequence
# Sets up a complete development environment with essential tools and applications
#
# @details This function performs the following operations:
#   1. Updates system firmware for hardware compatibility
#   2. Configures Flatpak for sandboxed applications
#   3. Installs multimedia codecs for media playback
#   4. Configures Firefox video codecs
#   5. Installs essential system packages
#   6. Installs Microsoft fonts for better web compatibility
#   7. Installs development IDEs (JetBrains, VS Code)
#   8. Sets up Docker containerization platform
#   9. Configures virtualization stack
#   10. Installs Oh My Posh for enhanced shell experience
#   11. Installs Brave Browser for privacy-focused browsing
#   12. Installs Wine for Windows application compatibility
#   13. Configures shell environment with customizations
#
# @param $1 Optional action parameter: "remove" to clean up IDEs and downloads
# @return 0 if all operations complete successfully
# @return 1 if any critical operation fails
main() {
    log_info "Starting comprehensive package installation..."
    
    # Perform firmware updates for hardware compatibility
    update_system_firmware

    # Configure Flatpak for sandboxed applications
    setup_flatpak_environment

    # Install multimedia codecs for comprehensive media support
    install_multimedia_codecs

    # Configure Firefox video codecs for web video playback
    configure_firefox_codecs

    # Install essential system packages and utilities
    install_packages "${PROGRAMS_TO_INSTALL_DNF[@]}"

    # Install Microsoft fonts for better web compatibility
    install_microsoft_fonts

    # Install Oh My Posh for enhanced shell experience
    setup_oh_my_posh_shell

    # Install Brave Browser for privacy-focused browsing
    install_brave_browser

    # Install Wine for Windows application compatibility
    install_wine

    # Configure shell environment with customizations
    configure_shell_environment
    
    log_success "Package installation completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.bashrc' to apply shell changes."
}

# Execute main function
main "$@"
