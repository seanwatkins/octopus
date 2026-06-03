#!/bin/sh
# Octopus QEMU test — uses persistent br0 bridge (set up via netplan at boot)
# br0 must already exist; see /etc/netplan/00-installer-config.yaml

TOP=/share/html/octo
TAP=tap-octopus
BRIDGE=br0

# Sanity check
if ! ip link show $BRIDGE > /dev/null 2>&1; then
    echo "ERROR: bridge $BRIDGE does not exist."
    echo "Run: sudo netplan apply  (after configuring br0 in /etc/netplan/)"
    exit 1
fi

# Create tap and attach to bridge
sudo ip tuntap add dev $TAP mode tap user sean 2>/dev/null || true
sudo ip link set $TAP master $BRIDGE
sudo ip link set $TAP up
echo "tap ready: $TAP -> $BRIDGE"

teardown() {
    sudo ip link set $TAP down 2>/dev/null || true
    sudo ip tuntap del dev $TAP mode tap 2>/dev/null || true
    echo "tap removed"
}
trap teardown EXIT INT TERM

qemu-system-x86_64 \
  -m 4096 \
  -cpu Haswell \
  -kernel $TOP/bzImage-pci \
  -initrd $TOP/rootfs-boot.cpio \
  -append "console=ttyS0,115200 earlyprintk=serial nomodeset panic=5 init=/init" \
  -nographic \
  -serial mon:stdio \
  -netdev tap,id=net0,ifname=$TAP,script=no,downscript=no \
  -device e1000,netdev=net0
