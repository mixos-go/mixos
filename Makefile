# MixOS-GO Build System
# Version 1.0.0 - VISO/SDISK/VRAM Support

SHELL := /bin/bash
.PHONY: all clean toolchain kernel mix-cli installer packages rootfs iso test help
.PHONY: initramfs viso sdisk vram modules-dep test-vram test-viso

# Configuration
VERSION := 1.0.0
BUILD_DIR := /tmp/mixos-build
OUTPUT_DIR := $(CURDIR)/artifacts
KERNEL_VERSION := 6.6.8-mixos
JOBS := $(shell nproc)

# VISO/VRAM Configuration
VISO_NAME := mixos-go-v$(VERSION)
VISO_SIZE := 2G
VRAM_MIN_RAM := 2048

# Export for sub-scripts
export BUILD_DIR OUTPUT_DIR JOBS KERNEL_VERSION VERSION VISO_NAME VISO_SIZE

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
BLUE := \033[0;34m
CYAN := \033[0;36m
NC := \033[0m

#=============================================================================
# Main targets
#=============================================================================

all: toolchain-check kernel mix-cli installer packages rootfs initramfs viso
	@echo -e "$(GREEN)✓ MixOS-GO v$(VERSION) build complete!$(NC)"
	@echo ""
	@echo "Build artifacts:"
	@ls -lh $(OUTPUT_DIR)/*.viso 2>/dev/null || true
	@ls -lh $(OUTPUT_DIR)/*.iso 2>/dev/null || true
	@ls -lh $(OUTPUT_DIR)/boot/* 2>/dev/null || true
	@echo ""
	@echo "To test: make test-viso"

help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║     MixOS-GO Build System v$(VERSION)                          ║"
	@echo "║     VISO/SDISK/VRAM Support                                  ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Main targets:"
	@echo "  all          - Build everything (kernel, mix-cli, packages, rootfs, viso)"
	@echo "  kernel       - Build Linux kernel"
	@echo "  mix-cli      - Build mix package manager"
	@echo "  packages     - Build all packages"
	@echo "  rootfs       - Build root filesystem"
	@echo "  iso          - Build traditional bootable ISO"
	@echo "  clean        - Clean build artifacts"
	@echo ""
	@echo -e "$(CYAN)VISO/VRAM targets (Revolutionary Features):$(NC)"
	@echo "  initramfs    - Build enhanced initramfs with VISO/VRAM support"
	@echo "  viso         - Build VISO (Virtual ISO) image"
	@echo "  sdisk        - Build SDISK (Selection Disk) image"
	@echo "  vram         - Build VRAM-optimized package"
	@echo "  modules-dep  - Generate kernel module dependencies"
	@echo ""
	@echo "Testing targets:"
	@echo "  test         - Run all tests"
	@echo "  test-mix     - Run mix-cli unit tests"
	@echo "  test-qemu    - Boot ISO in QEMU"
	@echo "  test-viso    - Boot VISO in QEMU with virtio"
	@echo "  test-vram    - Boot with VRAM mode enabled"
	@echo ""
	@echo "Utility targets:"
	@echo "  toolchain    - Build Docker toolchain image"
	@echo "  toolchain-check - Verify build tools are available"
	@echo "  info         - Show build configuration"
	@echo ""

#=============================================================================
# Toolchain
#=============================================================================

toolchain:
	@echo -e "$(YELLOW)Building Docker toolchain...$(NC)"
	docker build -t mixos-toolchain -f build/docker/Dockerfile.toolchain build/docker/
	@echo -e "$(GREEN)✓ Toolchain ready$(NC)"

toolchain-check:
	@echo -e "$(YELLOW)Checking build tools...$(NC)"
	@which gcc > /dev/null || (echo -e "$(RED)gcc not found$(NC)" && exit 1)
	@which go > /dev/null || (echo -e "$(RED)go not found$(NC)" && exit 1)
	@which make > /dev/null || (echo -e "$(RED)make not found$(NC)" && exit 1)
	@echo -e "$(GREEN)✓ Build tools available$(NC)"

#=============================================================================
# Kernel
#=============================================================================

kernel: toolchain-check
	@echo -e "$(YELLOW)Building Linux kernel $(KERNEL_VERSION)...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	@bash build/scripts/build-kernel.sh
	@echo -e "$(GREEN)✓ Kernel compiled$(NC)"

kernel-config:
	@echo "Opening kernel configuration..."
	@cd $(BUILD_DIR)/linux-$(KERNEL_VERSION) && make menuconfig

#=============================================================================
# Mix CLI Package Manager
#=============================================================================

mix-cli: toolchain-check
	@echo -e "$(YELLOW)Building mix package manager...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	cd src/mix-cli && \
		go mod tidy && \
		CGO_ENABLED=1 go build -ldflags="-s -w" -o $(OUTPUT_DIR)/mix .
	@echo -e "$(GREEN)✓ Mix CLI built ($(shell du -h $(OUTPUT_DIR)/mix | cut -f1))$(NC)"

mix-cli-static: toolchain-check
	@echo -e "$(YELLOW)Building static mix binary...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	cd src/mix-cli && \
		go mod tidy && \
		CGO_ENABLED=1 go build -ldflags="-s -w -linkmode external -extldflags '-static'" -o $(OUTPUT_DIR)/mix .
	@echo -e "$(GREEN)✓ Static mix CLI built$(NC)"

#=============================================================================
# Packages
#=============================================================================

packages: mix-cli
	@echo -e "$(YELLOW)Building packages...$(NC)"
	@mkdir -p $(OUTPUT_DIR)/packages
	@for pkg in src/packages/*/build.sh; do \
		if [ -f "$$pkg" ]; then \
			echo "Building $$(dirname $$pkg | xargs basename)..."; \
			bash "$$pkg" || true; \
		fi \
	done
	@echo -e "$(GREEN)✓ Packages built$(NC)"
	@ls -la $(OUTPUT_DIR)/packages/ 2>/dev/null || true

# Installer binary build (so build-rootfs.sh can copy it into rootfs)
installer: toolchain-check
	@echo -e "$(YELLOW)Building mixos installer binary...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	cd src/installer && \
		go mod tidy && \
		GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o $(OUTPUT_DIR)/mixos-install .
	@echo -e "$(GREEN)✓ Installer built ($(shell du -h $(OUTPUT_DIR)/mixos-install | cut -f1 2>/dev/null || echo '0'))$(NC)"

#=============================================================================
# Root Filesystem
#=============================================================================

rootfs: mix-cli packages
	@echo -e "$(YELLOW)Building root filesystem...$(NC)"
	@bash build/scripts/build-rootfs.sh
	@echo -e "$(GREEN)✓ Rootfs created$(NC)"

#=============================================================================
# ISO Image (Traditional)
#=============================================================================

iso: rootfs initramfs
	@echo -e "$(YELLOW)Building ISO image...$(NC)"
	@bash build/scripts/build-iso.sh
	@echo -e "$(GREEN)✓ ISO generated$(NC)"

#=============================================================================
# VISO/SDISK/VRAM (Revolutionary Features)
#=============================================================================

initramfs: toolchain-check
	@echo -e "$(CYAN)Building enhanced initramfs with VISO/VRAM support...$(NC)"
	@mkdir -p $(OUTPUT_DIR)/boot
	@bash build/scripts/build-initramfs.sh
	@echo -e "$(GREEN)✓ Initramfs built$(NC)"

viso: rootfs initramfs
	@echo -e "$(CYAN)Building VISO (Virtual ISO) image...$(NC)"
	@bash build/scripts/build-viso.sh
	@echo -e "$(GREEN)✓ VISO generated: $(VISO_NAME).viso$(NC)"

sdisk: viso
	@echo -e "$(CYAN)Creating SDISK (Selection Disk)...$(NC)"
	@echo "SDISK is an alias for VISO with SDISK boot parameter"
	@echo "Use: SDISK=$(VISO_NAME).VISO"
	@echo -e "$(GREEN)✓ SDISK ready$(NC)"

vram: rootfs
	@echo -e "$(CYAN)Building VRAM-optimized package...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	@if [ -f $(BUILD_DIR)/rootfs.squashfs ]; then \
		cp $(BUILD_DIR)/rootfs.squashfs $(OUTPUT_DIR)/$(VISO_NAME).vram; \
		echo -e "$(GREEN)✓ VRAM package created$(NC)"; \
	else \
		echo -e "$(YELLOW)Building squashfs for VRAM...$(NC)"; \
		mksquashfs $(BUILD_DIR)/rootfs $(OUTPUT_DIR)/$(VISO_NAME).vram -comp xz -Xbcj x86 -b 1M -noappend; \
		echo -e "$(GREEN)✓ VRAM package created$(NC)"; \
	fi

modules-dep:
	@echo -e "$(YELLOW)Generating kernel module dependencies...$(NC)"
	@bash build/scripts/gen-modules-dep.sh
	@echo -e "$(GREEN)✓ Module dependencies generated$(NC)"

# Build an unattended ISO embedding packaging/install.yaml
iso-autoinstall: toolchain-check
	@echo -e "$(YELLOW)Building unattended ISO (packaging/install.yaml)...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	@export INSTALL_CONFIG=$(CURDIR)/packaging/install.yaml; \
		echo "Using INSTALL_CONFIG=$$INSTALL_CONFIG"; \
		bash build/scripts/build-kernel.sh; \
		bash build/scripts/build-rootfs.sh; \
		bash build/scripts/build-iso.sh; \
		echo -e "$(GREEN)✓ Unattended ISO generated$(NC)"

#=============================================================================
# Testing
#=============================================================================

test: test-mix
	@echo -e "$(GREEN)✓ All tests passed$(NC)"

test-mix:
	@echo -e "$(YELLOW)Running mix-cli tests...$(NC)"
	cd src/mix-cli && go test -v ./...
	@echo -e "$(GREEN)✓ Mix CLI tests passed$(NC)"

test-qemu:
	@echo -e "$(YELLOW)Booting ISO in QEMU...$(NC)"
	@if [ -f $(OUTPUT_DIR)/mixos-go-v$(VERSION).iso ]; then \
		qemu-system-x86_64 \
			-cdrom $(OUTPUT_DIR)/mixos-go-v$(VERSION).iso \
			-m 512 \
			-enable-kvm 2>/dev/null || \
		qemu-system-x86_64 \
			-cdrom $(OUTPUT_DIR)/mixos-go-v$(VERSION).iso \
			-m 512 \
			-nographic; \
	else \
		echo -e "$(RED)ISO not found. Run 'make iso' first.$(NC)"; \
		exit 1; \
	fi

test-iso: test-qemu

test-viso:
	@echo -e "$(CYAN)Booting VISO in QEMU with virtio (Maximum Performance)...$(NC)"
	@if [ -f $(OUTPUT_DIR)/$(VISO_NAME).viso ]; then \
		qemu-system-x86_64 \
			-drive file=$(OUTPUT_DIR)/$(VISO_NAME).viso,format=qcow2,if=virtio,cache=writeback,aio=threads \
			-m 2G \
			-cpu host \
			-enable-kvm 2>/dev/null || \
		qemu-system-x86_64 \
			-drive file=$(OUTPUT_DIR)/$(VISO_NAME).viso,format=qcow2,if=virtio \
			-m 2G \
			-nographic; \
	else \
		echo -e "$(RED)VISO not found. Run 'make viso' first.$(NC)"; \
		exit 1; \
	fi

test-vram:
	@echo -e "$(CYAN)Booting with VRAM mode (System runs from RAM)...$(NC)"
	@if [ -f $(OUTPUT_DIR)/$(VISO_NAME).viso ]; then \
		qemu-system-x86_64 \
			-drive file=$(OUTPUT_DIR)/$(VISO_NAME).viso,format=qcow2,if=virtio,cache=writeback,aio=threads \
			-m 4G \
			-cpu host \
			-enable-kvm \
			-append "console=ttyS0 VRAM=auto SDISK=$(VISO_NAME).VISO" \
			-nographic 2>/dev/null || \
		qemu-system-x86_64 \
			-drive file=$(OUTPUT_DIR)/$(VISO_NAME).viso,format=qcow2,if=virtio \
			-m 4G \
			-append "console=ttyS0 VRAM=auto" \
			-nographic; \
	else \
		echo -e "$(RED)VISO not found. Run 'make viso' first.$(NC)"; \
		exit 1; \
	fi

test-sdisk:
	@echo -e "$(CYAN)Testing SDISK boot mechanism...$(NC)"
	@echo "SDISK boot uses kernel parameter: SDISK=$(VISO_NAME).VISO"
	@$(MAKE) test-vram

#=============================================================================
# Cleanup
#=============================================================================

clean:
	@echo -e "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	rm -rf $(OUTPUT_DIR)/*
	cd src/mix-cli && go clean
	@echo -e "$(GREEN)✓ Clean complete$(NC)"

clean-all: clean
	rm -rf $(BUILD_DIR)
	docker rmi mixos-toolchain 2>/dev/null || true

#=============================================================================
# Development helpers
#=============================================================================

dev-shell:
	@docker run -it --rm \
		-v $(CURDIR):/workspace \
		-w /workspace \
		mixos-toolchain \
		/bin/bash

checksums:
	@echo "Generating checksums..."
	@cd $(OUTPUT_DIR) && \
		for f in *.iso *.tar.gz; do \
			[ -f "$$f" ] && sha256sum "$$f" > "$$f.sha256"; \
		done
	@echo -e "$(GREEN)✓ Checksums generated$(NC)"

info:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║     MixOS-GO Build Information                               ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Version:        $(VERSION)"
	@echo "Kernel:         $(KERNEL_VERSION)"
	@echo "Build Dir:      $(BUILD_DIR)"
	@echo "Output Dir:     $(OUTPUT_DIR)"
	@echo "Parallel Jobs:  $(JOBS)"
	@echo ""
	@echo "VISO Configuration:"
	@echo "  VISO Name:    $(VISO_NAME)"
	@echo "  VISO Size:    $(VISO_SIZE)"
	@echo "  VRAM Min RAM: $(VRAM_MIN_RAM)MB"
	@echo ""
	@echo "Tool Versions:"
	@echo "  Go:    $$(go version 2>/dev/null || echo 'not installed')"
	@echo "  GCC:   $$(gcc --version 2>/dev/null | head -1 || echo 'not installed')"
	@echo "  QEMU:  $$(qemu-system-x86_64 --version 2>/dev/null | head -1 || echo 'not installed')"
	@echo ""
	@echo "Revolutionary Features:"
	@echo "  ✓ VISO (Virtual ISO) - Replaces traditional CDROM"
	@echo "  ✓ SDISK (Selection Disk) - Advanced boot mechanism"
	@echo "  ✓ VRAM Mode - Boot entire system from RAM"
	@echo "  ✓ Virtio Optimized - Maximum I/O performance"
	@echo ""
