# Runbook: LowMemory

| | |
|---|---|
| **Alert** | `LowMemory` (severity: warning) |
| **Rule** | `node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10` for 10m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | A host (NAS or Beelink) has had less than 10% of its RAM available for 10 minutes |
| **Impact** | Nothing broken yet — but if RAM runs out, Linux's **OOM killer** kills the biggest process. On the NAS that's usually Minecraft (`prominence2`) |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~11 min (15s scrape + 10m `for` + 30s `group_wait`) — slow on purpose, so short spikes don't page |
| **Does NOT cover** | A single container hitting its own `mem_limit` while the host is fine (the container restarts; MinecraftDown / TargetDown catch it); swap thrashing |

## How the check works

node_exporter on each host reports `MemAvailable` (RAM the kernel can hand out without swapping) and `MemTotal`. The rule divides them.

| Host | Normal RAM use | Instance |
|---|---|---|
| NAS (64 GB) | ZFS ARC up to 16 GB + `prominence2` ~11 GB + exporters ~1 GB → ~35 GB free | `100.105.219.6:9100` |
| Beelink | Prometheus, Grafana, Alertmanager, ntfy — a few GB | `100.66.160.124:9100` |

**ZFS note (NAS):** the ZFS cache (ARC) is *not* counted as "available" by Linux, even though ZFS gives it back under pressure. That's why it's capped at 16 GiB (`/etc/modprobe.d/zfs.conf`) — so it can never push this alert on its own.

---

## 1. Confirm (1 min)

Which host? Check the alert's `instance` label, then:

```bash
ssh nas            # or: ssh beelink
free -h            # look at the "available" column
```

Grafana → **Node Exporter Full** → pick the host → **Memory**: is it a sudden drop, or a slow climb over hours/days?

## 2. Diagnose

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'   # biggest containers
ps aux --sort=-%mem | head -10                                                      # biggest processes overall
sudo dmesg -T | grep -i -E "out of memory|oom-kill|killed process" | tail          # did the OOM killer already act?
```

NAS only — how big is the ZFS cache right now?

```bash
awk '/^size/ {printf "ARC size: %.1f GiB\n", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats
cat /sys/module/zfs/parameters/zfs_arc_max      # should be 17179869184 (16 GiB)
```

Grafana → **cAdvisor dashboard** → **Memory usage per container**: which line is climbing?

| What you see | Usually means |
|---|---|
| One container climbing for hours and never coming down | Memory leak in that app |
| `prominence2` well above ~11 GB | Modpack using more than planned, or many players + world generation |
| A new service just added | Not enough RAM budgeted for it |
| ARC above 16 GiB / `zfs_arc_max` is `0` | ARC cap not applied (lost after a reboot?) |
| `oom-kill` lines in `dmesg` | Linux already killed something — find out what, and restart it |

## 3. Fix

| Cause | Fix |
|---|---|
| A leaking container | Restart just that one: `docker compose restart <service>` (in its folder). Note it, and watch if it climbs again |
| Minecraft too big | Lower `MEMORY` or set/lower `mem_limit` in `nas/gameservers/minecraft/compose.yml` → `docker compose up -d` (restarts the server — warn players) |
| Too many services for the RAM | Stop something not needed right now; plan before adding more (a second modpack ≈ +10 GB) |
| ARC cap missing | `echo 17179869184 \| sudo tee /sys/module/zfs/parameters/zfs_arc_max`, then check `/etc/modprobe.d/zfs.conf` and run `sudo update-initramfs -u` |
| Something was OOM-killed | Restart it (`docker compose start <service>`), then deal with whatever used the memory |

**Don't:** reboot the host as the first move — it hides which process was the problem; turn off the OOM killer; raise the alert threshold just to make it stop.

## 4. Verify (the incident isn't over until all are true)

- [ ] `free -h` → "available" back above ~10% (NAS: several GB free)
- [ ] The memory graph is flat again, not still climbing
- [ ] Prometheus → Alerts → `LowMemory` **Inactive**
- [ ] **`[RESOLVED] LowMemory` arrived on the phone**
- [ ] Every service that was killed is back up (`docker ps`, MinecraftDown resolved)

## 5. Follow up

- [ ] Real event? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md` — especially if something was OOM-killed
- [ ] Needs a permanent fix? (`mem_limit` on the container, a RAM budget in the design doc, fewer services)
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| | | | | |
