#!/bin/bash
# Build script for base-files package

set -e

PKG_NAME="base-files"
PKG_VERSION="1.0.0"
PKG_DESC="Base system files for MixOS-GO"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build/packages/$PKG_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts/packages}"

echo "Building $PKG_NAME $PKG_VERSION..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"
mkdir -p "$OUTPUT_DIR"

# Create directory structure
cd "$BUILD_DIR/files"
mkdir -p {bin,sbin,usr/{bin,sbin,lib,share/doc/mixos},lib,lib64}
mkdir -p {etc/{init.d,network,profile.d,sysctl.d},var/{log,run,lock,tmp,cache,lib}}
mkdir -p {proc,sys,dev,tmp,root,home,mnt,opt,srv,run}

# Create essential files
cat > etc/os-release << 'EOF'
NAME="MixOS-GO"
VERSION="1.0.0"
ID=mixos
ID_LIKE=alpine
VERSION_ID=1.0.0
PRETTY_NAME="MixOS-GO v1.0.0"
HOME_URL="https://github.com/mixos-go"
EOF

cat > etc/hostname << 'EOF'
mixos
EOF

cat > etc/hosts << 'EOF'
127.0.0.1       localhost
127.0.1.1       mixos
::1             localhost ip6-localhost ip6-loopback
EOF

cat > etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

cat > etc/fstab << 'EOF'
# MixOS-GO /etc/fstab
proc             /proc          proc    defaults          0       0
sysfs            /sys           sysfs   defaults          0       0
devtmpfs         /dev           devtmpfs defaults         0       0
tmpfs            /tmp           tmpfs   defaults,noexec   0       0
tmpfs            /run           tmpfs   defaults,noexec   0       0
EOF

cat > etc/profile << 'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERM="${TERM:-linux}"
export PAGER="${PAGER:-less}"
export EDITOR="${EDITOR:-vi}"
export LANG="${LANG:-C.UTF-8}"

if [ -d /etc/profile.d ]; then
    for script in /etc/profile.d/*.sh; do
        [ -r "$script" ] && . "$script"
    done
fi

if [ "$(id -u)" -eq 0 ]; then
    PS1='\h:\w# '
else
    PS1='\u@\h:\w$ '
fi

alias ll='ls -la'
alias la='ls -A'
EOF

cat > etc/shells << 'EOF'
/bin/sh
/bin/ash
/bin/bash
EOF

cat > etc/passwd << 'EOF'
root:x:0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

cat > etc/shadow << 'EOF'
root:!:19722:0:99999:7:::
daemon:*:19722:0:99999:7:::
bin:*:19722:0:99999:7:::
sys:*:19722:0:99999:7:::
nobody:*:19722:0:99999:7:::
EOF

cat > etc/group << 'EOF'
root:x:0:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
wheel:x:10:root
users:x:100:
nogroup:x:65534:
EOF

# Set permissions
chmod 600 etc/shadow
chmod 644 etc/passwd etc/group
chmod 1777 tmp var/tmp

# Create metadata
cd "$BUILD_DIR"
cat > metadata.json << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "$PKG_DESC",
  "dependencies": [],
  "files": [
    "/etc/os-release",
    "/etc/hostname",
    "/etc/hosts",
    "/etc/resolv.conf",
    "/etc/fstab",
    "/etc/profile",
    "/etc/shells",
    "/etc/passwd",
    "/etc/shadow",
    "/etc/group"
  ]
}
EOF

# Create package
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/

echo "Package created: $OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg"
