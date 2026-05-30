#!/bin/bash
# scripts/post-build.sh
# Called by Buildroot after the rootfs is assembled but before image creation.
# Sets the kernel init= parameter and writes the GRUB config.

TARGET_DIR="$1"

# Ensure our init script is executable
chmod +x "${TARGET_DIR}/usr/local/bin/octopus-init"
chmod +x "${TARGET_DIR}/etc/s6/services"/*/run
chmod +x "${TARGET_DIR}/etc/s6/services"/*/finish 2>/dev/null || true

# Create log directories
mkdir -p "${TARGET_DIR}/var/log/octopus"
mkdir -p "${TARGET_DIR}/var/lib/chrony"
mkdir -p "${TARGET_DIR}/var/lib/unbound"
mkdir -p "${TARGET_DIR}/data/projects"

# Write GRUB config — boot with our init script as PID 1
mkdir -p "${TARGET_DIR}/boot/grub"
cat > "${TARGET_DIR}/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=3

menuentry "Octopus Appliance" {
    linux /boot/bzImage \
        root=/dev/sda1 \
        rw \
        init=/usr/local/bin/octopus-init \
        console=ttyS0,115200 \
        console=tty0 \
        quiet \
        loglevel=3
    initrd /boot/initrd
}

menuentry "Octopus (verbose)" {
    linux /boot/bzImage \
        root=/dev/sda1 \
        rw \
        init=/usr/local/bin/octopus-init \
        console=ttyS0,115200 \
        console=tty0 \
        loglevel=7
    initrd /boot/initrd
}
EOF

echo "[post-build] Octopus rootfs prepared."
