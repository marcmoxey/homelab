# Runbook: MinecraftDown

| | |
|---|---|
| **Alert** | `MinecraftDown` (severity: critical) |
| **Rule** | `minecraft_status_healthy == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | mc-monitor gets no answer from a Minecraft server for 2+ minutes |
| **Impact** | Friends can't join or get disconnected |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy topic `homelab-alerts` → phone |
| **Expected detection time** | ~3–3.5 min (15s scrape + 2m `for` + 30s `group_wait`) |
| **Does NOT cover** | Whether friends can reach it from the internet (port forward, DDNS, ISP). Test that from outside: phone on cellular, or a friend. |

## How the check works

```
prominence2 (NAS, :25565) ◄── mc-monitor (NAS) ◄── Prometheus (Beelink) ──► Alertmanager ──► ntfy ──► phone
                              pings it like the        scrapes 100.105.219.6:9150
                              in-game server list
```

| Piece | Where | Details |
|---|---|---|
| Minecraft server | NAS, `/opt/stacks/nas/gameservers/minecraft/compose.yaml`, service `prominence2` | `itzg/minecraft-server:2026.11.0-java17`, Prominence II v4.1.8 (Fabric 1.20.1), `MEMORY: 10G` |
| World data | NAS, `/opt/appdata/minecraft/prominence` | Mounted as `/data` in the container |
| mc-monitor | Same compose file | `itzg/mc-monitor:1.21.0`, `EXPORT_SERVERS: "prominence2:25565"`, metrics on `100.105.219.6:9150` |
| Scrape job | Beelink, `prometheus.yml` | `job_name: minecraft` |
| Firewall | NAS UFW (Ansible `group_vars/storage.yml`) | 9150 allowed from `100.66.160.124` only |

If **mc-monitor itself** is down, this alert can't fire (no data is not the same as 0). **TargetDown** for `job="minecraft"` covers that case.

---

## 1. Confirm (1 min)

1. Prometheus → **Alerts**: `http://100.66.160.124:9090/alerts` — which `server_host` is firing?
2. From the Beelink:
   ```bash
   curl -s http://100.105.219.6:9150/metrics | grep minecraft_status_healthy
   ```
   `0` = server not answering. No output = mc-monitor or the network is the problem (see TargetDown runbook).

## 2. Diagnose (on the NAS)

```bash
ssh nas
cd /opt/stacks/nas/gameservers/minecraft     # ALWAYS run docker compose from here
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker compose logs prominence2 --tail 50
docker stats --no-stream
```

| What you see | Usually means |
|---|---|
| `Exited (0)` | Stopped cleanly — someone ran `docker compose stop` (or a drill wasn't finished) |
| `Exited (1)` / `Exited (137)` | Crashed. 137 = killed, often out of memory |
| `Restarting` | Crash loop — read the logs |
| `Up`, but no `Done (…s)!` in the logs yet | Still starting. A modpack can take minutes, longer on first start or after an update |
| `java.lang.OutOfMemoryError` in logs | Modpack needs more than `MEMORY` |
| `Can't keep up!` repeating for 10+ min | Overloaded — world generation or too many players. Not the same as down |
| Mod list it **couldn't download** | CurseForge blocked automatic download for some mods — see the itzg "Auto CurseForge" docs |

## 3. Fix

| Cause | Fix |
|---|---|
| Stopped | `docker compose start prominence2` |
| Crashed once | `docker compose start prominence2`, then watch the logs |
| Out of memory | Raise `MEMORY` in `compose.yaml` → `docker compose up -d`. Check the NAS has room (Grafana → Node Exporter Full → RAM available) |
| Crash loop after a modpack or image change | Put the previous `CF_PAGE_URL` file ID / image tag back → `docker compose up -d`. Restore the world from backup if it was damaged |
| Container missing (after `down`) | `docker compose up -d` |
| Host rebooted, container didn't come back | `docker compose up -d` and check `restart: unless-stopped` is set |

**Always name the service.** mc-monitor lives in the same compose file, so commands without a service name hit it too:

| Command | Effect | Alert you get |
|---|---|---|
| `docker compose stop prominence2` | Stops **only the server** | MinecraftDown |
| `docker compose stop` | Stops **everything in the file**, mc-monitor included | TargetDown (no data, so MinecraftDown can't fire) |
| `docker compose down` | **Removes** everything in the file (world data is safe) | TargetDown |

## 4. Verify — the incident isn't over until all of these are true

- [ ] `docker compose logs -f prominence2` shows **`Done (…s)!`**
- [ ] `docker ps` shows `prominence2` **Up (healthy)**
- [ ] mc-monitor shows `minecraft_status_healthy … 1`
- [ ] **`[RESOLVED] MinecraftDown` arrived on the phone** ← don't skip this
- [ ] You (or a friend) can join

## 5. Follow up

- [ ] Real outage or drill? Write it up in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Add a row to the History table below and to the brag doc's Incidents table
- [ ] Step missing or wrong? Update this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| 2026-11-18 | Drill: `stop prominence2` → alert → `start` → resolved (full checklist) | ~2–3 min | ~5 min (est.) | None (drill went to plan) |
| 2026-11-17 | Drill: stopped `prominence2` on purpose; not restarted afterwards | ~3–4 min | ~9 h | `docs/postmortems/2026-11-17-minecraft-down-drill.md` |
