#!/bin/bash
# MixOS-GO ISO Build Script
# Creates bootable ISO image with GRUB bootloader

set -e

BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
ROOTFS_DIR="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
ISO_NAME="mixos-go-v1.0.0.iso"

echo "=== MixOS-GO ISO Build ==="
echo "Build Directory: $BUILD_DIR"
echo "Rootfs Directory: $ROOTFS_DIR"
echo "ISO Directory: $ISO_DIR"
echo "Output: $OUTPUT_DIR/$ISO_NAME"
echo ""

# Verify prerequisites
if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Rootfs not found at $ROOTFS_DIR"
    echo "Run build-rootfs.sh first"
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
    echo "Error: Kernel not found at $OUTPUT_DIR/vmlinuz-mixos"
    echo "Run build-kernel.sh first"
    exit 1
fi

# Clean previous ISO build
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"/{boot/grub,live}

# Create initramfs from rootfs
echo "Creating initramfs..."
cd "$ROOTFS_DIR"

# Create init script for initramfs
cat > init << 'INITEOF'
#!/bin/sh
# MixOS-GO Init Script

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Parse kernel command line
BOOT_DEV=""
ROOT_TYPE="squashfs"
for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)
            BOOT_DEV="${param#root=}"
            ;;
        rootfstype=*)
            ROOT_TYPE="${param#rootfstype=}"
            ;;
    esac
done

# Find and mount the live filesystem
echo "Searching for live filesystem..."

# Wait for devices
sleep 2

# Try to find the squashfs
mkdir -p /mnt/cdrom /mnt/root

# Try common CD-ROM devices
for dev in /dev/sr0 /dev/cdrom /dev/hdc /dev/scd0; do
    if [ -b "$dev" ]; then
        mount -t iso9660 -o ro "$dev" /mnt/cdrom 2>/dev/null && break
    fi
done

# Also try virtio block devices
for dev in /dev/vda /dev/vdb /dev/sda /dev/sdb; do
    if [ -b "$dev" ] && [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
        mount -t iso9660 -o ro "$dev" /mnt/cdrom 2>/dev/null || true
    fi
done

# Mount squashfs
if [ -f /mnt/cdrom/live/filesystem.squashfs ]; then
    echo "Found live filesystem, mounting..."
    mount -t squashfs -o ro /mnt/cdrom/live/filesystem.squashfs /mnt/root
else
    echo "Live filesystem not found, using initramfs as root"
    # Continue with initramfs as root
    exec /sbin/init
fi

# Switch to real root
echo "Switching to root filesystem..."
cd /mnt/root

# Move mounts
mkdir -p /mnt/root/mnt/cdrom
mount --move /mnt/cdrom /mnt/root/mnt/cdrom 2>/dev/null || true

# Pivot root
exec switch_root /mnt/root /sbin/init
INITEOF
chmod +x init

# Create initramfs cpio archive
echo "Packing initramfs..."
find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$ISO_DIR/boot/initramfs.img"

# Copy kernel
echo "Copying kernel..."
cp "$OUTPUT_DIR/vmlinuz-mixos" "$ISO_DIR/boot/vmlinuz"

# Create SquashFS from rootfs
echo "Creating SquashFS filesystem..."
mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz \
    -b 1M \
    -Xdict-size 100% \
    -no-exports \
    -noappend \
    -no-recovery

# Create GRUB configuration
echo "Creating GRUB configuration..."
cat > "$ISO_DIR/boot/grub/grub.cfg" << 'EOF'
# MixOS-GO GRUB Configuration

set timeout=5
set default=0

# Set colors
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "MixOS-GO v1.0.0" {
    linux /boot/vmlinuz quiet console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v1.0.0 (verbose)" {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v1.0.0 (recovery)" {
    linux /boot/vmlinuz single init=/bin/sh console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

# Automatic installer entry (uses /etc/mixos/install.yaml on the live image)
menuentry "MixOS-GO Automatic Install" {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200 mixos.autoinstall=1 mixos.config=/etc/mixos/install.yaml
    initrd /boot/initramfs.img
}
EOF

# Create ISO
echo "Creating ISO image..."
grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
    --product-name="MixOS-GO" \
    --product-version="1.0.0" \
    2>/dev/null || {
    # Fallback method using xorriso directly
    echo "Using xorriso fallback..."
    xorriso -as mkisofs \
        -o "$OUTPUT_DIR/$ISO_NAME" \
        -isohybrid-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -c boot/boot.cat \
        -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -V "MIXOS_GO" \
        "$ISO_DIR" 2>/dev/null || {
            # Simple ISO creation
            echo "Using simple ISO creation..."
            genisoimage -o "$OUTPUT_DIR/$ISO_NAME" \
                -b boot/grub/i386-pc/eltorito.img \
                -c boot/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -J -R -V "MIXOS_GO" \
                "$ISO_DIR" 2>/dev/null || {
                    echo "Creating basic ISO without bootloader..."
                    cd "$ISO_DIR"
                    tar -czf "$OUTPUT_DIR/mixos-go-v1.0.0.tar.gz" .
                    echo "Created tarball instead: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
                }
        }
}

# Generate checksums
cd "$OUTPUT_DIR"
if [ -f "$ISO_NAME" ]; then
    echo "Generating checksums..."
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    md5sum "$ISO_NAME" > "$ISO_NAME.md5"
    
    # Get ISO size
    ISO_SIZE=$(du -h "$ISO_NAME" | cut -f1)
    ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME")
    
    echo ""
    echo "=== ISO Build Complete ==="
    echo "ISO: $OUTPUT_DIR/$ISO_NAME ($ISO_SIZE)"
    echo "SHA256: $(cat $ISO_NAME.sha256)"
    echo ""
    
    # Verify size target
    ISO_SIZE_MB=$((ISO_SIZE_BYTES / 1024 / 1024))
    if [ "$ISO_SIZE_MB" -lt 500 ]; then
        echo "✓ ISO size ($ISO_SIZE_MB MB) is within target (<500MB)"
    else
        echo "⚠ ISO size ($ISO_SIZE_MB MB) exceeds target (<500MB)"
    fi
else
    echo ""
    echo "=== Build Complete (tarball) ==="
    echo "Tarball: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
fi
