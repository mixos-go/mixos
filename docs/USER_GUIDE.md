# MixOS-GO User Guide

## Overview

MixOS-GO is a minimal Linux distribution designed for servers and embedded systems. It features a custom package manager (`mix`) and security-hardened defaults.

## Package Manager (mix)

### Basic Commands

```bash
# Show help
mix --help

# Show version
mix --version

# Update package database
mix update

# Search for packages
mix search <query>

# Install packages
mix install <package> [package2...]

# Remove packages
mix remove <package>

# List installed packages
mix list

# List all available packages
mix list --all

# Show package information
mix info <package>

# Show package files
mix info --files <package>

# Upgrade packages
mix upgrade [package]
```

### Examples

```bash
# Install OpenSSH
mix install openssh

# Install multiple packages
mix install nginx curl vim

# Search for network tools
mix search network

# Remove a package
mix remove nginx

# Upgrade all packages
mix upgrade

# Upgrade specific package
mix upgrade openssh
```

### Package Installation Options

```bash
# Skip confirmation prompt
mix install -y openssh

# Skip dependency resolution
mix install --no-deps mypackage

# Verbose output
mix -v install openssh
```

## System Administration

### Service Management

Services are managed through init scripts in `/etc/init.d/`:

```bash
# Start a service
/etc/init.d/sshd start

# Stop a service
/etc/init.d/sshd stop

# Restart a service
/etc/init.d/sshd restart
```

### Network Configuration

#### DHCP
```bash
udhcpc -i eth0
```

#### Static IP
```bash
# Set IP address
ip addr add 192.168.1.100/24 dev eth0

# Set default gateway
ip route add default via 192.168.1.1

# Configure DNS
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

#### View Network Status
```bash
ip addr show
ip route show
cat /etc/resolv.conf
```

### Firewall (iptables)

```bash
# View current rules
iptables -L -n -v

# Load saved rules
/etc/init.d/iptables start

# Save current rules
/etc/init.d/iptables save

# Allow additional port (e.g., HTTP)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# Block an IP
iptables -A INPUT -s 192.168.1.100 -j DROP
```

### SSH Configuration

SSH is configured for key-only authentication by default.

```bash
# Add authorized key
mkdir -p ~/.ssh
echo "ssh-ed25519 AAAA... user@host" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# Start SSH daemon
/etc/init.d/sshd start

# Generate host keys (if needed)
ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
```

### User Management

```bash
# Add user
adduser username

# Set password
passwd username

# Add user to group
addgroup username wheel

# Delete user
deluser username
```

### System Information

```bash
# Kernel version
uname -a

# Memory usage
free -m

# Disk usage
df -h

# CPU info
cat /proc/cpuinfo

# Running processes
ps aux

# System uptime
uptime
```

## File System

### Directory Structure

```
/
├── bin/          # Essential binaries
├── sbin/         # System binaries
├── usr/
│   ├── bin/      # User binaries
│   ├── sbin/     # System admin binaries
│   ├── lib/      # Libraries
│   └── share/    # Shared data
├── etc/          # Configuration files
├── var/
│   ├── log/      # Log files
│   ├── lib/      # Variable data
│   └── cache/    # Cache files
├── tmp/          # Temporary files
├── root/         # Root home directory
├── home/         # User home directories
├── proc/         # Process information
├── sys/          # System information
└── dev/          # Device files
```

### Important Files

| File | Description |
|------|-------------|
| `/etc/passwd` | User accounts |
| `/etc/shadow` | Password hashes |
| `/etc/group` | Group definitions |
| `/etc/hostname` | System hostname |
| `/etc/hosts` | Host name resolution |
| `/etc/resolv.conf` | DNS configuration |
| `/etc/fstab` | Filesystem mounts |
| `/etc/profile` | Shell profile |
| `/etc/ssh/sshd_config` | SSH server config |
| `/etc/iptables/rules.v4` | Firewall rules |

## Logging

### System Logs

```bash
# View kernel messages
dmesg

# View system log
cat /var/log/messages

# Follow log in real-time
tail -f /var/log/messages
```

### Log Files

| Log | Description |
|-----|-------------|
| `/var/log/messages` | General system log |
| `/var/log/auth.log` | Authentication log |
| `/var/log/kern.log` | Kernel log |

## Performance Tuning

### Sysctl Parameters

View current settings:
```bash
sysctl -a
```

Modify settings:
```bash
# Temporary
sysctl -w net.ipv4.ip_forward=1

# Permanent (add to /etc/sysctl.d/99-custom.conf)
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.d/99-custom.conf
```

### Memory Management

```bash
# Clear page cache
sync; echo 3 > /proc/sys/vm/drop_caches

# View memory info
cat /proc/meminfo
```

## Troubleshooting

### Common Issues

**Package installation fails**
```bash
# Update database first
mix update

# Check disk space
df -h

# Try verbose mode
mix -v install package
```

**Service won't start**
```bash
# Check if already running
ps aux | grep servicename

# Check logs
dmesg | tail
cat /var/log/messages | tail
```

**Network not working**
```bash
# Check interface status
ip link show

# Bring up interface
ip link set eth0 up

# Check for IP
ip addr show eth0

# Test connectivity
ping 8.8.8.8
```

### Recovery Mode

Boot with kernel parameter `init=/bin/sh` for emergency shell.

```bash
# Remount root as read-write
mount -o remount,rw /

# Fix issues...

# Reboot
sync
reboot -f
```
