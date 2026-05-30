#!/bin/bash
# scripts/build.sh
#
# Full Octopus build — SBCL core + Buildroot image.
# Run this from the project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════╗"
echo "║        Octopus Appliance Build       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Check the prebuilt binary exists or build it
PREBUILT="${SCRIPT_DIR}/../prebuilt/mcp-server"
if [ ! -f "${PREBUILT}" ]; then
    echo "── Step 1/2: Building SBCL core ────────────────"
    bash "${SCRIPT_DIR}/build-sbcl-core.sh"
else
    echo "── Step 1/2: SBCL core already built (${PREBUILT})"
    echo "   Run scripts/build-sbcl-core.sh to rebuild."
fi

echo ""

# Step 2: Build the Buildroot image
echo "── Step 2/2: Building Buildroot image ──────────"
bash "${SCRIPT_DIR}/make-image.sh"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║           Build complete!            ║"
echo "╚══════════════════════════════════════╝"
