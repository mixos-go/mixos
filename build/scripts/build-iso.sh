#!/bin/bash
# ============================================================================
# MixOS-GO ISO Build Script
# Creates bootable ISO/VISO image with GRUB bootloader
# Supports: Traditional ISO, VISO, VRAM mode
# ============================================================================

set -e

BUILD_DIR="${BUILD_DIR:-/tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
ROOTFS_DIR="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
VERSION="${VERSION:-1.0.0}"
ISO_NAME="mixos-go-v${VERSION}.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO ISO Builder                                     ║"
echo "║     VISO/SDISK/VRAM Support                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log_info "Build Directory: $BUILD_DIR"
log_info "Rootfs Directory: $ROOTFS_DIR"
log_info "ISO Directory: $ISO_DIR"
log_info "Output: $OUTPUT_DIR/$ISO_NAME"
echo ""

# Verify prerequisites
if [ ! -d "$ROOTFS_DIR" ]; then
    log_error "Rootfs not found at $ROOTFS_DIR"
    log_info "Run build-rootfs.sh first"
    exit 1
fi

# Check for kernel (optional - can use enhanced initramfs)
KERNEL_PATH=""
if [ -f "$OUTPUT_DIR/boot/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/boot/vmlinuz-mixos"
elif [ -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/vmlinuz-mixos"
else
    log_warn "Kernel not found, will create ISO without kernel"
fi

# Check for enhanced initramfs
INITRAMFS_PATH=""
if [ -f "$OUTPUT_DIR/boot/initramfs-mixos.img" ]; then
    INITRAMFS_PATH="$OUTPUT_DIR/boot/initramfs-mixos.img"
    log_ok "Using enhanced initramfs with VISO/VRAM support"
fi

# Clean previous ISO build
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"/{boot/grub,live,config}

# ============================================================================
# Step 1: Prepare initramfs
# ============================================================================
log_info "Preparing initramfs..."

if [ -n "$INITRAMFS_PATH" ]; then
    # Use enhanced initramfs with VISO/VRAM support
    cp "$INITRAMFS_PATH" "$ISO_DIR/boot/initramfs.img"
    log_ok "Using enhanced initramfs"
else
    # Create basic initramfs from rootfs
    log_info "Creating basic initramfs from rootfs..."
    cd "$ROOTFS_DIR"

    # Create init script for initramfs
    cat > init << 'INITEOF'
#!/bin/sh
# MixOS-GO Init Script (Basic)

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Parse kernel command line
BOOT_DEV=""
ROOT_TYPE="squashfs"
VRAM_MODE=""
SDISK_VALUE=""

for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)
            BOOT_DEV="${param#root=}"
            ;;
        rootfstype=*)
            ROOT_TYPE="${param#rootfstype=}"
            ;;
        VRAM=*)
            VRAM_MODE="${param#VRAM=}"
            ;;
        SDISK=*)
            SDISK_VALUE="${param#SDISK=}"
            ;;
    esac
done

# Find and mount the live filesystem
echo "Searching for live filesystem..."

# Wait for devices
sleep 2

# Try to find the squashfs
mkdir -p /mnt/cdrom /mnt/root /mnt/vram

# Try virtio devices first (VISO)
for dev in /dev/vda /dev/vdb; do
    if [ -b "$dev" ]; then
        mount -o ro "$dev" /mnt/cdrom 2>/dev/null && break
    fi
done

# Try common CD-ROM devices
if [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
    for dev in /dev/sr0 /dev/cdrom /dev/hdc /dev/scd0; do
        if [ -b "$dev" ]; then
            mount -t iso9660 -o ro "$dev" /mnt/cdrom 2>/dev/null && break
        fi
    done
fi

# Also try SATA/IDE devices
if [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
    for dev in /dev/sda /dev/sdb; do
        if [ -b "$dev" ]; then
            mount -o ro "$dev" /mnt/cdrom 2>/dev/null || true
        fi
    done
fi

# Find squashfs
SQUASHFS_PATH=""
for path in /mnt/cdrom/live/filesystem.squashfs /mnt/cdrom/rootfs/rootfs.squashfs /mnt/cdrom/rootfs.squashfs; do
    if [ -f "$path" ]; then
        SQUASHFS_PATH="$path"
        break
    fi
done

# Mount squashfs
if [ -n "$SQUASHFS_PATH" ]; then
    echo "Found live filesystem: $SQUASHFS_PATH"
    
    # Check VRAM mode
    if [ "$VRAM_MODE" = "auto" ] || [ "$VRAM_MODE" = "1" ] || [ "$VRAM_MODE" = "yes" ]; then
        # Get available RAM
        MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
        if [ "$MEM_TOTAL" -ge 2048 ]; then
            echo "VRAM mode: Loading system into RAM..."
            mount -t tmpfs -o size=1G tmpfs /mnt/vram
            mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
            cp -a /mnt/root/* /mnt/vram/
            umount /mnt/root
            mount --bind /mnt/vram /mnt/root
            echo "VRAM mode: System loaded into RAM!"
        else
            mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
        fi
    else
        mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
    fi
else
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
    log_info "Packing initramfs..."
    find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$ISO_DIR/boot/initramfs.img"
    cd "$REPO_ROOT"
fi

# ============================================================================
# Step 2: Copy kernel
# ============================================================================
log_info "Copying kernel..."
if [ -n "$KERNEL_PATH" ]; then
    cp "$KERNEL_PATH" "$ISO_DIR/boot/vmlinuz"
    log_ok "Kernel copied"
else
    log_warn "No kernel found - ISO will not be bootable without external kernel"
fi

# ============================================================================
# Step 3: Create SquashFS from rootfs
# ============================================================================
log_info "Creating SquashFS filesystem..."
mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz \
    -b 1M \
    -Xdict-size 100% \
    -no-exports \
    -noappend \
    -no-recovery \
    -quiet

SQUASHFS_SIZE=$(du -h "$ISO_DIR/live/filesystem.squashfs" | cut -f1)
log_ok "SquashFS created: $SQUASHFS_SIZE"

# ============================================================================
# Step 4: Create ISO metadata
# ============================================================================
log_info "Creating ISO metadata..."

cat > "$ISO_DIR/config/iso.json" << EOF
{
    "name": "MixOS-GO",
    "version": "$VERSION",
    "format": "ISO",
    "created": "$(date -Iseconds)",
    "features": {
        "vram_support": true,
        "sdisk_boot": true,
        "installer": true
    },
    "boot": {
        "kernel": "boot/vmlinuz",
        "initramfs": "boot/initramfs.img",
        "cmdline": "console=ttyS0 quiet"
    }
}
EOF

# ============================================================================
# Step 5: Create GRUB configuration
# ============================================================================
log_info "Creating GRUB configuration..."
cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
# MixOS-GO GRUB Configuration
# Version: $VERSION

set timeout=10
set default=0

# Set colors
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

# Custom theme
insmod gfxterm
insmod png

menuentry "🚀 MixOS-GO v$VERSION (Installer)" {
    linux /boot/vmlinuz console=ttyS0 quiet mixos.mode=installer
    initrd /boot/initramfs.img
}

menuentry "⚡ MixOS-GO v$VERSION (VRAM Mode - Maximum Performance)" {
    linux /boot/vmlinuz console=ttyS0 VRAM=auto quiet
    initrd /boot/initramfs.img
}

menuentry "💿 MixOS-GO v$VERSION (Standard Boot)" {
    linux /boot/vmlinuz console=ttyS0 quiet console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

menuentry "🔧 MixOS-GO v$VERSION (Verbose)" {
    linux /boot/vmlinuz console=ttyS0
    initrd /boot/initramfs.img
}

menuentry "🛠️ MixOS-GO v$VERSION (Recovery Shell)" {
    linux /boot/vmlinuz console=ttyS0 single init=/bin/sh console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

menuentry "📖 MixOS-GO v$VERSION (Debug Mode)" {
    linux /boot/vmlinuz console=ttyS0 debug console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

# Automatic installer entry (uses /etc/mixos/install.yaml on the live image)
menuentry "MixOS-GO Automatic Install" {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200 mixos.autoinstall=1 mixos.config=/etc/mixos/install.yaml
    initrd /boot/initramfs.img
}
EOF

log_ok "GRUB configuration created"

# ============================================================================
# Step 6: Create ISO image
# ============================================================================
log_info "Creating ISO image..."

grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
    --product-name="MixOS-GO" \
    --product-version="$VERSION" \
    2>/dev/null || {
    # Fallback method using xorriso directly
    log_warn "grub-mkrescue failed, using xorriso fallback..."
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
            log_warn "xorriso failed, using genisoimage..."
            genisoimage -o "$OUTPUT_DIR/$ISO_NAME" \
                -b boot/grub/i386-pc/eltorito.img \
                -c boot/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -J -R -V "MIXOS_GO" \
                "$ISO_DIR" 2>/dev/null || {
                    log_warn "Creating tarball instead of ISO..."
                    cd "$ISO_DIR"
                    tar -czf "$OUTPUT_DIR/mixos-go-v${VERSION}.tar.gz" .
                    log_ok "Created tarball: mixos-go-v${VERSION}.tar.gz"
                }
        }
}

# ============================================================================
# Step 7: Generate checksums and summary
# ============================================================================
cd "$OUTPUT_DIR"
if [ -f "$ISO_NAME" ]; then
    log_info "Generating checksums..."
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    md5sum "$ISO_NAME" > "$ISO_NAME.md5"
    
    # Get ISO size
    ISO_SIZE=$(du -h "$ISO_NAME" | cut -f1)
    ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME")
    ISO_SIZE_MB=$((ISO_SIZE_BYTES / 1024 / 1024))
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     ISO Build Complete!                                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Output: $OUTPUT_DIR/$ISO_NAME ($ISO_SIZE)"
    echo "SHA256: $(cat $ISO_NAME.sha256 | cut -d' ' -f1)"
    echo ""
    
    # Verify size target
    if [ "$ISO_SIZE_MB" -lt 500 ]; then
        log_ok "ISO size ($ISO_SIZE_MB MB) is within target (<500MB)"
    else
        log_warn "ISO size ($ISO_SIZE_MB MB) exceeds target (<500MB)"
    fi
    
    echo ""
    echo "Boot options:"
    echo "  1. Installer Mode:  Boot and run MixOS Setup"
    echo "  2. VRAM Mode:       Maximum performance (requires 2GB+ RAM)"
    echo "  3. Standard Boot:   Normal boot from squashfs"
    echo "  4. Recovery Shell:  Emergency shell access"
    echo ""
    echo "QEMU test command:"
    echo "  qemu-system-x86_64 -cdrom $OUTPUT_DIR/$ISO_NAME -m 2G -nographic"
    echo ""
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Build Complete (tarball)                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Tarball: $OUTPUT_DIR/mixos-go-v${VERSION}.tar.gz"
    echo ""
fi
