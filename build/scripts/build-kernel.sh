#!/bin/bash
# MixOS-GO Kernel Build Script
# Downloads and compiles Linux kernel 6.6.8

set -e

KERNEL_VERSION="6.6.8"
KERNEL_MAJOR="6"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
CONFIG_FILE="${CONFIG_FILE:-$(pwd)/configs/kernel/mixos_defconfig}"
JOBS="${JOBS:-$(nproc)}"

echo "=== MixOS-GO Kernel Build ==="
echo "Kernel Version: $KERNEL_VERSION"
echo "Build Directory: $BUILD_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Config File: $CONFIG_FILE"
echo "Parallel Jobs: $JOBS"
echo ""

# Create directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Download kernel source if not present
KERNEL_TARBALL="$BUILD_DIR/linux-${KERNEL_VERSION}.tar.xz"
KERNEL_SRC="$BUILD_DIR/linux-${KERNEL_VERSION}"

if [ ! -f "$KERNEL_TARBALL" ]; then
    echo "Downloading Linux kernel $KERNEL_VERSION..."
    curl -L -o "$KERNEL_TARBALL" "$KERNEL_URL"
fi

# Extract kernel source
if [ ! -d "$KERNEL_SRC" ]; then
    echo "Extracting kernel source..."
    tar -xf "$KERNEL_TARBALL" -C "$BUILD_DIR"
fi

cd "$KERNEL_SRC"

# Clean previous build
echo "Cleaning previous build..."
make mrproper

# Copy configuration
echo "Applying MixOS kernel configuration..."
cp "$CONFIG_FILE" .config

# Update config with defaults for any new options
make olddefconfig

# Build kernel
echo "Building kernel (this may take a while)..."
make -j"$JOBS" bzImage

# Build modules
echo "Building kernel modules..."
make -j"$JOBS" modules

# Install modules to temporary directory
MODULES_DIR="$BUILD_DIR/modules"
rm -rf "$MODULES_DIR"
mkdir -p "$MODULES_DIR"
make INSTALL_MOD_PATH="$MODULES_DIR" modules_install

# Copy kernel image
echo "Copying kernel image..."
cp arch/x86/boot/bzImage "$OUTPUT_DIR/vmlinuz-mixos"

# Copy System.map
cp System.map "$OUTPUT_DIR/System.map-mixos"

# Create modules tarball
echo "Creating modules tarball..."
cd "$MODULES_DIR"
tar -czf "$OUTPUT_DIR/modules-mixos.tar.gz" lib/

# Get kernel size
KERNEL_SIZE=$(du -h "$OUTPUT_DIR/vmlinuz-mixos" | cut -f1)
echo ""
echo "=== Kernel Build Complete ==="
echo "Kernel: $OUTPUT_DIR/vmlinuz-mixos ($KERNEL_SIZE)"
echo "Modules: $OUTPUT_DIR/modules-mixos.tar.gz"
echo "System.map: $OUTPUT_DIR/System.map-mixos"

# Verify kernel size target
KERNEL_SIZE_BYTES=$(stat -c%s "$OUTPUT_DIR/vmlinuz-mixos")
KERNEL_SIZE_MB=$((KERNEL_SIZE_BYTES / 1024 / 1024))
if [ "$KERNEL_SIZE_MB" -lt 15 ]; then
    echo "✓ Kernel size ($KERNEL_SIZE_MB MB) is within target (<15MB)"
else
    echo "⚠ Kernel size ($KERNEL_SIZE_MB MB) exceeds target (<15MB)"
fi
