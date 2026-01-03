# MixOS-GO Installation Guide

## System Requirements

### Minimum Requirements
- x86_64 processor
- 512MB RAM
- 1GB disk space
- BIOS or UEFI boot support

### Recommended Requirements
- x86_64 processor (Intel/AMD)
- 1GB+ RAM
- 4GB+ disk space
- Network connectivity

## Installation Methods

### 1. Live Boot (Recommended for Testing)

1. Download the ISO: `mixos-go-v1.0.0.iso`
2. Verify checksum:
   ```bash
   sha256sum -c mixos-go-v1.0.0.iso.sha256
   ```
3. Boot from ISO (USB or CD)
4. Login as root (no password required for console)

### 2. Virtual Machine Installation

#### QEMU/KVM
```bash
# Create disk image
qemu-img create -f qcow2 mixos.qcow2 4G

# Boot from ISO
qemu-system-x86_64 \
    -cdrom mixos-go-v1.0.0.iso \
    -hda mixos.qcow2 \
    -m 1024 \
    -enable-kvm \
    -boot d
```

#### VirtualBox
1. Create new VM (Linux, Other Linux 64-bit)
2. Allocate 1GB RAM, 4GB disk
3. Mount ISO as CD/DVD
4. Boot and install

### 3. Disk Installation

**Warning**: This will erase all data on the target disk!

```bash
# Boot from ISO first, then:

# Partition disk (example: /dev/sda)
fdisk /dev/sda
# Create: 512MB boot partition (sda1), rest for root (sda2)

# Format partitions
mkfs.ext4 /dev/sda1
mkfs.ext4 /dev/sda2

# Mount
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Copy system
cp -a /mnt/cdrom/live/* /mnt/

# Install bootloader
grub-install --target=i386-pc --boot-directory=/mnt/boot /dev/sda

# Configure fstab
cat > /mnt/etc/fstab << EOF
/dev/sda2  /      ext4  defaults  0 1
/dev/sda1  /boot  ext4  defaults  0 2
EOF

# Unmount and reboot
umount -R /mnt
reboot
```

## Installer (Interactive and Unattended)

MixOS includes an interactive terminal installer (`mixos-install`) which is run on first boot if present. The installer also supports an unattended YAML configuration file for automated installations.

Files of interest:
- `packaging/install.yaml` — repository sample config used by `make iso-autoinstall`.
- `/etc/mixos/install.yaml` — path on the live image used by the autoinstall runner.

Autoinstall options can also be passed via the kernel command line:
- `mixos.autoinstall=1` — enable autoinstall
- `mixos.config=/path/to/install.yaml` — path to config file (e.g. `/etc/mixos/install.yaml`)

Example: boot an automatic install from GRUB or VM kernel args:

```
console=tty0 console=ttyS0,115200 mixos.autoinstall=1 mixos.config=/etc/mixos/install.yaml
```

Config schema (YAML, concise):

```yaml
hostname: myhost
root_password: "plain-or-hint"
# or provide a precomputed hash:
root_password_hash: "$6$..."
create_user:
    name: user
    password: "userpass"
    password_hash: "..."
    sudo: true
network:
    mode: dhcp # or static
    interface: eth0
    address: 192.168.1.100/24
    gateway: 192.168.1.1
    nameservers: [8.8.8.8, 1.1.1.1]
packages:
    - base-files
    - openssh
post_install_scripts:
    - |
        echo "post install"
```

Security notes:
- Prefer hashed passwords when embedding configs. The installer accepts plaintext and uses `chpasswd` if available; providing a hash will attempt to write `/etc/shadow` directly (best-effort).
- Do not include secrets in public ISOs.

Building an unattended ISO

```bash
# Build unattended ISO using the repository sample:
make iso-autoinstall

# Or embed your own config file:
INSTALL_CONFIG=/abs/path/to/install.yaml make iso
```

CI validation

The CI workflow performs a dry-run of the installer to validate parsing and basic operations. This does not execute destructive actions — it runs `mixos-install --config packaging/install.yaml --dry-run` as part of the build.


## Post-Installation Setup

### 1. Set Root Password (Optional)
```bash
passwd root
```

### 2. Configure SSH Access
```bash
# Generate SSH keys on your local machine
ssh-keygen -t ed25519

# Copy public key to MixOS
mkdir -p /root/.ssh
echo "your-public-key" >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Start SSH daemon
/etc/init.d/sshd start
```

### 3. Configure Network
```bash
# DHCP (automatic)
udhcpc -i eth0

# Static IP
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### 4. Update Package Database
```bash
mix update
```

### 5. Install Additional Packages
```bash
mix install openssh nginx
```

## Troubleshooting

### Boot Issues

**Problem**: System doesn't boot
- Verify ISO integrity with checksum
- Try different boot mode (BIOS/UEFI)
- Check boot order in BIOS

**Problem**: Kernel panic
- Boot with `init=/bin/sh` to get shell
- Check for hardware compatibility

### Network Issues

**Problem**: No network connectivity
```bash
# Check interface
ip link show

# Bring up interface
ip link set eth0 up

# Try DHCP
udhcpc -i eth0
```

### SSH Issues

**Problem**: Can't connect via SSH
```bash
# Check SSH is running
ps aux | grep sshd

# Start SSH
/etc/init.d/sshd start

# Check firewall
iptables -L -n
```

## Getting Help

- Documentation: `/usr/share/doc/mixos/`
- Issue tracker: https://github.com/mixos-go/issues
