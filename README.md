# Octopus 🐙

A minimal Linux appliance that boots directly into a live Common Lisp MCP server.
Eight arms — eight services — one purpose.

Built with Buildroot, supervised by s6, tunnelled by Cloudflare.
The entire OS exists to get out of the way and let the Lisp image run.

Written by Claude (https://claude.ai) with Sean Watkins.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

---

## What it is

Octopus boots a machine directly into a running SBCL image. Claude connects
to it over MCP and can define new tools at runtime — they're eval'd into the
live image, written to `tools.lisp`, and survive reboots. No redeploy, no
container rebuild, no restart. The server rewrites itself in conversation.

See the [website](https://octopusmcp.xyz) for the full writeup.

---

## Services

```
PID 1 → octopus-init → s6-svscan
                          ├── mcp-server    SBCL MCP server (Hunchentoot + OAuth 2.0)
                          ├── cloudflared   Cloudflare HTTPS tunnel (no open ports)
                          ├── sshd          OpenSSH
                          ├── chrony        NTP
                          ├── unbound       Local DNS resolver
                          ├── dhcpcd        DHCP client
                          └── watchdog      Kernel hardware watchdog
```

Boot sequence:
```
PXE/netboot → bzImage-pci → static ELF /init → octopus-init → s6-svscan → services
```

All service logs go to `/var/log/octopus/<service>.log`.

---

## Directory layout

```
octopus/
├── buildroot/              Buildroot BR2_EXTERNAL tree
│   ├── configs/
│   │   ├── octopus_defconfig   Main Buildroot config
│   │   └── linux.config        Stripped kernel config (x86_64, PCI, e1000/r8169)
│   └── patches/            Kernel/package patches
├── overlay/                Rootfs overlay — synced to initramfs
│   ├── etc/
│   │   ├── octopus.env     Runtime configuration (edit before building)
│   │   ├── s6/services/    s6 supervised service run scripts
│   │   ├── ssh/            sshd config
│   │   └── unbound/        unbound DNS config
│   └── usr/local/bin/
│       └── octopus-init    Boot script (banner, spinners, DHCP wait, s6 handoff)
├── prebuilt/               Built artifacts (not in git — too large)
│   ├── bzImage-pci         Linux 6.11.11 kernel (PCI enabled)
│   ├── rootfs-boot.cpio    Initramfs (~107MB with cloudflared + mcp-server)
│   ├── mcp-server          SBCL executable core
│   └── cloudflared         Cloudflare tunnel binary
├── scripts/
│   ├── build.sh            Full build orchestration
│   ├── build-sbcl-core.sh  Compiles SBCL + deps into single binary
│   ├── make-image.sh       Runs Buildroot
│   ├── octo-test.sh        QEMU test (bridged networking)
│   └── post-build.sh       Post-build hook
├── docs/
│   ├── building.md         Full build process — cross compiler, cpio, gotchas
│   └── configuration.md    Runtime configuration reference
└── public/
    └── index.html          Project website
```

---

## Quick start

### Option A — Docker (easiest)

See [mcp_server](https://github.com/seanwatkins/mcp_server) — the OctopusBaby
Docker image runs the MCP server in a container with Cloudflare tunnel included.

```bash
git clone https://github.com/seanwatkins/mcp_server
cd mcp_server/docker
cp .env.example .env   # set MCP_SERVER_URL and TUNNEL_TOKEN
docker compose up -d
```

### Option B — Netboot (bare metal)

Pre-built kernel and initramfs are served over HTTP. Your netboot.xyz entry:

```
kernel http://YOUR_SERVER/octo/bzImage-pci ip=dhcp console=tty0 earlyprintk=vga nomodeset panic=5 init=/init
initrd http://YOUR_SERVER/octo/rootfs-boot.cpio
```

Configure before building by editing `overlay/etc/octopus.env`:

```bash
MCP_SERVER_URL=https://your-hostname.octopusmcp.xyz
TUNNEL_TOKEN=eyJhIjoiZTY4...
SSH_AUTHORIZED_KEYS="ssh-ed25519 AAAA... you@host"
```

### Option C — Build from source

Read `docs/building.md` first — there are several non-obvious steps involving
the cross-compiler, cpio device nodes, and glibc/musl library setup.

```bash
# Prerequisites
sudo apt-get install -y build-essential git wget cpio unzip rsync bc \
  libncurses-dev libssl-dev python3 sbcl

# Get Buildroot
wget https://buildroot.org/downloads/buildroot-2024.11.1.tar.gz -P /projects
tar xf /projects/buildroot-2024.11.1.tar.gz -C /projects

# Build SBCL core first
./scripts/build-sbcl-core.sh

# Build the image
./scripts/make-image.sh
```

See `docs/building.md` for the full story including every problem we hit.

---

## Runtime configuration

All configuration is in `/etc/octopus.env`. Edit before building, or SSH in
and edit live — services re-read it on restart.

| Variable | Default | Description |
|---|---|---|
| `HOSTNAME` | `octopus` | Machine hostname |
| `MCP_SERVER_URL` | — | Public URL Claude connects to — **must be set** |
| `MCP_PORT` | `8765` | MCP server port |
| `MCP_ROOT` | `/data/projects` | Tools filesystem root |
| `TUNNEL_TOKEN` | — | Cloudflare tunnel token |
| `TOOLS_FILE` | `/data/projects/tools.lisp` | Persistent tool definitions |
| `LOG_FILE` | `/var/log/octopus/mcp-server.log` | MCP server log |
| `SSH_AUTHORIZED_KEYS` | — | Public keys for SSH access |
| `NETWORK_INTERFACE` | auto-detected | Override if auto-detect fails |

See `docs/configuration.md` for all options.

---

## Service management

```bash
s6-svc -r /etc/s6/services/mcp-server     # restart
s6-svc -d /etc/s6/services/cloudflared    # stop
s6-svc -u /etc/s6/services/cloudflared    # start
s6-svstat /etc/s6/services/mcp-server     # status

tail -f /var/log/octopus/mcp-server.log   # logs
tail -f /var/log/octopus/cloudflared.log
```

---

## Connecting to Claude

Once running, add the public URL to Claude:
**Settings → Integrations → Add MCP Server → enter your `MCP_SERVER_URL`**

---

## QEMU testing

```bash
# Requires br0 bridge set up via netplan (see docs/building.md)
./scripts/octo-test.sh
```

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).

Copyright © 2026 Sean Watkins. Derivative works must also be GPL v3.
