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

# Source logging library
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/../lib/logging.sh"


readonly DOWNLOAD_DIR=~/Downloads
readonly JETBRAINS_DIR="/opt/jetbrains"
readonly VSCODE_DIR="/opt/vscode"

# URLs for downloading software, ensure to keep them updated
readonly IDEA_URL=https://download.jetbrains.com/idea/ideaIU-2025.3.3.tar.gz
readonly PYCHARM_URL=https://download.jetbrains.com/python/pycharm-2025.3.3.tar.gz

readonly VSCODE_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-x64"

# URLs for Java development tools
readonly OPENJDK_URL=https://download.java.net/openjdk/jdk21/ri/openjdk-21+35_linux-x64_bin.tar.gz
readonly GRADLE_URL=https://services.gradle.org/distributions/gradle-8.14.4-bin.zip

readonly GRADLE_DIR="/opt/gradle"

readonly bashrc_path="$HOME/.bashrc"

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
  log_info "Performing JetBrains IDEs installation..."

  # Download IntelliJ IDEA Ultimate
  log_info "Downloading IntelliJ IDEA Ultimate..."
  if ! wget -P "$DOWNLOAD_DIR" "$IDEA_URL"; then
    log_error "Failed to download IntelliJ IDEA"
    return 1
  fi

  # Download PyCharm Professional
  log_info "Downloading PyCharm Professional..."
  if ! wget -P "$DOWNLOAD_DIR" "$PYCHARM_URL"; then
    log_error "Failed to download PyCharm"
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
  if ! sudo tar -xzf "$DOWNLOAD_DIR"/ideaIU-*.tar.gz -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract IntelliJ IDEA"
    return 1
  fi

  # Extract PyCharm to installation directory
  log_info "Extracting PyCharm..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR"/pycharm-*.tar.gz -C "$JETBRAINS_DIR"; then
    log_error "Failed to extract PyCharm"
    return 1
  fi

  # Remove downloaded IntelliJ IDEA tarball
  local idea_files
  idea_files=$(find "$DOWNLOAD_DIR" -name "ideaIU-*.tar.gz" -type f 2>/dev/null)
  if [ -n "$idea_files" ]; then
    log_info "Removing downloaded IntelliJ IDEA files..."
    echo "$idea_files" | xargs rm -f
  else
    log_info "No IntelliJ IDEA download files found"
  fi

  # Remove downloaded PyCharm tarball
  local pycharm_files
  pycharm_files=$(find "$DOWNLOAD_DIR" -name "pycharm-*.tar.gz" -type f 2>/dev/null)
  if [ -n "$pycharm_files" ]; then
    log_info "Removing downloaded PyCharm files..."
    echo "$pycharm_files" | xargs rm -f
  else
    log_info "No PyCharm download files found"
  fi

  log_success "JetBrains IDEs installed successfully"
}

# Function to install Visual Studio Code
# Downloads and installs VS Code for system-wide access
# Extracts VS Code to /opt/vscode and sets up the development environment
#
# @details This function:
#   - Downloads VS Code stable release from Microsoft
#   - Creates /opt/vscode directory for installation
#   - Extracts VS Code to the installation directory
#   - Handles dynamic filename resolution for downloaded package
#
# @return 0 if VS Code is installed successfully
# @return 1 if VS Code installation fails
install_vscode_ide() {
  log_info "Installing Visual Studio Code..."

  # Download VS Code stable release
  log_info "Downloading VS Code..."
  if ! wget --content-disposition -P "$DOWNLOAD_DIR" "$VSCODE_URL"; then
    log_error "Failed to download VS Code"
    return 1
  fi

  # Get the actual filename from the download directory (handles dynamic naming)
  local downloaded_file
  downloaded_file=$(find "$DOWNLOAD_DIR" -name "code*.tar.gz" -type f -printf "%f\n" | head -1)
  if [ -z "$downloaded_file" ]; then
    log_error "Could not find downloaded VS Code file"
    return 1
  fi

  log_info "Downloaded file: $downloaded_file"

  # Create VS Code installation directory in /opt
  log_info "Creating /opt/vscode directory..."
  if ! sudo mkdir -p "$VSCODE_DIR"; then
    log_error "Failed to create VS Code directory"
    return 1
  fi

  # Extract VS Code to installation directory
  log_info "Extracting VS Code..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR/$downloaded_file" -C "$VSCODE_DIR"; then
    log_error "Failed to extract VS Code"
    return 1
  fi

  # Remove downloaded VS Code tarball
  local vscode_files
  vscode_files=$(find "$DOWNLOAD_DIR" -name "code*.tar.gz" -type f 2>/dev/null)
  if [ -n "$vscode_files" ]; then
    log_info "Removing downloaded VS Code files..."
    echo "$vscode_files" | xargs rm -f
  else
    log_info "No VS Code download files found"
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

  # Remove conflicting Docker packages
  log_info "Removing previous Docker installation..."
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
    log_warning "Some Docker packages may not have been installed"
  fi

  # Install DNF plugins for repository management
  log_info "Setting up Docker repository..."
  if ! sudo dnf -y install dnf-plugins-core; then
    log_error "Failed to install dnf-plugins-core"
    return 1
  fi

  # Add Docker official repository
  if ! sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo; then
    log_error "Failed to add Docker repository"
    return 1
  fi

  # Install Docker CE and related packages
  log_info "Installing Docker packages..."
  if ! sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    log_error "Failed to install Docker packages"
    return 1
  fi

  # Enable Docker service to start on boot
  log_info "Enabling Docker service..."
  if ! sudo systemctl enable --now docker; then
    log_error "Failed to enable Docker service"
    return 1
  fi

  # Add current user to docker group for non-root usage
  log_info "Adding user to docker group..."
  if ! sudo usermod -aG docker "$USER"; then
    log_error "Failed to add user to docker group"
    return 1
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

  # Download OpenJDK 21
  log_info "Downloading OpenJDK ..."
  if ! wget -P "$DOWNLOAD_DIR" "$OPENJDK_URL"; then
    log_error "Failed to download OpenJDK"
    return 1
  fi

  # Create Java installation directory in /opt
  log_info "Creating /opt/java directory..."
  if ! sudo mkdir -p /opt/java; then
    log_error "Failed to create Java directory"
    return 1
  fi

  # Extract OpenJDK 21 to installation directory
  log_info "Extracting OpenJDK ..."
  if ! sudo tar -xzf "$DOWNLOAD_DIR"/openjdk-21*.tar.gz -C /opt/java; then
    log_error "Failed to extract OpenJDK"
    return 1
  fi

  # Remove downloaded OpenJDK tarball
  log_info "Removing downloaded OpenJDK files..."
  rm -f "$DOWNLOAD_DIR"/openjdk-21*.tar.gz

  # Set JAVA_HOME in /etc/environment for system-wide access
  log_info "Setting JAVA_HOME environment variable..."
  if ! echo "JAVA_HOME=/opt/java/jdk-21" | sudo tee -a /etc/environment > /dev/null; then
    log_error "Failed to set JAVA_HOME"
    return 1
  fi

  # Add Java to PATH for all users
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

  # Download Gradle 8.14.4
  log_info "Downloading Gradle ."
  if ! wget -P "$DOWNLOAD_DIR" "$GRADLE_URL"; then
    log_error "Failed to download Gradle"
    return 1
  fi

  # Install unzip if not already present
  if ! command -v unzip &> /dev/null; then
    log_info "Installing unzip..."
    if ! sudo dnf -y install unzip; then
      log_error "Failed to install unzip"
      return 1
    fi
  fi

  # Create Gradle installation directory in /opt
  log_info "Creating /opt/gradle directory..."
  if ! sudo mkdir -p "$GRADLE_DIR"; then
    log_error "Failed to create Gradle directory"
    return 1
  fi

  # Extract Gradle to installation directory
  log_info "Extracting Gradle..."
  if ! sudo unzip -q "$DOWNLOAD_DIR"/gradle-8*.zip -d "$GRADLE_DIR"; then
    log_error "Failed to extract Gradle"
    return 1
  fi

  # Remove downloaded Gradle zip file
  log_info "Removing downloaded Gradle files..."
  rm -f "$DOWNLOAD_DIR"/gradle-8*.zip

  # Set GRADLE_HOME in /etc/environment for system-wide access
  log_info "Setting GRADLE_HOME environment variable..."
  if ! echo "GRADLE_HOME=/opt/gradle/gradle-8.14.4" | sudo tee -a /etc/environment > /dev/null; then
    log_error "Failed to set GRADLE_HOME"
    return 1
  fi

  # Add Gradle to PATH for all users
  if ! echo "export PATH=\$GRADLE_HOME/bin:\$PATH" | sudo tee /etc/profile.d/gradle.sh > /dev/null; then
    log_error "Failed to add Gradle to PATH"
    return 1
  fi

  log_success "Gradle installed successfully"

}

# Function to configure shell environment
# Configures .bashrc to include Java and Gradle
# Creates backup of existing .bashrc before making changes
#
# @details This function:
#   - Checks if configuration already exists to avoid duplication
#   - Creates timestamped backup of .bashrc
#   - Adds Java and Gradle path for user usage
#
# @return 0 if shell environment is configured successfully
# @return 1 if shell configuration fails
configure_shell_environment() {
  local config_block="\n# Java and Gradle\n"
  local java_home="export JAVA_HOME=/opt/java/jdk-21"
  local gradle_home="export GRADLE_HOME=/opt/gradle/gradle-8.14.4"

  # Ccombine the paths for Java and Gradle
  local path_config='export PATH=$PATH:$JAVA_HOME/bin:$GRADLE_HOME/bin'

  # Create backup of existing .bashrc with timestamp
  if ! cp "$bashrc_path" "${bashrc_path}.backup.$(date +%Y%m%d_%H%M%S)"; then
    log_warning "Failed to backup .bashrc"
  fi

  # Add configuration section header
  if ! echo -e "$config_block" >> "$bashrc_path"; then
    log_error "Failed to add configuration block to .bashrc"
    return 1
  fi

  # Add JAVA_HOME
  if ! echo -e "$java_home" >> "$bashrc_path"; then
    log_error "Failed to add JAVA_HOME line to .bashrc"
    return 1
  fi

  # Add GRADLE_HOME
  if ! echo -e "$gradle_home" >> "$bashrc_path"; then
    log_error "Failed to add GRADLE_HOME line to .bashrc"
    return 1
  fi

  # Add PATH configuration
  if ! echo -e "$path_config" >> "$bashrc_path"; then
    log_error "Failed to add PATH line to .bashrc"
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

    # Install JetBrains IDEs (IntelliJ IDEA and PyCharm)
    #install_jetbrains_ide

    # Install Visual Studio Code
    #install_vscode_ide

    # Set up Docker containerization platform
    #setup_docker_engine

    #Install OpenJDK 21 for Java development
    # install_openjdk

    # Install Gradle 8.14.3 build tool
    # install_gradle

    # # Configure shell environment
    configure_shell_environment

    log_success "Development environment and container's installation completed successfully!"
    log_info "Please restart your terminal or run 'source ~/.bashrc' to apply shell changes."
}

# Execute main function
main "$@"
