# MixOS-GO v1.0.0

A minimal, security-hardened Linux distribution with a professional package manager written in Go.

## Features

- **Minimal Footprint**: ~400MB ISO, <200MB RAM usage
- **Fast Boot**: <5 seconds to login prompt
- **Security Hardened**: Kernel hardening, iptables firewall, SSH key-only auth
- **Professional Package Manager**: `mix` CLI with dependency resolution
- **Modern Stack**: Linux 6.6.8 kernel, musl libc, BusyBox utilities

## Quick Start

### Building

```bash
# Build everything
make all

# Or build individual components
make kernel      # Build Linux kernel
make mix-cli     # Build package manager
make packages    # Build packages
make rootfs      # Build root filesystem
make iso         # Build bootable ISO
```

### Unattended / Automated ISO

You can build an unattended ISO that embeds a sample installer config (`packaging/install.yaml`) and will run the installer at first boot.

```bash
# Build an unattended ISO using the repository sample config
make iso-autoinstall

# Or provide your own config
INSTALL_CONFIG=/path/to/install.yaml make iso
```

### Testing

```bash
# Run unit tests
make test

# Boot in QEMU
make test-qemu
```

### Using the Package Manager

```bash
# Update package database
mix update

# Search for packages
mix search nginx

# Install a package
mix install openssh

# List installed packages
mix list

# Remove a package
mix remove nginx

# Show package info
mix info openssh
```

## System Requirements

### Build Requirements

- Go 1.21+
- GCC/G++
- Make
- GRUB tools (grub-mkrescue)
- SquashFS tools
- cpio, gzip, xz

### Runtime Requirements

- x86_64 CPU
- 512MB RAM (minimum)
- BIOS or UEFI boot

## Directory Structure

```
mixos-go/
├── build/
│   ├── docker/          # Docker toolchain
│   └── scripts/         # Build scripts
├── configs/
│   ├── kernel/          # Kernel configuration
│   └── security/        # Security hardening
├── src/
│   ├── mix-cli/         # Package manager source
│   └── packages/        # Package build recipes
├── tests/               # Test files
├── docs/                # Documentation
├── artifacts/           # Build output
└── Makefile
```

## Package Format (.mixpkg)

Packages are gzipped tarballs containing:

```
package-1.0.0.mixpkg
├── metadata.json        # Package metadata
├── files/               # Files to install
│   ├── usr/bin/...
│   └── etc/...
└── scripts/             # Optional install scripts
    ├── pre-install.sh
    └── post-install.sh
```

### metadata.json Schema

```json
{
  "name": "package-name",
  "version": "1.0.0",
  "description": "Package description",
  "dependencies": ["dep1", "dep2>=1.0"],
  "files": ["/usr/bin/binary", "/etc/config"],
  "checksum": "sha256..."
}
```

## Security Features

### Kernel Hardening

- Namespaces and cgroups enabled
- SELinux/AppArmor support
- Hardened usercopy
- FORTIFY_SOURCE enabled
- KASLR enabled

### Network Security

- Default-deny iptables firewall
- SSH rate limiting
- SYN cookies enabled
- ICMP restrictions

### System Security

- No root password login (SSH key only)
- Restricted sysctl parameters
- Protected symlinks/hardlinks
- Audit logging

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `make test`
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- Linux kernel developers
- BusyBox project
- Alpine Linux (inspiration)
- Go community
