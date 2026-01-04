## TROUBLESHOOTING: ISO build, initramfs and early-boot

This document records the problems encountered while adding the interactive installer and how to diagnose/fix them.

- Problem: kernel panic "Unable to mount root fs" when booting ISO
  - Cause: the `initramfs.img` embedded in the ISO could be truncated/differ from the locally-generated archive.
  - Fixes:
    - Ensure `build/scripts/build-iso.sh` writes a deterministic initramfs and `sync` is run before ISO creation.
    - Use explicit `xorriso -graft-points` as a fallback to graft the exact `boot/initramfs.img` into the ISO (avoid indirect copying that may truncate files).
    - Validate by comparing checksums: `sha256sum /tmp/initramfs.img` vs `sha256sum /mnt/boot/initramfs.img` after mounting the ISO.

- Problem: boot falls back to initramfs root ("Live filesystem not found")
  - Cause: early `/init` may not find or mount the CD-ROM or `live/filesystem.squashfs` fast enough under QEMU/runners.
  - Fixes:
    - Update `/init` in the initramfs to:
      - sleep a short while at start (15s), retry mounts across plausible devices, and run `modprobe squashfs` before attempting squashfs mounts.
      - Emit helpful diagnostics to the serial console (e.g. `ls -l /mnt/cdrom`, `/proc/partitions`, `blkid`) so CI logs show device state.
    - Verify squashfs exists inside ISO: `unsquashfs -l artifacts/*.iso` or mount the ISO and `ls -l live/filesystem.squashfs`.

- Problem: `mixos-install` reported "not found" in early init scripts
  - Cause: the installer binary was present in the initramfs during tests but may be missing in the live squashfs root after pivot.
  - Fixes:
    - Ensure `build/scripts/build-rootfs.sh` copies `artifacts/mixos-install` into the rootfs that becomes the squashfs (check permissions and executable bit).
    - After building ISO, mount the squashfs and verify: `unsquashfs -l /tmp/mixos-build/iso/live/filesystem.squashfs | grep mixos-install`.

- CI/workflow guidance
  - The `build.yml` workflow includes a headless QEMU smoke-boot step that runs the built ISO for ~90s and checks the serial log for the boot prompt. This helps catch initramfs truncation and early-boot failures.
  - If the workflow fails the smoke-boot step, download the `artifacts` (ISO and `boot.log`) and compare checksums and the serial console output to pinpoint the failure mode.

- Local reproduction steps
  1. Build locally: `make iso` (this runs `build-rootfs.sh` and `build-iso.sh`).
  2. Generate a standalone initramfs for debugging:
     - `cd /tmp/mixos-build/rootfs && find . -print0 | cpio --null -ov --format=newc | gzip -9 > /tmp/initramfs.img`
     - `sha256sum /tmp/initramfs.img`
  3. Mount the produced ISO and compare:
     - `sudo mount -o loop artifacts/mixos-go-v1.0.0.iso /mnt`
     - `sha256sum /mnt/boot/initramfs.img`
  4. Boot in QEMU and capture serial:
     - `timeout 90s qemu-system-x86_64 -cdrom artifacts/mixos-go-v1.0.0.iso -m 512 -nographic -serial file:artifacts/boot.log`
     - Inspect `artifacts/boot.log` for "mixos login" or the diagnostic messages from the initramfs.

- When to escalate
  - If checksums match but the ISO still fails to pivot into squashfs, inspect `artifacts/boot.log` for device nodes (`/proc/partitions`) and whether `squashfs` module loaded. Add additional `ls`/`dmesg` output in `/init` if needed.

If you want, I can (a) add more diagnostic captures to the initramfs `/init`, (b) extend the CI timeout, or (c) create a small script to automatically verify embedded initramfs checksums in the generated ISO as part of the build job.
