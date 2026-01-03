# MixOS-GO Build System
# Version 1.0.0

SHELL := /bin/bash
.PHONY: all clean toolchain kernel mix-cli installer packages rootfs iso test help

# Configuration
VERSION := 1.0.0
BUILD_DIR := /tmp/mixos-build
OUTPUT_DIR := $(CURDIR)/artifacts
KERNEL_VERSION := 6.6.8
JOBS := $(shell nproc)

# Export for sub-scripts
export BUILD_DIR OUTPUT_DIR JOBS

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m

#=============================================================================
# Main targets
#=============================================================================

all: toolchain-check kernel mix-cli installer packages rootfs iso
	@echo -e "$(GREEN)✓ MixOS-GO v$(VERSION) build complete!$(NC)"
	@echo ""
	@echo "Build artifacts:"
	@ls -lh $(OUTPUT_DIR)/*.iso 2>/dev/null || ls -lh $(OUTPUT_DIR)/*.tar.gz 2>/dev/null || true
	@echo ""
	@echo "To test: make test-qemu"

help:
	@echo "MixOS-GO Build System v$(VERSION)"
	@echo ""
	@echo "Main targets:"
	@echo "  all          - Build everything (kernel, mix-cli, packages, rootfs, iso)"
	@echo "  kernel       - Build Linux kernel"
	@echo "  mix-cli      - Build mix package manager"
	@echo "  packages     - Build all packages"
	@echo "  rootfs       - Build root filesystem"
	@echo "  iso          - Build bootable ISO"
	@echo "  clean        - Clean build artifacts"
	@echo ""
	@echo "Testing targets:"
	@echo "  test         - Run all tests"
	@echo "  test-mix     - Run mix-cli unit tests"
	@echo "  test-qemu    - Boot ISO in QEMU"
	@echo ""
	@echo "Utility targets:"
	@echo "  toolchain    - Build Docker toolchain image"
	@echo "  toolchain-check - Verify build tools are available"

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
# ISO Image
#=============================================================================

iso: rootfs
	@echo -e "$(YELLOW)Building ISO image...$(NC)"
	@bash build/scripts/build-iso.sh
	@echo -e "$(GREEN)✓ ISO generated$(NC)"

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
	@echo "MixOS-GO Build Information"
	@echo "=========================="
	@echo "Version: $(VERSION)"
	@echo "Kernel: $(KERNEL_VERSION)"
	@echo "Build Dir: $(BUILD_DIR)"
	@echo "Output Dir: $(OUTPUT_DIR)"
	@echo "Parallel Jobs: $(JOBS)"
	@echo ""
	@echo "Go version: $$(go version 2>/dev/null || echo 'not installed')"
	@echo "GCC version: $$(gcc --version 2>/dev/null | head -1 || echo 'not installed')"
