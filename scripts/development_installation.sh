#!/bin/bash

###############################################################################
# Development Tools Installation Script for Fedora
###############################################################################
# This script installs essential development tools and configures various
# development environments on Fedora Linux.
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
source "${SCRIPT_DIR}/../lib/shellrc.sh"
require_fedora
source "${SCRIPT_DIR}/../lib/versions.sh"

# Optional per-user overrides — see config/profile.env.example.
if [[ -f "${SCRIPT_DIR}/../config/profile.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/../config/profile.env"
fi


readonly DOWNLOAD_DIR=~/Downloads
readonly JETBRAINS_DIR="/opt/jetbrains"
readonly VSCODE_REPO_FILE="/etc/yum.repos.d/vscode.repo"

# VS Code ships its own signed repository for Fedora/RHEL. The repo file
# below is the single source of truth for the baseurl, and the GPG key is
# kept in sync via `rpm --import` (idempotent on identical keys).
readonly VSCODE_GPG_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
readonly VSCODE_REPO_CONTENT="[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
"

readonly GRADLE_DIR="/opt/gradle"

# Function to install JetBrains IDEs (IntelliJ IDEA and PyCharm)
# Downloads and installs IntelliJ IDEA Ultimate and PyCharm Professional
# Extracts the IDEs to /opt/jetbrains for system-wide access
#
# @details This function:
#   - Downloads IntelliJ IDEA Ultimate and PyCharm Professional tarballs
#   - Creates /opt/jetbrains directory for installation
#   - Extracts IDEs to the installation directory
#
# @return 0 if JetBrains IDEs are installed successfully
# @return 1 if JetBrains IDE installation fails
install_jetbrains_ide() {
  if [[ "${ENABLE_JETBRAINS:-1}" != "1" ]]; then
    log_info "JetBrains IDEs disabled by profile.env — skipping"
    return 0
  fi
  log_info "Performing JetBrains IDEs installation..."

  # Download IntelliJ IDEA Community
  log_info "Downloading IntelliJ IDEA (${IDEA_VERSION})..."
  if ! wget -O "$DOWNLOAD_DIR/$IDEA_FILENAME" "$IDEA_URL"; then
    log_error "Failed to download IntelliJ IDEA"
    return 1
  fi
  if ! verify_checksum_from_url "$DOWNLOAD_DIR/$IDEA_FILENAME" "$IDEA_SHA256_URL"; then
    log_error "IntelliJ IDEA checksum verification failed"
    return 1
  fi

  # Download PyCharm Community
  log_info "Downloading PyCharm Community (${PYCHARM_VERSION})..."
  if ! wget -O "$DOWNLOAD_DIR/$PYCHARM_FILENAME" "$PYCHARM_URL"; then
    log_error "Failed to download PyCharm"
    return 1
  fi
  if ! verify_checksum_from_url "$DOWNLOAD_DIR/$PYCHARM_FILENAME" "$PYCHARM_SHA256_URL"; then
    log_error "PyCharm checksum verification failed"
    return 1
  fi

  # Create JetBrains installation directory in /opt
  log_info "Creating /opt/jetbrains directory..."
  if ! sudo mkdir -p "$JETBRAINS_DIR"; then
    log_error "Failed to create JetBrains directory"
    return 1
  fi

  # Extract IntelliJ IDEA to installation directory
  log_info "Extracting IntelliJ IDEA..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR/$IDEA_FILENAME" -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract IntelliJ IDEA"
    return 1
  fi

  # Extract PyCharm to installation directory
  log_info "Extracting PyCharm..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR/$PYCHARM_FILENAME" -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract PyCharm"
    return 1
  fi

  # Clean up downloaded archives
  rm -f "$DOWNLOAD_DIR/$IDEA_FILENAME" "$DOWNLOAD_DIR/$PYCHARM_FILENAME"
  log_success "JetBrains IDEs installed successfully"
}

# Function to install Visual Studio Code
# Adds Microsoft's official VS Code yum repository and installs the `code`
# package so future `dnf upgrade` runs keep the editor current automatically.
#
# @details This function:
#   - Imports the Microsoft package-signing GPG key
#   - Writes the vscode.repo definition (idempotent — content-matched)
#   - Installs the `code` package from the repository
#
# @return 0 if VS Code is installed successfully
# @return 1 if VS Code installation fails
install_vscode_ide() {
  if [[ "${ENABLE_VSCODE:-1}" != "1" ]]; then
    log_info "VS Code disabled by profile.env — skipping"
    return 0
  fi
  log_info "Installing Visual Studio Code..."

  # Import Microsoft's package-signing key. `rpm --import` is idempotent —
  # re-importing the exact same key is a documented no-op — so this is safe
  # to run on every invocation.
  log_info "Importing Microsoft GPG key..."
  local key_tmp
  key_tmp=$(mktemp)
  # shellcheck disable=SC2064  # we want $key_tmp expanded now, not later.
  trap "rm -f '$key_tmp'" RETURN
  if ! curl -fsSL "$VSCODE_GPG_KEY_URL" -o "$key_tmp"; then
    log_error "Failed to download Microsoft GPG key"
    return 1
  fi
  if ! sudo rpm --import "$key_tmp"; then
    log_error "Failed to import Microsoft GPG key"
    return 1
  fi

  # Add the VS Code yum repository. Writing the file ourselves (instead of
  # `dnf config-manager addrepo`) keeps the definition under version control
  # in this script and avoids depending on dnf-plugins-core here. The content
  # check makes this idempotent — a re-run with an unchanged file is a no-op.
  if [[ -f "$VSCODE_REPO_FILE" ]] \
     && diff -q <(sudo cat "$VSCODE_REPO_FILE" 2>/dev/null) \
                <(printf '%s' "$VSCODE_REPO_CONTENT") &>/dev/null; then
    log_info "VS Code repository already configured at $VSCODE_REPO_FILE"
  else
    log_info "Adding VS Code repository..."
    if ! printf '%s' "$VSCODE_REPO_CONTENT" \
         | sudo tee "$VSCODE_REPO_FILE" > /dev/null; then
      log_error "Failed to write VS Code repository file"
      return 1
    fi
  fi

  # Install (or upgrade) the `code` package. dnf is idempotent: a present
  # package at the same version is a no-op; a newer repo version upgrades.
  log_info "Installing VS Code package..."
  if ! sudo dnf -y install code; then
    log_error "Failed to install VS Code"
    return 1
  fi

  log_success "VS Code installed successfully"
}

# Function to set up Docker Engine
# Installs Docker Community Edition and configures it for use
# Removes old Docker versions, sets up repository, and adds user to docker group
#
# @details This function:
#   - Removes conflicting Docker packages
#   - Adds Docker official repository
#   - Installs Docker CE, CLI, and compose plugins
#   - Enables Docker service and adds user to docker group
#
# @return 0 if Docker Engine is set up successfully
# @return 1 if Docker setup fails
setup_docker_engine() {
  log_info "Performing Docker installation..."

  local docker_repo_file="/etc/yum.repos.d/docker-ce.repo"

  # Only remove the legacy/distro `docker` package set on first install —
  # never wipe an existing docker-ce, because re-running the menu option
  # would orphan running containers and volumes.
  if rpm -q docker-ce &>/dev/null; then
    log_info "docker-ce already installed — skipping legacy-package removal"
  else
    log_info "Removing legacy Docker packages (if any)..."
    if ! sudo dnf -y remove docker \
                    docker-client \
                    docker-client-latest \
                    docker-common \
                    docker-latest \
                    docker-latest-logrotate \
                    docker-logrotate \
                    docker-selinux \
                    docker-engine-selinux \
                    docker-engine; then
      log_warning "Some legacy Docker packages were not installed (safe to ignore)"
    fi
  fi

  # Install DNF plugins for repository management
  log_info "Ensuring dnf-plugins-core is installed..."
  if ! sudo dnf -y install dnf-plugins-core; then
    log_error "Failed to install dnf-plugins-core"
    return 1
  fi

  # Add Docker official repository (idempotent). Uses DNF5 `addrepo` subcommand
  # to match the rest of the codebase; DNF4's `--add-repo` flag is gone.
  if [[ -f "$docker_repo_file" ]]; then
    log_info "Docker repository already configured at $docker_repo_file"
  else
    log_info "Adding Docker repository..."
    if ! sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo; then
      log_error "Failed to add Docker repository"
      return 1
    fi
  fi

  # Install Docker CE and related packages (idempotent — dnf will no-op
  # when packages are present, or upgrade if a newer version is available)
  log_info "Installing/upgrading Docker packages..."
  if ! sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    log_error "Failed to install Docker packages"
    return 1
  fi

  # Enable Docker service to start on boot (idempotent)
  log_info "Enabling Docker service..."
  if ! sudo systemctl enable --now docker; then
    log_error "Failed to enable Docker service"
    return 1
  fi

  # Add current user to docker group for non-root usage (idempotent).
  # A substring match on the captured group list avoids `id -nG | tr | grep`,
  # which can SIGPIPE under `set -o pipefail`.
  local user_groups
  user_groups=" $(id -nG "$USER" 2>/dev/null) "
  if [[ "$user_groups" == *" docker "* ]]; then
    log_info "User '$USER' is already in the docker group"
  else
    log_info "Adding user '$USER' to docker group..."
    if ! sudo usermod -aG docker "$USER"; then
      log_error "Failed to add user to docker group"
      return 1
    fi
    log_warning "Log out and back in for the docker group membership to take effect."
  fi

  log_success "Docker engine setup completed"
}

# Function to install OpenJDK
# Downloads and installs Oracle OpenJDK for Java development
# Extracts JDK to /opt/java for system-wide access
#
# @details This function:
#   - Downloads Oracle OpenJDK tarball
#   - Creates /opt/java directory for installation
#   - Extracts JDK to the installation directory
#   - Sets up JAVA_HOME environment variable
#
# @return 0 if OpenJDK is installed successfully
# @return 1 if OpenJDK installation fails
install_openjdk() {
  log_info "Installing OpenJDK ..."

  local java_home="/opt/java/jdk-21"

  # Skip the download/extract entirely if the JDK is already on disk.
  if [[ -d "$java_home" ]]; then
    log_info "OpenJDK already present at $java_home — skipping download/extract"
  else
    log_info "Downloading OpenJDK ..."
    if ! wget -O "$DOWNLOAD_DIR/$OPENJDK_FILENAME" "$OPENJDK_URL"; then
      log_error "Failed to download OpenJDK"
      return 1
    fi
    if ! verify_checksum_from_url "$DOWNLOAD_DIR/$OPENJDK_FILENAME" "$OPENJDK_SHA256_URL"; then
      log_error "OpenJDK checksum verification failed"
      return 1
    fi

    log_info "Creating /opt/java directory..."
    if ! sudo mkdir -p /opt/java; then
      log_error "Failed to create Java directory"
      return 1
    fi

    log_info "Extracting OpenJDK ..."
    if ! sudo tar -xzf "$DOWNLOAD_DIR/$OPENJDK_FILENAME" -C /opt/java; then
      log_error "Failed to extract OpenJDK"
      return 1
    fi

    log_info "Removing downloaded OpenJDK files..."
    rm -f "$DOWNLOAD_DIR/$OPENJDK_FILENAME"
  fi

  # Set JAVA_HOME in /etc/environment (idempotent: replace or append, never
  # duplicate). Without this guard, every re-run appended another line.
  log_info "Setting JAVA_HOME environment variable..."
  if sudo grep -q "^JAVA_HOME=" /etc/environment 2>/dev/null; then
    if ! sudo sed -i "s|^JAVA_HOME=.*|JAVA_HOME=${java_home}|" /etc/environment; then
      log_error "Failed to update JAVA_HOME in /etc/environment"
      return 1
    fi
  else
    if ! echo "JAVA_HOME=${java_home}" | sudo tee -a /etc/environment > /dev/null; then
      log_error "Failed to set JAVA_HOME"
      return 1
    fi
  fi

  # Add Java to PATH for all users (single-file owner, safe to overwrite)
  if ! echo "export PATH=\$JAVA_HOME/bin:\$PATH" | sudo tee /etc/profile.d/java.sh > /dev/null; then
    log_error "Failed to add Java to PATH"
    return 1
  fi

  log_success "OpenJDK installed successfully"
}

# Function to install Gradle
# Downloads and installs Gradle build tool for Java projects
# Extracts Gradle to /opt/gradle for system-wide access
#
# @details This function:
#   - Downloads Gradle binary distribution
#   - Creates /opt/gradle directory for installation
#   - Extracts Gradle to the installation directory
#   - Sets up GRADLE_HOME environment variable and adds to PATH
#
# @return 0 if Gradle is installed successfully
# @return 1 if Gradle installation fails
install_gradle() {
  log_info "Installing Gradle"

  local gradle_home="${GRADLE_DIR}/${GRADLE_HOME_DIR}"

  # Skip the download/extract entirely if the requested Gradle version is
  # already on disk.
  if [[ -d "$gradle_home" ]]; then
    log_info "Gradle already present at $gradle_home — skipping download/extract"
  else
    log_info "Downloading Gradle ."
    if ! wget -O "$DOWNLOAD_DIR/$GRADLE_FILENAME" "$GRADLE_URL"; then
      log_error "Failed to download Gradle"
      return 1
    fi
    if ! verify_checksum_from_url "$DOWNLOAD_DIR/$GRADLE_FILENAME" "$GRADLE_SHA256_URL"; then
      log_error "Gradle checksum verification failed"
      return 1
    fi

    if ! command -v unzip &> /dev/null; then
      log_info "Installing unzip..."
      if ! sudo dnf -y install unzip; then
        log_error "Failed to install unzip"
        return 1
      fi
    fi

    log_info "Creating /opt/gradle directory..."
    if ! sudo mkdir -p "$GRADLE_DIR"; then
      log_error "Failed to create Gradle directory"
      return 1
    fi

    log_info "Extracting Gradle..."
    if ! sudo unzip -q "$DOWNLOAD_DIR/$GRADLE_FILENAME" -d "$GRADLE_DIR"; then
      log_error "Failed to extract Gradle"
      return 1
    fi

    log_info "Removing downloaded Gradle files..."
    rm -f "$DOWNLOAD_DIR/$GRADLE_FILENAME"
  fi

  # Set GRADLE_HOME in /etc/environment (idempotent: replace or append).
  log_info "Setting GRADLE_HOME environment variable..."
  if sudo grep -q "^GRADLE_HOME=" /etc/environment 2>/dev/null; then
    if ! sudo sed -i "s|^GRADLE_HOME=.*|GRADLE_HOME=${gradle_home}|" /etc/environment; then
      log_error "Failed to update GRADLE_HOME in /etc/environment"
      return 1
    fi
  else
    if ! echo "GRADLE_HOME=${gradle_home}" | sudo tee -a /etc/environment > /dev/null; then
      log_error "Failed to set GRADLE_HOME"
      return 1
    fi
  fi

  # Add Gradle to PATH for all users (single-file owner, safe to overwrite)
  if ! echo "export PATH=\$GRADLE_HOME/bin:\$PATH" | sudo tee /etc/profile.d/gradle.sh > /dev/null; then
    log_error "Failed to add Gradle to PATH"
    return 1
  fi

  log_success "Gradle installed successfully"
}

# Configure the user's shell rc file with JAVA_HOME, GRADLE_HOME, and PATH.
# Idempotent + multi-shell via lib/shellrc.sh:append_if_missing.
configure_shell_environment() {
  local java_home="/opt/java/jdk-21"
  local gradle_home="${GRADLE_DIR}/${GRADLE_HOME_DIR}"
  local marker="# fpi: Java and Gradle"
  local bash_block fish_block

  bash_block="export JAVA_HOME=${java_home}
export GRADLE_HOME=${gradle_home}
export PATH=\$PATH:\$JAVA_HOME/bin:\$GRADLE_HOME/bin"

  fish_block="set -x JAVA_HOME ${java_home}
set -x GRADLE_HOME ${gradle_home}
set -x PATH \$PATH \$JAVA_HOME/bin \$GRADLE_HOME/bin"

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
#   1. Installs development IDEs (JetBrains, VS Code)
#   2. Sets up Docker containerization platform
#   3. Installs OpenJDK for Java development
#   4. Installs Gradle build tool
#
# @param $1 Optional action parameter: "remove" to clean up IDEs and downloads
# @return 0 if all operations complete successfully
# @return 1 if any critical operation fails
main() {
    log_info "Starting comprehensive development environment and container's installation..."

    # Aggregate failures across steps so the exit code reflects reality.
    local failures=0

    install_jetbrains_ide       || failures=$((failures + 1))
    install_vscode_ide          || failures=$((failures + 1))
    setup_docker_engine         || failures=$((failures + 1))
    install_openjdk             || failures=$((failures + 1))
    install_gradle              || failures=$((failures + 1))
    configure_shell_environment || failures=$((failures + 1))

    if [[ $failures -gt 0 ]]; then
        log_error "Development installation finished with $failures failed step(s) — review the log above."
        exit 1
    fi

    log_success "Development environment and container's installation completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.bashrc' to apply shell changes."
}

# Execute main function
main "$@"
