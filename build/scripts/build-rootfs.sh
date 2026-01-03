#!/bin/bash
# MixOS-GO Root Filesystem Build Script
# Creates the base root filesystem with BusyBox and essential files

set -e

BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
ROOTFS_DIR="$BUILD_DIR/rootfs"
BUSYBOX_VERSION="1.36.1"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

echo "=== MixOS-GO Root Filesystem Build ==="
echo "Build Directory: $BUILD_DIR"
echo "Rootfs Directory: $ROOTFS_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo ""

# Create directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Clean previous rootfs
rm -rf "$ROOTFS_DIR"

# Create standard Linux directory structure
echo "Creating directory structure..."
mkdir -p "$ROOTFS_DIR"/{bin,sbin,usr/{bin,sbin,lib,share},lib,lib64}
mkdir -p "$ROOTFS_DIR"/{etc/{init.d,network,ssh,sysctl.d,iptables,profile.d},var/{log,run,lock,tmp,cache,lib/mix}}
mkdir -p "$ROOTFS_DIR"/{proc,sys,dev,tmp,root,home,mnt,opt,srv}
mkdir -p "$ROOTFS_DIR"/run/{lock,sshd}

# Set permissions
chmod 1777 "$ROOTFS_DIR/tmp"
chmod 1777 "$ROOTFS_DIR/var/tmp"
chmod 700 "$ROOTFS_DIR/root"

# Download and build BusyBox
BUSYBOX_TARBALL="$BUILD_DIR/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_SRC="$BUILD_DIR/busybox-${BUSYBOX_VERSION}"

if [ ! -f "$BUSYBOX_TARBALL" ]; then
    echo "Downloading BusyBox $BUSYBOX_VERSION..."
    curl -L -o "$BUSYBOX_TARBALL" "$BUSYBOX_URL"
fi

if [ ! -d "$BUSYBOX_SRC" ]; then
    echo "Extracting BusyBox..."
    tar -xf "$BUSYBOX_TARBALL" -C "$BUILD_DIR"
fi

# Get the repository root directory (where the script was called from)
REPO_ROOT="$(pwd)"
PATCH_DIR="$REPO_ROOT/build/patches"

echo "Repository root: $REPO_ROOT"
echo "Patch directory: $PATCH_DIR"

cd "$BUSYBOX_SRC"

# Apply patches
if [ -d "$PATCH_DIR" ]; then
    for patch in "$PATCH_DIR"/busybox-*.patch; do
        if [ -f "$patch" ]; then
            echo "Applying patch: $(basename "$patch")"
            patch -p1 < "$patch" || echo "Patch may already be applied or failed"
        fi
    done
else
    echo "Warning: Patch directory not found at $PATCH_DIR"
    ls -la "$REPO_ROOT/build/" || true
fi

# Configure BusyBox for static build
echo "Configuring BusyBox..."
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
sed -i 's/CONFIG_FEATURE_SH_STANDALONE=y/# CONFIG_FEATURE_SH_STANDALONE is not set/' .config

# Build BusyBox
echo "Building BusyBox..."
make -j"$(nproc)"

# Install BusyBox
echo "Installing BusyBox..."
make CONFIG_PREFIX="$ROOTFS_DIR" install

# Create essential device nodes (will be populated by devtmpfs at boot)
echo "Creating device nodes..."
mkdir -p "$ROOTFS_DIR/dev"
# Note: actual device nodes created at boot by devtmpfs

# Create /etc/fstab
cat > "$ROOTFS_DIR/etc/fstab" << 'EOF'
# MixOS-GO /etc/fstab
# <file system>  <mount point>  <type>  <options>         <dump>  <pass>
proc             /proc          proc    defaults          0       0
sysfs            /sys           sysfs   defaults          0       0
devtmpfs         /dev           devtmpfs defaults         0       0
devpts           /dev/pts       devpts  gid=5,mode=620    0       0
tmpfs            /tmp           tmpfs   defaults,noexec   0       0
tmpfs            /run           tmpfs   defaults,noexec   0       0
EOF

# Create /etc/hostname
echo "mixos" > "$ROOTFS_DIR/etc/hostname"

# Create /etc/hosts
cat > "$ROOTFS_DIR/etc/hosts" << 'EOF'
127.0.0.1       localhost
127.0.1.1       mixos
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Create /etc/resolv.conf
cat > "$ROOTFS_DIR/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Create /etc/os-release
cat > "$ROOTFS_DIR/etc/os-release" << 'EOF'
NAME="MixOS-GO"
VERSION="1.0.0"
ID=mixos
ID_LIKE=alpine
VERSION_ID=1.0.0
PRETTY_NAME="MixOS-GO v1.0.0"
HOME_URL="https://github.com/mixos-go"
BUG_REPORT_URL="https://github.com/mixos-go/issues"
EOF

# Create /etc/issue
cat > "$ROOTFS_DIR/etc/issue" << 'EOF'
MixOS-GO v1.0.0 - Minimal Linux Distribution

Welcome to MixOS-GO!

Kernel \r on \m (\l)

EOF

# Create /etc/motd
cat > "$ROOTFS_DIR/etc/motd" << 'EOF'

🧡 Welcome to MixOS-GO v1.0.0!

Quick Start:
  mix --help          Show package manager help
  mix setup           Run interactive setup wizard
  mix welcome         Show welcome screen
  mix list            List installed packages
  mix search <pkg>    Search for packages
  mix install <pkg>   Install a package
  mixmagisk <cmd>     Run command as root

Boot Modes:
  VRAM=auto           Boot entire system from RAM
  SDISK=name.viso     Boot from specific VISO

Documentation: /usr/share/doc/mixos/

EOF

# Create /etc/profile
cat > "$ROOTFS_DIR/etc/profile" << 'EOF'
# MixOS-GO System Profile

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERM="${TERM:-linux}"
export PAGER="${PAGER:-less}"
export EDITOR="${EDITOR:-vi}"
export LANG="${LANG:-C.UTF-8}"

# Load profile.d scripts
if [ -d /etc/profile.d ]; then
    for script in /etc/profile.d/*.sh; do
        [ -r "$script" ] && . "$script"
    done
    unset script
fi

# Set prompt
if [ "$(id -u)" -eq 0 ]; then
    PS1='\[\033[01;31m\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
else
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ '
fi

# Aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
EOF

# Create init script (simple init for BusyBox)
cat > "$ROOTFS_DIR/etc/inittab" << 'EOF'
# MixOS-GO /etc/inittab

# System initialization
::sysinit:/etc/init.d/rcS

# Start getty on serial and consoles
# Serial (common CI / VM serial device)
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
# Fallback to /dev/console for environments expecting a "console" device
::respawn:/sbin/getty -L console 115200 vt100

# Stuff to do before rebooting
::shutdown:/etc/init.d/rcK
::ctrlaltdel:/sbin/reboot
EOF

# Create rcS (startup script)
cat > "$ROOTFS_DIR/etc/init.d/rcS" << 'EOF'
#!/bin/sh
# MixOS-GO System Startup Script

echo "Starting MixOS-GO..."

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /dev/shm
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run

# Set hostname
hostname -F /etc/hostname

# Load kernel modules
if [ -d /lib/modules ]; then
    for mod in /lib/modules/*/modules.dep; do
        if [ -f "$mod" ]; then
            depmod -a
            break
        fi
    done
fi

# Apply sysctl settings
if [ -d /etc/sysctl.d ]; then
    for conf in /etc/sysctl.d/*.conf; do
        [ -f "$conf" ] && sysctl -p "$conf" 2>/dev/null
    done
fi

# Configure networking
echo "Configuring network..."
ip link set lo up
ip link set eth0 up 2>/dev/null || true
udhcpc -i eth0 -s /etc/network/udhcpc.script -q 2>/dev/null || true

# Apply iptables rules
if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
fi

# Start services
for script in /etc/init.d/S*; do
    [ -x "$script" ] && "$script" start
done

# Display login prompt
clear
cat /etc/issue
echo ""
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/rcS"

# Create rcK (shutdown script)
cat > "$ROOTFS_DIR/etc/init.d/rcK" << 'EOF'
#!/bin/sh
# MixOS-GO System Shutdown Script

echo "Shutting down MixOS-GO..."

# Stop services
for script in /etc/init.d/K*; do
    [ -x "$script" ] && "$script" stop
done

# Sync filesystems
sync

# Unmount filesystems
umount -a -r 2>/dev/null

echo "System halted."
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/rcK"

# Create udhcpc script
mkdir -p "$ROOTFS_DIR/etc/network"
cat > "$ROOTFS_DIR/etc/network/udhcpc.script" << 'EOF'
#!/bin/sh
# udhcpc script for MixOS-GO

case "$1" in
    deconfig)
        ip addr flush dev "$interface"
        ip link set "$interface" up
        ;;
    renew|bound)
        ip addr add "$ip/$mask" dev "$interface"
        if [ -n "$router" ]; then
            ip route add default via "$router" dev "$interface"
        fi
        if [ -n "$dns" ]; then
            echo -n > /etc/resolv.conf
            for ns in $dns; do
                echo "nameserver $ns" >> /etc/resolv.conf
            done
        fi
        ;;
esac
EOF
chmod +x "$ROOTFS_DIR/etc/network/udhcpc.script"

# Create SSH startup script
cat > "$ROOTFS_DIR/etc/init.d/S50sshd" << 'EOF'
#!/bin/sh
# SSH daemon startup script

SSHD=/usr/sbin/sshd
PIDFILE=/run/sshd.pid

case "$1" in
    start)
        echo "Starting SSH daemon..."
        # Generate host keys if missing
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" 2>/dev/null
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" 2>/dev/null
        fi
        mkdir -p /run/sshd
        $SSHD
        ;;
    stop)
        echo "Stopping SSH daemon..."
        [ -f $PIDFILE ] && kill $(cat $PIDFILE)
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/S50sshd"

# Apply security hardening
if [ -f "$(pwd)/configs/security/hardening.sh" ]; then
    echo "Applying security hardening..."
    bash "$(pwd)/configs/security/hardening.sh" "$ROOTFS_DIR"
fi

# Install kernel modules if available
if [ -f "$OUTPUT_DIR/modules-mixos.tar.gz" ]; then
    echo "Installing kernel modules..."
    tar -xzf "$OUTPUT_DIR/modules-mixos.tar.gz" -C "$ROOTFS_DIR"
fi

# Copy mix CLI if available
if [ -f "$OUTPUT_DIR/mix" ]; then
    echo "Installing mix package manager..."
    cp "$OUTPUT_DIR/mix" "$ROOTFS_DIR/usr/bin/mix"
    chmod +x "$ROOTFS_DIR/usr/bin/mix"
    
    # Create mixmagisk symlink
    ln -sf mix "$ROOTFS_DIR/usr/bin/mixmagisk"
fi

# Copy installer if available
if [ -f "$OUTPUT_DIR/mixos-install" ]; then
    echo "Installing mixos installer..."
    cp "$OUTPUT_DIR/mixos-install" "$ROOTFS_DIR/usr/bin/mixos-install"
    chmod +x "$ROOTFS_DIR/usr/bin/mixos-install"
fi

# Create installer configuration directory and sample config
mkdir -p "$ROOTFS_DIR/etc/mixos"
cat > "$ROOTFS_DIR/etc/mixos/install.yaml.sample" << 'EOF'
# MixOS installer sample configuration (YAML)
hostname: mixos-host
# Either provide plaintext passwords (will be hashed by system) or provide a precomputed hash.
root_password: "changeme"
#root_password_hash: "$6$..."
create_user:
    name: demo
    password: "demo"
    sudo: true
network:
    mode: dhcp
    interface: eth0
packages:
    - base-files
    - openssh
post_install_scripts:
    - |
        echo "Post-install script running"
EOF

# First-boot init script (runs installer on first boot if present)
cat > "$ROOTFS_DIR/etc/init.d/S10firstboot" << 'EOF'
#!/bin/sh
# MixOS firstboot installer hook

MARKER=/var/lib/mixos/firstboot_done
if [ -f "$MARKER" ]; then
        exit 0
fi

if [ -x /usr/bin/mixos-install ]; then
        if [ -f /etc/mixos/install.yaml ]; then
                echo "Running unattended installer from /etc/mixos/install.yaml"
                /usr/bin/mixos-install --config /etc/mixos/install.yaml || true
        else
                # Run interactive installer if console available
                if [ -c /dev/tty1 ] || [ -t 1 ]; then
                        echo "Starting interactive installer"
                        /usr/bin/mixos-install || true
                else
                        echo "No installer config and no interactive console; skipping installer"
                fi
        fi
fi

mkdir -p /var/lib/mixos
touch "$MARKER"
exit 0
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/S10firstboot"

# Ensure marker dir exists on image
mkdir -p "$ROOTFS_DIR/var/lib/mixos"

# Optionally copy a provided install.yaml into the image for unattended ISOs.
# Set INSTALL_CONFIG to an absolute path to a YAML file, or place a
# packaging/install.yaml file in the repository.
if [ -n "$INSTALL_CONFIG" ] && [ -f "$INSTALL_CONFIG" ]; then
    echo "Copying provided installer config: $INSTALL_CONFIG -> /etc/mixos/install.yaml"
    cp "$INSTALL_CONFIG" "$ROOTFS_DIR/etc/mixos/install.yaml"
    chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
elif [ -f "$(pwd)/packaging/install.yaml" ]; then
    echo "Copying packaging/install.yaml -> /etc/mixos/install.yaml"
    cp "$(pwd)/packaging/install.yaml" "$ROOTFS_DIR/etc/mixos/install.yaml"
    chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
fi

# Create package database directory
mkdir -p "$ROOTFS_DIR/var/lib/mix"

# Create documentation directory
mkdir -p "$ROOTFS_DIR/usr/share/doc/mixos"

# ============================================================================
# MixMagisk Setup
# ============================================================================
echo "Setting up MixMagisk..."

# Create mixmagisk directories
mkdir -p "$ROOTFS_DIR/etc/mixmagisk/policy.d"
mkdir -p "$ROOTFS_DIR/var/log"
mkdir -p "$ROOTFS_DIR/run/mixmagisk"

# Create default mixmagisk config
cat > "$ROOTFS_DIR/etc/mixmagisk/config" << 'EOF'
# MixMagisk Configuration
# MixOS Root Management System

[general]
version = 1.0.0
log_level = info
session_timeout = 300

[security]
require_password = true
allow_root_shell = true
audit_all_commands = true

[defaults]
default_policy = deny
allow_wheel_group = true
allow_mixmagisk_group = true
EOF

# Create root user policy
cat > "$ROOTFS_DIR/etc/mixmagisk/policy.d/root.policy" << 'EOF'
# MixMagisk Policy for root
# Root user always has full access

[user]
name = root
allow_root = true
require_pin = false
log_level = info
timeout = 0

[commands]
allow = *

[restrictions]
# No restrictions for root
EOF

# Create default user policy template
cat > "$ROOTFS_DIR/etc/mixmagisk/policy.d/default.policy.template" << 'EOF'
# MixMagisk Policy Template
# Copy this file to <username>.policy and customize

[user]
name = USERNAME
allow_root = true
require_pin = false
log_level = info
timeout = 300

[commands]
# Allow all commands (use specific patterns to restrict)
allow = *

[restrictions]
# Deny dangerous commands
deny = rm -rf /
deny = dd if=/dev/zero of=/dev/sda
deny = mkfs.*
EOF

# ============================================================================
# First Boot Setup
# ============================================================================
echo "Creating first boot setup..."

# Create first boot script
cat > "$ROOTFS_DIR/etc/init.d/S01firstboot" << 'EOF'
#!/bin/sh
# MixOS-GO First Boot Setup

FIRSTBOOT_FLAG="/var/lib/mix/.firstboot_done"

if [ -f "$FIRSTBOOT_FLAG" ]; then
    exit 0
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     🧡 Welcome to MixOS-GO First Boot!                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check boot mode
if grep -q "mixos.mode=installer" /proc/cmdline 2>/dev/null; then
    echo "Installer mode detected..."
    echo "Run 'mix setup' to start the setup wizard"
fi

# Check VRAM mode
if grep -q "VRAM=" /proc/cmdline 2>/dev/null; then
    mkdir -p /run/mixos
    touch /run/mixos/vram
    echo "⚡ VRAM mode enabled - System running from RAM"
fi

# Create firstboot flag
mkdir -p /var/lib/mix
touch "$FIRSTBOOT_FLAG"

echo ""
echo "Run 'mix welcome' for an interactive welcome screen"
echo "Run 'mix setup' to configure your system"
echo ""
EOF
chmod +x "$ROOTFS_DIR/etc/init.d/S01firstboot"

# ============================================================================
# Profile Scripts
# ============================================================================
echo "Creating profile scripts..."

# Create mixos profile script
cat > "$ROOTFS_DIR/etc/profile.d/mixos.sh" << 'EOF'
# MixOS-GO Profile Script

# Check if running in VRAM mode
if [ -f /run/mixos/vram ]; then
    export MIXOS_VRAM=1
    export PS1_PREFIX="⚡"
fi

# Set MixOS-specific environment
export MIXOS_VERSION="1.0.0"
export MIXOS_HOME="/var/lib/mix"

# Aliases for MixOS commands
alias setup='mix setup'
alias welcome='mix welcome'
alias su='mixmagisk -i'

# Show welcome message on first login
if [ ! -f "$HOME/.mixos_welcomed" ] && [ -t 0 ]; then
    echo ""
    echo "🧡 Welcome to MixOS-GO!"
    echo "   Run 'mix welcome' for the full welcome experience"
    echo "   Run 'mix help' for available commands"
    echo ""
    touch "$HOME/.mixos_welcomed" 2>/dev/null || true
fi
EOF

# ============================================================================
# User Management
# ============================================================================
echo "Setting up user management..."

# Create passwd file
cat > "$ROOTFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

# Create shadow file (root with no password initially)
cat > "$ROOTFS_DIR/etc/shadow" << 'EOF'
root::0:0:99999:7:::
nobody:*:0:0:99999:7:::
EOF
chmod 600 "$ROOTFS_DIR/etc/shadow"

# Create group file
cat > "$ROOTFS_DIR/etc/group" << 'EOF'
root:x:0:
wheel:x:10:
mixmagisk:x:100:
users:x:100:
nobody:x:65534:
EOF

# Create gshadow file
cat > "$ROOTFS_DIR/etc/gshadow" << 'EOF'
root:::
wheel:::
mixmagisk:::
users:::
nobody:::
EOF
chmod 600 "$ROOTFS_DIR/etc/gshadow"

# ============================================================================
# VRAM/VISO Support Files
# ============================================================================
echo "Creating VRAM/VISO support files..."

mkdir -p "$ROOTFS_DIR/run/mixos"

# Create VRAM status script
cat > "$ROOTFS_DIR/usr/bin/vram-status" << 'EOF'
#!/bin/sh
# MixOS VRAM Status Script

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS VRAM Status                                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if VRAM mode is active
if [ -f /run/mixos/vram ]; then
    echo "  Mode:     ⚡ VRAM (Active)"
else
    echo "  Mode:     💿 Standard"
fi

# Memory info
MEM_TOTAL=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo)
MEM_FREE=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_FREE))

echo "  RAM:      ${MEM_USED}MB / ${MEM_TOTAL}MB"

# Disk info
if [ -f /run/mixos/vram ]; then
    TMPFS_SIZE=$(df -h /run 2>/dev/null | tail -1 | awk '{print $2}')
    TMPFS_USED=$(df -h /run 2>/dev/null | tail -1 | awk '{print $3}')
    echo "  VRAM:     ${TMPFS_USED} / ${TMPFS_SIZE}"
fi

echo ""
EOF
chmod +x "$ROOTFS_DIR/usr/bin/vram-status"

# Calculate rootfs size
ROOTFS_SIZE=$(du -sh "$ROOTFS_DIR" | cut -f1)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Root Filesystem Build Complete!                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Rootfs: $ROOTFS_DIR ($ROOTFS_SIZE)"
echo ""
echo "  Features:"
echo "    ✓ BusyBox utilities"
echo "    ✓ MixMagisk root management"
echo "    ✓ VRAM/VISO support"
echo "    ✓ First boot setup"
echo "    ✓ User management"
echo ""
echo "Directory structure:"
ls -la "$ROOTFS_DIR"
