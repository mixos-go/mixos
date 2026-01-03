#!/bin/bash
# Build script for openssh package
# Downloads pre-built OpenSSH from Alpine

set -e

PKG_NAME="openssh"
PKG_VERSION="9.6"
PKG_DESC="OpenSSH server and client"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build/packages/$PKG_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts/packages}"

echo "Building $PKG_NAME $PKG_VERSION..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# For a real build, we would compile OpenSSH
# For now, create a placeholder package with config files

mkdir -p files/etc/ssh
mkdir -p files/usr/sbin
mkdir -p files/usr/bin
mkdir -p files/etc/init.d
mkdir -p files/run/sshd

# Create sshd_config
cat > files/etc/ssh/sshd_config << 'EOF'
Port 22
AddressFamily any
ListenAddress 0.0.0.0
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
LoginGraceTime 30
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd yes
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# Create ssh_config
cat > files/etc/ssh/ssh_config << 'EOF'
Host *
    ForwardAgent no
    ForwardX11 no
    PasswordAuthentication no
    CheckHostIP yes
    StrictHostKeyChecking ask
    IdentityFile ~/.ssh/id_ed25519
    IdentityFile ~/.ssh/id_rsa
    Protocol 2
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
    KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
EOF

# Create init script
cat > files/etc/init.d/sshd << 'EOF'
#!/bin/sh
SSHD=/usr/sbin/sshd
PIDFILE=/run/sshd.pid

case "$1" in
    start)
        echo "Starting SSH daemon..."
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        fi
        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
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
chmod +x files/etc/init.d/sshd

# Create metadata
cat > metadata.json << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "$PKG_DESC",
  "dependencies": ["base-files", "openssl"],
  "files": [
    "/etc/ssh/sshd_config",
    "/etc/ssh/ssh_config",
    "/etc/init.d/sshd"
  ],
  "post_install": "#!/bin/sh\\nif [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then\\n  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' 2>/dev/null || true\\nfi"
}
EOF

# Create package
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/

echo "Package created: $OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg"
