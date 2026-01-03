#!/bin/bash
# Build script for iptables package

set -e

PKG_NAME="iptables"
PKG_VERSION="1.8.10"
PKG_DESC="Linux firewall administration tools"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build/packages/$PKG_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts/packages}"

echo "Building $PKG_NAME $PKG_VERSION..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# Create directory structure
mkdir -p files/etc/iptables
mkdir -p files/etc/init.d

# Create default iptables rules
cat > files/etc/iptables/rules.v4 << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (rate limited)
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT

# Allow ICMP ping (rate limited)
-A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT

# Log dropped packets
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4

COMMIT
EOF

cat > files/etc/iptables/rules.v6 << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m limit --limit 3/min --limit-burst 3 -j ACCEPT
-A INPUT -p ipv6-icmp -j ACCEPT

COMMIT
EOF

# Create init script
cat > files/etc/init.d/iptables << 'EOF'
#!/bin/sh
case "$1" in
    start)
        echo "Loading iptables rules..."
        if [ -f /etc/iptables/rules.v4 ]; then
            iptables-restore < /etc/iptables/rules.v4
        fi
        if [ -f /etc/iptables/rules.v6 ]; then
            ip6tables-restore < /etc/iptables/rules.v6 2>/dev/null || true
        fi
        ;;
    stop)
        echo "Flushing iptables rules..."
        iptables -F
        iptables -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        ;;
    save)
        echo "Saving iptables rules..."
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|save|restart}"
        exit 1
        ;;
esac
EOF
chmod +x files/etc/init.d/iptables

# Create metadata
cat > metadata.json << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "$PKG_DESC",
  "dependencies": ["base-files"],
  "files": [
    "/etc/iptables/rules.v4",
    "/etc/iptables/rules.v6",
    "/etc/init.d/iptables"
  ]
}
EOF

tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/

echo "Package created: $OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg"
