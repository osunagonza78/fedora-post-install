#!/bin/bash

###############################################################################
# Packages Installation Script for Fedora
###############################################################################
# This script installs essential packages, multimedia codecs, etc.
#
# Author: Gilberto Osuna Gonzalez
# Version: 1.0
###############################################################################

set -Eeuo pipefail

# Source logging and package utilities libraries
SCRIPT_DIR="$(dirname "$0")"

source "${SCRIPT_DIR}/../lib/logging.sh"
source "${SCRIPT_DIR}/../lib/verify.sh"
source "${SCRIPT_DIR}/../lib/runtime.sh"
source "${SCRIPT_DIR}/../lib/shellrc.sh"
require_fedora
source "${SCRIPT_DIR}/../lib/versions.sh"
source "${SCRIPT_DIR}/../lib/package_utils.sh"

# Optional per-user overrides — see config/profile.env.example. Toggles like
# ENABLE_BRAVE_BROWSER, ENABLE_WINE, OMP_THEME live there.
if [[ -f "${SCRIPT_DIR}/../config/profile.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/../config/profile.env"
fi


# Global variables
# ROCm packages live in install_amd_rocm_stack instead — they're a ~1 GB
# pull and only useful when an AMD GPU is present.
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

  # Add Flathub repository if not already present. Capture remote-list first:
  # `flatpak remote-list | grep -q` can SIGPIPE flatpak under `set -o pipefail`.
  local flatpak_remotes
  flatpak_remotes=$(flatpak remote-list 2>/dev/null) || true
  if ! grep -q "flathub" <<<"$flatpak_remotes"; then
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
  if [[ "${ENABLE_MS_FONTS:-1}" != "1" ]]; then
    log_info "Microsoft fonts disabled by profile.env — skipping"
    return 0
  fi
  log_info "Performing fonts setup..."

  # Install font management dependencies
  if ! sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig; then
    log_error "Failed to install font dependencies"
    return 1
  fi

  # Download Microsoft Core Fonts installer with curl to a tempfile, install
  # the local RPM with dnf, then remove the downloaded file.
  # dnf install (vs. rpm -i) is idempotent and resolves dependencies, where
  # rpm -i errors on the second run.
  local ms_fonts_url="https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm"
  local ms_fonts_rpm
  if ! ms_fonts_rpm=$(mktemp -t msttcore-fonts-installer.XXXXXX.rpm); then
    log_error "Failed to create tempfile for Microsoft fonts installer"
    return 1
  fi

  if ! curl -fsSL -o "$ms_fonts_rpm" "$ms_fonts_url"; then
    log_error "Failed to download Microsoft fonts installer"
    rm -f "$ms_fonts_rpm"
    return 1
  fi

  if ! sudo dnf install -y "$ms_fonts_rpm"; then
    log_error "Failed to install Microsoft fonts"
    rm -f "$ms_fonts_rpm"
    return 1
  fi

  rm -f "$ms_fonts_rpm"

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
  if [[ "${ENABLE_BRAVE_BROWSER:-1}" != "1" ]]; then
    log_info "Brave Browser disabled by profile.env — skipping"
    return 0
  fi
  log_info "Performing brave browser installation..."
  
  # Install required DNF plugins for repository management
  if ! sudo dnf install -y dnf-plugins-core; then
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
  if [[ "${ENABLE_WINE:-1}" != "1" ]]; then
    log_info "Wine disabled by profile.env — skipping"
    return 0
  fi
  log_info "Performing wine installation..."

  # WineHQ doesn't always publish a repo for the newest Fedora release the
  # day it ships. Probe the URL with wget --spider before adding the repo;
  # on a 404, fall back to the Fedora-shipped `wine` package so the user
  # still gets a working Wine.
  log_info "Probing WineHQ repository for Fedora ${FEDORA_VERSION}..."
  if wget -q --spider --tries=1 --timeout=10 "$WINE_REPO_URL"; then
    log_info "Adding WineHQ repository..."
    if ! sudo dnf config-manager addrepo --from-repofile="${WINE_REPO_URL}"; then
      log_error "Failed to add Wine repository"
      return 1
    fi
    if ! sudo dnf install -y winehq-stable; then
      log_error "Failed to install WineHQ"
      return 1
    fi
    log_success "WineHQ installed"
  else
    log_warning "WineHQ repo not available for Fedora ${FEDORA_VERSION} — falling back to Fedora-shipped wine"
    if ! sudo dnf install -y wine; then
      log_error "Failed to install Fedora wine"
      return 1
    fi
    log_success "Wine (Fedora package) installed"
  fi
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
  if [[ "${ENABLE_OMP:-1}" != "1" ]]; then
    log_info "Oh My Posh disabled by profile.env — skipping"
    return 0
  fi
  log_info "Performing Oh My Posh installation..."
  local posh_bin="/usr/local/bin/oh-my-posh"
  local fonts_dir="$HOME/.local/share/fonts"
  local themes_dir="$HOME/.poshthemes"
  local downloads_dir="$HOME/Downloads"

  mkdir -p "$downloads_dir"

  # --- Oh My Posh binary ---
  # Download as the user to a tempfile, verify SHA-256 against the vendor's
  # sibling checksum, then `install -m 0755` into /usr/local/bin. Avoids
  # running wget's TLS/HTTP stack as root.
  if [[ -x "$posh_bin" ]]; then
    log_info "Oh My Posh binary already present at $posh_bin — skipping"
  else
    local tmp_posh
    if ! tmp_posh=$(mktemp -t oh-my-posh.XXXXXX); then
      log_error "Failed to create tempfile for Oh My Posh"
      return 1
    fi
    log_info "Downloading Oh My Posh binary..."
    if ! wget -qO "$tmp_posh" "$OMP_BIN_URL"; then
      log_error "Failed to download Oh My Posh"
      rm -f "$tmp_posh"
      return 1
    fi
    if ! verify_checksum_from_url "$tmp_posh" "$OMP_BIN_SHA256_URL"; then
      log_error "Oh My Posh checksum verification failed"
      rm -f "$tmp_posh"
      return 1
    fi
    if ! sudo install -m 0755 "$tmp_posh" "$posh_bin"; then
      log_error "Failed to install Oh My Posh binary"
      rm -f "$tmp_posh"
      return 1
    fi
    rm -f "$tmp_posh"
  fi

  # --- FiraCode Nerd Font ---
  if [[ "${ENABLE_FIRACODE:-1}" != "1" ]]; then
    log_info "FiraCode disabled by profile.env — skipping"
  elif compgen -G "$fonts_dir/FiraCode*" > /dev/null; then
    log_info "FiraCode Nerd Font already installed in $fonts_dir — skipping"
  else
    if ! mkdir -p "$fonts_dir"; then
      log_error "Failed to create fonts directory"
      return 1
    fi
    log_info "Downloading FiraCode Nerd Font..."
    if ! wget -O "$downloads_dir/firacode.zip" "$FIRACODE_URL"; then
      log_error "Failed to download FiraCode font"
      return 1
    fi
    if ! verify_checksum_from_url "$downloads_dir/firacode.zip" "$FIRACODE_SHA256_URL" "FiraCode.zip"; then
      log_error "FiraCode checksum verification failed"
      return 1
    fi
    if ! unzip -o "$downloads_dir/firacode.zip" -d "$fonts_dir"; then
      log_error "Failed to extract FiraCode font"
      return 1
    fi
    rm -f "$downloads_dir/firacode.zip"
    if ! fc-cache -f -v; then
      log_warning "Failed to update font cache"
    fi
  fi

  # --- Oh My Posh themes ---
  if compgen -G "$themes_dir/*.omp.json" > /dev/null; then
    log_info "Oh My Posh themes already installed in $themes_dir — skipping"
  else
    if ! mkdir -p "$themes_dir"; then
      log_error "Failed to create themes directory"
      return 1
    fi
    log_info "Downloading Oh My Posh themes..."
    if ! wget -O "$themes_dir/themes.zip" "$OMP_THEMES_URL"; then
      log_error "Failed to download Oh My Posh themes"
      return 1
    fi
    if ! verify_checksum_from_url "$themes_dir/themes.zip" "$OMP_THEMES_SHA256_URL"; then
      log_error "Oh My Posh themes checksum verification failed"
      return 1
    fi
    if ! unzip -o "$themes_dir/themes.zip" -d "$themes_dir"; then
      log_error "Failed to extract Oh My Posh themes"
      return 1
    fi
    if compgen -G "$themes_dir/*.json" > /dev/null; then
      chmod u+rw "$themes_dir"/*.json || log_warning "Failed to set permissions on theme files"
    fi
    rm -f "$themes_dir/themes.zip"
  fi

  log_success "Oh My Posh shell setup completed"
}

# Install the AMD ROCm compute stack, but only on machines that actually
# have an AMD GPU/APU. The ROCm packages are ~1 GB and useless on Intel/NVIDIA
# hosts — see lspci-gated NVIDIA install in nvidia_drivers.sh:check_nvidia_gpu.
install_amd_rocm_stack() {
  log_info "Checking for AMD device before installing ROCm..."

  if ! command -v lspci &>/dev/null; then
    log_info "Installing pciutils (provides lspci)..."
    if ! sudo dnf -y install pciutils &>/dev/null; then
      log_warning "Failed to install pciutils — skipping ROCm"
      return 0
    fi
  fi

  # Capture lspci once — `lspci | grep -iq` SIGPIPEs lspci under pipefail when
  # a match is found, wrongly skipping ROCm exactly when an AMD GPU is present.
  local pci_devices
  pci_devices=$(lspci 2>/dev/null) || true

  if ! grep -iq amd <<<"$pci_devices"; then
    log_info "No AMD device detected — skipping ROCm install"
    return 0
  fi

  log_info "AMD device detected — installing ROCm stack..."
  install_packages rocminfo rocm-opencl rocm-clinfo rocm-hip
}

# Configure the user's shell rc file to invoke fastfetch and load Oh My Posh.
# Idempotent + multi-shell via lib/shellrc.sh:append_if_missing. Gated by the
# ENABLE_SHELL_PROMPT toggle in config/profile.env.
configure_shell_environment() {
  if [[ "${ENABLE_SHELL_PROMPT:-1}" != "1" ]]; then
    log_info "Shell prompt customisation disabled by profile.env — skipping"
    return 0
  fi

  local theme="${OMP_THEME:-jandedobbeleer}"
  local marker="# fpi: fastfetch and Oh My Posh"
  local bash_block fish_block

  bash_block="fastfetch
eval \"\$(oh-my-posh init bash --config ~/.poshthemes/${theme}.omp.json)\""

  fish_block="fastfetch
oh-my-posh init fish --config ~/.poshthemes/${theme}.omp.json | source"

  append_if_missing "$marker" "$bash_block" "$fish_block"
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

    # Each step is allowed to fail without aborting the rest, but we
    # aggregate the failure count and exit non-zero at the end so the
    # caller (and the menu's "✓ Completed" message) reflects reality.
    local failures=0

    update_system_firmware                          || failures=$((failures + 1))
    setup_flatpak_environment                       || failures=$((failures + 1))
    install_multimedia_codecs                       || failures=$((failures + 1))
    configure_firefox_codecs                        || failures=$((failures + 1))
    install_packages "${PROGRAMS_TO_INSTALL_DNF[@]}" || failures=$((failures + 1))
    install_amd_rocm_stack                          || failures=$((failures + 1))
    install_microsoft_fonts                         || failures=$((failures + 1))
    setup_oh_my_posh_shell                          || failures=$((failures + 1))
    install_brave_browser                           || failures=$((failures + 1))
    install_wine                                    || failures=$((failures + 1))
    configure_shell_environment                     || failures=$((failures + 1))

    if [[ $failures -gt 0 ]]; then
        log_error "Package installation finished with $failures failed step(s) — review the log above."
        exit 1
    fi

    log_success "Package installation completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.bashrc' to apply shell changes."
}

# Execute main function
main "$@"
