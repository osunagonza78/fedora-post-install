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

- **OS**: Fedora 41 or newer (DNF5 is required)
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

`run.sh` launches a tmux split-pane menu on its own dedicated socket. The
menu lives in the left pane; output streams in the right pane. A green ✓
appears next to any entry already completed in this state directory.

```
╭──────────────────────────────────────────────────────────╮
│             FEDORA POST-INSTALL TOOL                     │
╰──────────────────────────────────────────────────────────╯

  1) ✓ System Configuration
       Optimize DNF, set hostname, and tune system limits.

  2)   Packages Installation
       Enable RPM Fusion, Flatpak, and install essential apps.

  3)   Development Environment Installation
       Install Development Tools.

  4)   Virtualization Stack
       Install KVM/QEMU hypervisor and libvirt services.

  5)   Secure Boot Config
       Generate and enroll MOK keys for 3rd party modules.

  6)   Nvidia Drivers
       Install latest proprietary drivers via Akmod.

  7)   Run Recommended Baseline
       System Configuration + Packages Installation back-to-back.

  8)   Exit

──────────────────────────────────────────────────────────
↑↓/jk navigate  •  1-9 jump  •  Enter select  •  q quit
Alt+←/→ switch panes  •  Ctrl+b [ scrollback
```

### CLI flags

```
./run.sh                       Interactive menu (default)
./run.sh --list                Print available script keys and exit
./run.sh --run KEY             Run one script non-interactively (no tmux)
./run.sh --run all             Run the recommended baseline
./run.sh --dry-run [--run KEY] Print every privileged call as `DRY:` and skip
./run.sh --help                Show usage
```

The non-interactive path is what to use from Ansible / Vagrant / Packer.

### State and logs

- Per-pane output is tee'd to `${XDG_STATE_HOME:-~/.local/state}/fpi/logs/<key>-<timestamp>.log`.
- Completed scripts are recorded in `~/.local/state/fpi/done` so the menu ✓ marker survives a reboot.

### Personal preferences

Defaults assume an opinionated workstation (Brave, Wine, Oh My Posh +
fastfetch, FiraCode, JetBrains IDEs, VS Code). Copy
`config/profile.env.example` to `config/profile.env` and flip any
`ENABLE_*` toggle to `0` to skip its install. `OMP_THEME` picks which Oh
My Posh theme is wired into the shellrc.

### Multi-shell support

The shellrc init blocks (Java/Gradle exports, fastfetch + Oh My Posh
init) are written to whichever rc file matches `$SHELL`:

| Shell | File                                  |
|-------|---------------------------------------|
| bash  | `~/.bashrc`                           |
| zsh   | `~/.zshrc`                            |
| fish  | `~/.config/fish/config.fish` (fish syntax) |

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
├── run.sh                              # Interactive launcher + CLI entry
├── scripts/                            # Individual installation scripts
│   ├── system_configuration.sh
│   ├── packages_installation.sh
│   ├── development_installation.sh
│   ├── virtualization_installation.sh
│   ├── configure_secureboot.sh
│   └── nvidia_drivers.sh
├── lib/                                # Shared libraries
│   ├── ui.sh                           # Colour palette + style codes
│   ├── logging.sh                      # log_info/warning/error/success
│   ├── verify.sh                       # require_fedora, confirm_reboot, checksum helpers
│   ├── runtime.sh                      # State paths, dry-run sudo override, mark_done
│   ├── shellrc.sh                      # detect_shell_rc, append_if_missing
│   ├── output_pane.sh                  # Right-pane runner (tees to log)
│   ├── package_utils.sh                # install_packages helper
│   └── versions.sh                     # Pinned URLs + SHA-256 sibling refs
├── config/
│   └── profile.env.example             # Copy to profile.env to override defaults
├── .github/workflows/
│   └── shellcheck.yml                  # lint on every PR
├── IMPROVEMENTS.md                     # Reliability/usability backlog
├── README.md                           # This documentation
└── LICENSE                             # GPL v3.0
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
- Comprehensive logging with colour-coded output
- Idempotent: re-running skips work already done
- Checksum verification on every download with a vendor-published `.sha256`
- Dry-run support: every privileged call is gated through a single `sudo`
  wrapper that respects `FPI_DRY_RUN`

> Note: there is **no rollback support** — changes the scripts make to
> `/etc/dnf/dnf.conf`, `/etc/environment`, etc. are persistent. Snapshot
> the host (Timeshift, BTRFS snapshots, LVM) before running on systems
> that need an undo path.

### Updating pinned versions

`lib/versions.sh` pins JetBrains IDE, Gradle, OpenJDK, and FiraCode
versions. When a JetBrains release rotates out of the download server,
update the corresponding `*_VERSION` variable and run `--dry-run --run
development_installation` to confirm the new URL resolves.

| Variable          | Where to find the latest                                                   |
|-------------------|-----------------------------------------------------------------------------|
| `IDEA_VERSION`    | https://www.jetbrains.com/idea/download/other.html                          |
| `PYCHARM_VERSION` | https://www.jetbrains.com/pycharm/download/other.html                       |
| `GRADLE_VERSION`  | https://gradle.org/releases/                                                |
| `OPENJDK_*`       | https://jdk.java.net/                                                       |
| `FIRACODE_VERSION`| https://github.com/ryanoasis/nerd-fonts/releases                            |

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

