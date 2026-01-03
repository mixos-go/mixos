#!/bin/bash
#set -e

PKG_NAME="mixos-installer"
PKG_VERSION="0.1.0"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build/packages/$PKG_NAME}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts/packages}"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/files/usr/bin"
mkdir -p "$OUTPUT_DIR"

# Build Go installer
cd "$(dirname "$0")/../../installer" || exit 1

if command -v go >/dev/null 2>&1; then
    echo "Building installer binary..."
    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$BUILD_DIR/files/usr/bin/mixos-install" .
else
    echo "Go toolchain not found. Please build 'mixos-install' and place it in $BUILD_DIR/files/usr/bin"
fi

# Create metadata
cat > "$BUILD_DIR/metadata.json" << EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "Interactive MixOS installer (TUI)",
  "dependencies": [],
  "files": [
    "/usr/bin/mixos-install"
  ]
}
EOF

# Package
cd "$BUILD_DIR" || exit 1
tar -czf "$OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg" metadata.json files/

echo "Package created: $OUTPUT_DIR/${PKG_NAME}-${PKG_VERSION}.mixpkg"
