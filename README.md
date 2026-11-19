# homelab

A two-machine homelab run like a small production environment: everything is defined in Git, every alert has a runbook, and every outage — real or drilled — gets a blameless postmortem.

![Homelab diagram](docs/homelab-diagram.png)

## What runs where

| Machine | Role | Runs |
|---|---|---|
| **NAS** — Jonsbo N5, i5-14600K, 64 GB RAM, ZFS RAIDZ1 on 4× 18 TB (47 TiB usable), 2.5 GbE, Ubuntu 26.04 | Does the work | Modded Minecraft server, mc-monitor, cAdvisor, node_exporter, smartctl-exporter, NUT server (UPS over USB) |
| **Beelink SER Pro** — Ubuntu 26.04 | Watches everything | Prometheus, Grafana, Alertmanager, ntfy (push to phone), node_exporter, NUT client |
| **healthchecks.io** | Watches the watcher | Dead man's switch for the alerting chain, plus backup checks |

The two machines talk over **Tailscale**. Every monitoring port is bound to a Tailscale address and allowed only from the monitoring host in UFW; the only port open to the internet is the Minecraft server (whitelisted).

## Storage

| Dataset | Mount | Used for |
|---|---|---|
| `tank/data` (recordsize 1M) | `/data` | Media and downloads (TRaSH Guides layout) |
| `tank/files` | `/tank/files` | File shares |
| `tank/photos` | `/tank/photos` | Photos |
| `tank/gameservers` | `/tank/gameservers` | Game server data |
| `tank/backups` | `/tank/backups` | Backups (e.g. Minecraft worlds) |

RAIDZ1 survives any one drive failing. lz4 compression and `atime=off` on everything, ZFS ARC capped at 16 GiB, monthly scrubs. Fast, frequently written data (the live Minecraft world) stays on the NVMe; its backups go to the pool, so each copy is on different hardware.

## How a problem reaches my phone

```
exporter (NAS) → Prometheus (scrape every 15 s) → alert rule (for: …)
              → Alertmanager → ntfy-alertmanager → ntfy → phone
Alertmanager → Watchdog heartbeat every 1 min → healthchecks.io → Discord / email / ntfy.sh
```

| Alert | Fires when | Runbook |
|---|---|---|
| TargetDown | Prometheus can't scrape a target for 2 min | [target-down.md](docs/runbooks/target-down.md) |
| Watchdog (dead man's switch) | healthchecks.io stops getting heartbeats | [watchdog-down.md](docs/runbooks/watchdog-down.md) |
| DriveHot | A drive is above 50 °C for 10 min | [drive-hot.md](docs/runbooks/drive-hot.md) |
| DriveFailing | A drive's SMART status reports FAILED | [drive-failing.md](docs/runbooks/drive-failing.md) |
| ZpoolNotOnline | The ZFS pool is degraded or worse for 1 min | [zpool-not-online.md](docs/runbooks/zpool-not-online.md) |
| LowMemory | A host has < 10% RAM available for 10 min | [low-memory.md](docs/runbooks/low-memory.md) |
| MinecraftDown | The Minecraft server stops answering for 2 min | [minecraft-down.md](docs/runbooks/minecraft-down.md) |

Every alert links to its runbook from the notification itself. New runbooks start from [`_TEMPLATE.md`](docs/runbooks/_TEMPLATE.md).

## Dashboards

Grafana dashboards are saved as JSON in `monitoring/grafana/dashboards/`.

| Dashboard | Answers |
|---|---|
| Node Exporter Full | Is the machine healthy? (CPU, RAM, disk, network) |
| cAdvisor | Which container is using the resources? |
| Minecraft | Is the game up, how fast does it answer, and who's playing? |
| Drives (SMART) | Drive health, temperatures, warning counters, NVMe wear |

## Repo layout

```
ansible/       Host provisioning (roles: base, docker, tailscale) for both machines
monitoring/    Beelink stack: Prometheus, Grafana, Alertmanager, ntfy (Docker Compose)
  grafana/dashboards/   Dashboard JSON
nas/
  exporters/             node_exporter, smartctl-exporter, cAdvisor
  gameservers/minecraft/ Minecraft server + mc-monitor + backup.sh
  nut/                   UPS config (passwords in *.example only)
docs/
  runbooks/      What to do when each alert fires
  postmortems/   Blameless write-ups of every outage and drill
```

The same repo is cloned to `/opt/stacks` on both machines; each one runs only its own folders.

## Reliability practices

- **Infrastructure as code:** Docker Compose for every service, Ansible for the hosts. A second Ansible run reports `changed=0`.
- **Pinned versions:** every image (and the Minecraft modpack) is pinned; upgrades are a deliberate one-line change.
- **Validate before restart:** `promtool check config` and `amtool check-config` before any Prometheus or Alertmanager restart.
- **Reboot-tested:** after host-level changes the box is rebooted on purpose to prove everything comes back.
- **Drills:** alerts are tested by breaking things on purpose. A drill isn't finished until the *Resolved* notification arrives.
- **Planned maintenance under a silence:** Alertmanager silences scoped to the host being worked on, expired when it's back.
- **Backups with a restore test:** Minecraft world backed up hourly (keep 24) and nightly (keep 7) to the ZFS pool. Saving is paused and flushed first so an archive is never caught mid-write; archives are written to a temp file and renamed only when complete; missed backups alert via healthchecks.io.
- **Burn-in before trust:** drives got SMART short tests, a 48-hour destructive `badblocks` pass and SMART long tests; RAM got 4 passes of MemTest86 — all with zero errors before any data was stored.
- **Power protection:** a CyberPower UPS shared via NUT so both machines can shut down cleanly.
- **Secrets stay out of Git:** `.env` files, tokens and ping URLs are git-ignored; `*.example` files show the format.

## Postmortems

| Date | What happened | Write-up |
|---|---|---|
| 2026-11-17 | Minecraft drill left the server down ~9 h | [link](docs/postmortems/2026-11-17-minecraft-down-drill.md) |
| 2026-11-09 | Power loss: monitoring down ~10 h | [link](docs/postmortems/2026-11-09-power-loss-monitoring-outage.md) |
| 2026-11-08 | Alertmanager / dead man's switch drill | [link](docs/postmortems/2026-11-08-alertmanager-deadmans-drill.md) |
| 2026-11-08 | node_exporter drill | [link](docs/postmortems/2026-11-08-node-exporter-drill.md) |
