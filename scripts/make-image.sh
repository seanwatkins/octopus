#!/bin/bash
# scripts/make-image.sh — builds the Octopus image from /projects/buildroot-2024.11.1

set -euo pipefail
BR_DIR="/projects/buildroot-2024.11.1"
EXTERNAL_DIR="/share/projects/octopus/buildroot"
OUTPUT_DIR="${BR_DIR}/output"

echo "=== Octopus: Building image ==="
cd "${BR_DIR}"

if [ ! -f ".config" ]; then
    make BR2_EXTERNAL="${EXTERNAL_DIR}" octopus_defconfig
fi

make -j$(nproc) \
  HOSTCFLAGS="-std=gnu11 -O2" \
  HOSTCXXFLAGS="-std=gnu++11 -O2"

if [ -f "${OUTPUT_DIR}/images/rootfs.iso9660" ]; then
    cp "${OUTPUT_DIR}/images/rootfs.iso9660" "${OUTPUT_DIR}/images/octopus.iso"
    cp "${OUTPUT_DIR}/images/octopus.iso" /share/projects/octopus/prebuilt/octopus.iso
    SIZE=$(du -sh "${OUTPUT_DIR}/images/octopus.iso" | cut -f1)
    echo "=== Done: ${OUTPUT_DIR}/images/octopus.iso (${SIZE}) ==="
fi
