# Fedora Post-Install Suite

> An opinionated post-installation automation suite for Fedora that handles system configuration, package management, driver setup, and virtualization with an enhanced interactive interface.

## 🎯 Overview

A bash-based utility to automate the "Day 1" tasks of a Fedora install. This project handles everything from repository configuration to Nvidia driver installation and virtualization setup, ensuring a production-ready environment in minutes with a modern, user-friendly interface.

Note: This is a personal project tailored to my specific use case. It is published as-is, but users are encouraged to modify the scripts to suit their own hardware and software preferences.

## ✨ Features

- **🔧 System Configuration** - DNF optimizations, hostname setup, system limits tuning
- **📦 Package Management** - Essential packages, Flatpaks, multimedia codecs, and development tools installation
- **💻 Development Environment** - Development tools and container support setup
- **🖥️ Virtualization Stack** - KVM/QEMU hypervisor and libvirt services for virtual machines
- **🔒 Secure Boot Support** - Automatic MOK key generation and enrollment for 3rd-party modules
- **🎮 NVIDIA Drivers** - Latest proprietary drivers via Akmod with automatic updates
- **📺 Enhanced Output Display** - Clean, real-time command execution with progress tracking

## 📋 Prerequisites

- **OS**: Latest Fedora
- **Permissions**: Root/sudo access
- **Network**: Active internet connection
- **Storage**: ~2GB free space for packages and drivers

## 🚀 Quick Start

```bash
# Clone and run the installer
git clone https://github.com/osunagonza78/fedora-post-install.git
cd fedora-post-install
chmod +x run.sh
./run.sh
```

**Note**: No sudo required for the main script - it handles privilege escalation internally when needed.

## 📖 Usage Guide

The script provides an interactive menu-driven interface with enhanced output display:

```
┌─────────────────────────────────────────────────┐
│           Fedora Post-Install Tool              │
├─────────────────────────────────────────────────┤
│ 1. System Configuration                         │
│    Optimize DNF, set hostname, and tune limits  │
│                                                 │
│ 2. Packages Installation                        │
│    Enable RPM Fusion, Flatpak, and apps         │
│                                                 │
│ 3. Development Environment Installation         │
│    Install Development Tools                    │
│                                                 │
│ 4. Virtualization Stack                         │
│    Install KVM/QEMU hypervisor and libvirt      │
│                                                 │
│ 5. Secure Boot Config                           │
│    Generate and enroll MOK keys                 │
│                                                 │
│ 6. NVIDIA Drivers                               │
│    Install latest proprietary drivers           │
│                                                 │
│ 7. Exit                                         │
└─────────────────────────────────────────────────┘
```

### Enhanced Interface Features

- **Command Preview**: Shows the exact command that will be executed
- **Real-time Output**: Displays live command output with full interactive control
- **Progress Tracking**: Clear status indicators and completion messages
- **Clean Navigation**: Arrow key navigation with visual feedback
- **Error Handling**: Detailed error messages and exit codes

### Menu Options

1. **System Configuration** - Optimize DNF, set hostname, tune system limits
2. **Packages Installation** - Install essential software, multimedia codecs, and development tools
3. **Development Environment** - Install development tools and container support
4. **Virtualization Stack** - Install KVM/QEMU hypervisor and configure libvirt services for VM support
5. **Secure Boot Config** - Configure MOK keys for third-party kernel modules
6. **NVIDIA Drivers** - Install and configure proprietary NVIDIA drivers
7. **Exit** - Close the application

## ⚠️ Important Notes

- Always review scripts before running
- Backup important data before system modifications
- Some features require system reboot
- NVIDIA driver installation may disable secure boot temporarily
- Virtualization requires CPU hardware support (Intel VT-x or AMD-V)
- The enhanced interface shows live command output - you can interrupt with Ctrl+C if needed

## 🏗️ Project Structure

```
fedora-post-install/
├── run.sh                           # Main interactive launcher
├── scripts/                         # Individual installation scripts
│   ├── system_configuration.sh      # System optimizations and tuning
│   ├── packages_installation.sh    # Essential packages and codecs
│   ├── development_installation.sh  # Development tools and Docker
│   ├── virtualization_installation.sh # KVM/QEMU and libvirt setup
│   ├── configure_secureboot.sh      # MOK key management
│   └── nvidia_drivers.sh            # NVIDIA driver installation
├── lib/                             # Shared libraries
│   └── logging.sh                   # Common logging functions
├── README.md                        # This documentation
└── LICENSE                          # GPL v3.0 License
```

## 🔧 Technical Details

### Enhanced Output System

The tool features a custom output display system that:
- Shows the exact command being executed before running
- Maintains a clean, branded interface during execution
- Provides real-time output with full interactive capabilities
- Displays completion status with exit codes
- Returns seamlessly to the main menu

### Script Organization

Each installation script is modular and independent:
- Comprehensive logging with color-coded output
- Error handling and rollback capabilities
- Dependency checking and validation
- Progress indicators and status updates

## 🤝 Contributing

Contributions are welcome! Ensure to test any change before submitting code.

### Development Guidelines

- Follow the existing code style and commenting format
- Test all functions thoroughly before submitting
- Update documentation for any new features
- Maintain compatibility with Fedora

## 📄 License

This project is open source and available under the [GPL v3.0 License](LICENSE).

## 🙏 Acknowledgments

- Fedora Project for the excellent distribution
- The open-source community for various tools and utilities

