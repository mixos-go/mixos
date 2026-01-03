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

# Wait for devices to settle (give CD-ROM more time to appear)
sleep 15

mkdir -p /mnt/cdrom /mnt/root

# Helper to attempt mounting a device as ISO9660 with retries
try_mount_iso() {
    local dev="$1"
    local i
    for i in 1 2 3 4 5; do
        if [ -b "$dev" ]; then
            echo "Trying to mount $dev (attempt $i)..."
            if mount -t iso9660 -o ro "$dev" /mnt/cdrom; then
                echo "Mounted $dev -> /mnt/cdrom"
                ls -l /mnt/cdrom || true
                return 0
            else
                echo "Mount failed for $dev (attempt $i)" >&2
            fi
        fi
        sleep 2
    done
    return 1
}

# Try common CD-ROM and block devices
for dev in /dev/sr0 /dev/cdrom /dev/hdc /dev/scd0 /dev/vda /dev/vdb /dev/sda /dev/sdb; do
    if try_mount_iso "$dev"; then
        break
    fi
done

# If mounted, look for filesystem.squashfs; also scan the mounted tree
if [ -d /mnt/cdrom ] && [ -f /mnt/cdrom/live/filesystem.squashfs ]; then
    echo "Found live filesystem at /mnt/cdrom/live/filesystem.squashfs, mounting..."
    mount -t squashfs -o ro /mnt/cdrom/live/filesystem.squashfs /mnt/root
else
    # Try to find filesystem.squashfs anywhere under /mnt/cdrom if mounted
    if [ -d /mnt/cdrom ]; then
        fs=$(find /mnt/cdrom -maxdepth 3 -type f -name filesystem.squashfs 2>/dev/null | head -n1 || true)
        if [ -n "$fs" ]; then
            echo "Found live filesystem at $fs, mounting..."
            mount -t squashfs -o ro "$fs" /mnt/root
        fi
    fi
fi

# If mounting didn't succeed, fall back to initramfs root
if [ ! -d /mnt/root ] || [ -z "$(ls -A /mnt/root 2>/dev/null)" ]; then
    echo "Live filesystem not found, using initramfs as root"
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
# Ensure filesystem buffers are flushed so xorriso/grub see final files
sync

# Prefer grub-mkrescue (works on many systems). If it fails or to avoid
# subtle truncation issues when mixing internal temp dirs, fall back to an
# explicit xorriso invocation that grafts exact files from $ISO_DIR.
if grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
    --product-name="MixOS-GO" \
    --product-version="1.0.0" 2>/dev/null; then
    true
else
    echo "grub-mkrescue failed or unavailable; using explicit xorriso graft-points..."
    # Use explicit graft-points so we control exact source files copied into the ISO
    if command -v xorriso >/dev/null 2>&1; then
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
            -graft-points \
                /boot/initramfs.img="$ISO_DIR/boot/initramfs.img" \
                /boot/vmlinuz="$ISO_DIR/boot/vmlinuz" \
                /boot/grub/grub.cfg="$ISO_DIR/boot/grub/grub.cfg" \
                /live="$ISO_DIR/live" \
            2>/dev/null || {
                echo "xorriso fallback failed; creating basic tarball instead..."
                cd "$ISO_DIR"
                tar -czf "$OUTPUT_DIR/mixos-go-v1.0.0.tar.gz" .
                echo "Created tarball instead: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
            }
    else
        echo "xorriso not installed; creating basic tarball instead..."
        cd "$ISO_DIR"
        tar -czf "$OUTPUT_DIR/mixos-go-v1.0.0.tar.gz" .
        echo "Created tarball instead: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
    fi
fi

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
