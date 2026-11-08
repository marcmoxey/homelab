# Runbook: Watchdog DOWN (dead man's switch)

| | |
|---|---|
| **Alert** | healthchecks.io email: **"beelink-watchdog is DOWN"** |
| **Fires when** | healthchecks.io gets no ping for 5 min (period) + 5 min (grace) |
| **Meaning** | Something in the alerting chain is broken: Beelink → Prometheus → `Watchdog` rule → Alertmanager → internet → healthchecks.io |
| **Impact** | **No alerts can reach the phone.** Assume other problems may be going unnoticed. |
| **Notified via** | Email from healthchecks.io (outside the homelab) |
| **Expected detection time** | ~10 min after alerting breaks |

## How the chain works

1. Prometheus evaluates `Watchdog` (`expr: vector(1)`) — always firing — in `monitoring/prometheus/rules/alerts.yml`
2. Alertmanager routes `alertname="Watchdog"` to receiver `deadman-switch` (`group_interval: 1m`, `repeat_interval: 1m`) in `monitoring/alertmanager/alertmanager.yml`
3. That receiver's webhook reads the ping URL from `url_file: /etc/alertmanager/secrets/healthchecks_url`
4. Host file: `/opt/stacks/monitoring/alertmanager/secrets/healthchecks_url` (git-ignored; copy kept in password manager)
5. healthchecks.io check `beelink-watchdog` expects a ping every 5 min

---

## 1. Can I reach the Beelink? (1 min)

```bash
ssh beelink                            # over Tailscale
ssh mmoxey@<beelink-LAN-IP>            # fallback from home if Tailscale is down
```

- **Neither works** → Beelink is off, frozen, or off the network. Check power and cable, check the Archer's connected devices, power-cycle if needed. Once it's back, go to **step 4**.
- **Works** → continue.

## 2. Diagnose the chain (on the Beelink)

```bash
cd /opt/stacks/monitoring              # ALWAYS run docker compose from here
docker compose ps                      # prometheus + alertmanager should be "Up", not "Restarting"
```

Then follow the chain in order — stop at the first broken link:

| # | Check | Command / place | Healthy looks like |
|---|---|---|---|
| a | Prometheus running | `docker compose logs prometheus --tail 30` | `Server is ready to receive web requests`, no `Error loading config` |
| b | Watchdog firing | `http://100.66.160.124:9090/alerts` | **Watchdog = Firing** |
| c | Alertmanager running | `docker compose logs alertmanager --tail 30` | No webhook / `url_file` errors |
| d | Alertmanager has it | `http://100.66.160.124:9093` | **Watchdog** listed |
| e | Secret file present | `ls -la alertmanager/secrets/` | `healthchecks_url` is a **file** (`-rw-r--r--`), not a directory |
| f | Secret mounted | `grep -n "secrets" compose.yaml` | `./alertmanager/secrets:/etc/alertmanager/secrets:ro` (note the `./`) |
| g | Internet working | `curl -sI https://hc-ping.com \| head -1` | `HTTP/2 200` or similar |
| h | healthchecks.io itself | https://status.healthchecks.io | All systems operational (if not → false alarm) |

## 3. Fix

| Broken link | Fix |
|---|---|
| a — Prometheus crash-looping | Read the error, fix `prometheus/prometheus.yml`, **validate** (below), `docker compose restart prometheus` |
| b — Watchdog not firing | Check the rule in `prometheus/rules/alerts.yml` → validate → `docker compose restart prometheus` |
| c/d — Alertmanager stopped or erroring | `docker compose start alertmanager`; validate its config (below); `docker compose restart alertmanager` |
| e — Secret file missing | `echo -n '<ping URL from password manager>' > alertmanager/secrets/healthchecks_url && chmod 644 alertmanager/secrets/healthchecks_url` then `docker compose restart alertmanager` |
| e — It's a directory, not a file | Docker created it because the file was missing at start: `docker compose down`, `sudo rm -r alertmanager/secrets/healthchecks_url`, recreate the file, `docker compose up -d` |
| f — Mount missing | Add the volume line to the `alertmanager` service, `docker compose up -d` (should say **Recreated**) |
| g — No internet | Check the Archer / ISP; nothing to fix on the Beelink |
| Docker itself down | `sudo systemctl status docker` → `sudo systemctl restart docker` → `cd /opt/stacks/monitoring && docker compose up -d` |

### Validate before restarting (always)
```bash
cd /opt/stacks/monitoring
docker run --rm -v "$PWD/prometheus:/etc/prometheus" --entrypoint promtool \
  prom/prometheus:v3.13.5 check config /etc/prometheus/prometheus.yml
docker run --rm -v "$PWD/alertmanager:/etc/alertmanager" --entrypoint amtool \
  prom/alertmanager:<pinned-version> check-config /etc/alertmanager/alertmanager.yml
```

## 4. Verify

- [ ] healthchecks.io emails **"beelink-watchdog is UP"**
- [ ] healthchecks.io **Total Pings** climbs about once per minute
- [ ] `docker compose ps` — all 6 containers **Up**
- [ ] **Alerting was blind during the outage** — check Prometheus **Alerts** and **Target health** for anything that broke in that window

## 5. Follow up

- [ ] Write a postmortem — include **how long alerting was blind** (last ping → UP), not just healthchecks.io's "downtime" number (it counts from when it *declared* down)
- [ ] Add a row to the brag doc's Incidents table
- [ ] Update this runbook if a step was missing

## History

| Date | What happened | Detect | Blind window | Postmortem |
|---|---|---|---|---|
| 2026-11-08 | Prometheus crash loop from `evalutation_interval` typo | ~3 min (manual) | ~5 min | Covered in the dead man's switch postmortem |
| 2026-11-08 | Alertmanager stopped (drill) | ~10 min (3:54 → 4:04 PM) | ~12 min (3:54 → 4:06 PM) | `docs/postmortems/2026-11-08-alertmanager-deadmans-drill.md` |
