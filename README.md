# Octopus

A minimal Linux appliance OS that boots directly into the MCP server stack.
Eight arms — eight services — one purpose.

Built with Buildroot, supervised by s6, with a pre-compiled SBCL core for
~100ms startup time.

Written by Claude (https://claude.ai) with Sean Watkins.

---

## Architecture

```
PID 1 (s6-svscan)
├── mcp-server    — SBCL MCP server (hunchentoot HTTP + OAuth)
├── cloudflared   — Cloudflare HTTPS tunnel
├── sshd          — OpenSSH for remote access
├── chrony        — NTP time sync
├── unbound       — Local DNS resolver
├── dhcpcd        — DHCP client
├── watchdog      — Kernel hardware watchdog
└── logger        — s6 log aggregator → /var/log/octopus
```

Boot sequence:
```
BIOS/UEFI → GRUB → kernel → /usr/local/bin/octopus-init (PID 1) → s6-svscan → services
```

---

## Directory layout

```
octopus/
├── buildroot/                  Buildroot external tree
│   ├── Config.in
│   ├── external.mk
│   ├── configs/
│   │   ├── octopus_defconfig   Main Buildroot config
│   │   ├── linux.config        Stripped kernel config
│   │   └── busybox.config      Minimal busybox config
│   └── package/
│       └── sbcl-mcp/           Custom package: SBCL core binary
├── overlay/                    Rootfs overlay
│   ├── etc/
│   │   ├── s6/
│   │   │   ├── init/           PID 1 stage scripts
│   │   │   └── services/       s6 supervised services
│   │   │       ├── mcp-server/
│   │   │       ├── cloudflared/
│   │   │       ├── sshd/
│   │   │       ├── chrony/
│   │   │       ├── unbound/
│   │   │       ├── dhcpcd/
│   │   │       └── watchdog/
│   │   ├── unbound/
│   │   │   └── unbound.conf
│   │   └── ssh/
│   │       └── sshd_config
│   └── usr/local/bin/
│       └── octopus-init        PID 1 init script
├── prebuilt/                   Populated by build-sbcl-core.sh
│   ├── mcp-server              SBCL executable core
│   └── mcp-server.env.example
├── scripts/
│   ├── build.sh                Full build orchestration
│   ├── build-sbcl-core.sh      Compiles SBCL + deps into single binary
│   └── make-image.sh           Runs Buildroot
└── docs/
    └── configuration.md        Runtime configuration reference
```

---

## Quick start

### Prerequisites

```bash
# Ubuntu/Debian build host
sudo apt-get install -y \
  build-essential git wget cpio unzip rsync bc \
  libncurses-dev libssl-dev python3 python3-pip \
  sbcl

# Quicklisp must be installed for the build user
# https://www.quicklisp.org/beta/
```

### Build

```bash
cd /share/projects/octopus
./scripts/build.sh
```

Output: `buildroot/output/images/octopus.iso`

### Flash to USB

```bash
sudo dd if=buildroot/output/images/octopus.iso of=/dev/sdX bs=4M status=progress
```

---

## Runtime configuration

Edit `overlay/etc/octopus.env` before building, or mount the first partition
and edit `/etc/octopus.env` on a running appliance.

See `docs/configuration.md` for all options.

---

## Rebuilding the SBCL core

After changing `mcp-server.lisp`:

```bash
./scripts/build-sbcl-core.sh
# Then rebuild the image:
./scripts/make-image.sh
```

---

## Service management (s6)

```bash
# Stop a service
s6-svc -d /etc/s6/services/mcp-server

# Start a service
s6-svc -u /etc/s6/services/mcp-server

# Restart a service
s6-svc -r /etc/s6/services/mcp-server

# Check service status
s6-svstat /etc/s6/services/mcp-server

# Tail logs
tail -f /var/log/octopus/mcp-server/current
```
