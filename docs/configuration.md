# Octopus Configuration Reference

All runtime configuration lives in `/etc/octopus.env` on the appliance.
Edit this file before building, or edit it on a running appliance and
reboot (or restart individual services with `s6-svc -r`).

---

## Identity

| Variable | Default | Description |
|---|---|---|
| `HOSTNAME` | `octopus` | Machine hostname |

---

## Network

| Variable | Default | Description |
|---|---|---|
| `NETWORK_INTERFACE` | `eth0` | Primary network interface |
| `NETWORK_MODE` | `dhcp` | `dhcp` or `static` |
| `STATIC_IP` | — | IP address (static mode only) |
| `STATIC_NETMASK` | — | Netmask e.g. `255.255.255.0` (static mode only) |
| `STATIC_GATEWAY` | — | Default gateway (static mode only) |

---

## MCP Server

| Variable | Default | Description |
|---|---|---|
| `MCP_SERVER_URL` | — | Public HTTPS URL Claude connects to (your tunnel URL) |
| `MCP_PORT` | `8765` | Local HTTP port |
| `MCP_ROOT` | `/data/projects` | Root directory exposed to Claude via file tools |
| `MCP_ENDPOINT` | `/claude` | HTTP path for the MCP endpoint |

---

## Cloudflare Tunnel

| Variable | Default | Description |
|---|---|---|
| `TUNNEL_TOKEN` | — | Cloudflare tunnel token from dash.cloudflare.com |

To create a tunnel:
1. Go to https://one.dash.cloudflare.com/ → Networks → Tunnels
2. Create a tunnel, copy the token
3. Set the public hostname to point at `http://localhost:8765`

---

## SSH

| Variable | Default | Description |
|---|---|---|
| `SSH_AUTHORIZED_KEYS` | — | Public key(s) for SSH access (one per line) |

Password authentication is disabled. Only key-based auth is allowed.

---

## NTP

| Variable | Default | Description |
|---|---|---|
| `NTP_SERVERS` | `0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org` | Space-separated NTP server list |

---

## DNS

| Variable | Default | Description |
|---|---|---|
| `DNS_UPSTREAM` | `1.1.1.1` | Primary upstream DNS resolver |
| `DNS_UPSTREAM_SECONDARY` | `8.8.8.8` | Secondary upstream DNS resolver |

Unbound runs as a local caching resolver on `127.0.0.1:53` and forwards
to the upstream resolvers. All services on the appliance use it.

---

## Logging

| Variable | Default | Description |
|---|---|---|
| `LOG_DIR` | `/var/log/octopus` | Base directory for all logs |

Log files:
- `/var/log/octopus/mcp-server/current` — MCP server output
- `/var/log/octopus/cloudflared/current` — Tunnel output
- `/var/log/octopus/crashes.log` — Service crash log (from s6 finish scripts)
- `/var/log/octopus/unbound.log` — DNS resolver log

---

## First boot checklist

1. Edit `overlay/etc/octopus.env` with your values
2. Run `./scripts/build.sh`
3. Flash `buildroot/output/images/octopus.iso` to USB
4. Boot the appliance
5. SSH in: `ssh root@<ip>`
6. Add the tunnel URL to Claude.ai → Settings → Connectors
