# Runbook: TargetDown

| | |
|---|---|
| **Alert** | `TargetDown` (severity: critical) |
| **Rule** | `up == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | Prometheus can't scrape a target for 2+ minutes |
| **Impact** | No metrics from that target; alerts that depend on it can't fire |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy topic `homelab-alerts` → phone |
| **Expected detection time** | ~2.5–3 min (15s scrape + 15s evaluation + 2m `for` + 30s `group_wait`) |

## Current targets

| Job | Target | Runs as |
|---|---|---|
| `prometheus` | `localhost:9090` | Container `prometheus` (Compose network) |
| `node` | `100.66.160.124:9100` | Container `node-exporter` (`network_mode: host`, listens on Tailscale IP only) |

---

## 1. Confirm (1 min)

1. Open **Prometheus → Status → Target health**: `http://100.66.160.124:9090/targets`
2. Note which **job / instance** is DOWN and the **error** text.

| Error text | Usually means |
|---|---|
| `connection refused` | Nothing listening on that port — container stopped or crashed |
| `context deadline exceeded` / timeout | Something is blocking traffic — firewall (UFW) or network |
| `no such host` | Name doesn't resolve — wrong target in `prometheus.yml` |

> If you can't open the Prometheus UI at all, Prometheus itself may be down. The Watchdog / dead man's switch will also fire — see `watchdog-down.md`.

## 2. Diagnose (on the Beelink)

```bash
ssh beelink                          # over Tailscale
cd /opt/stacks/monitoring            # ALWAYS run docker compose from here

docker compose ps                    # Up? Exited? Restarting?
docker compose logs <service> --tail 30
```

**If the down target is `node` (node_exporter):**
```bash
# Is node_exporter answering on the host?
curl -s http://100.66.160.124:9100/metrics | head -3

# Is the firewall rule that lets Prometheus's container reach it still there?
sudo ufw status numbered             # expect: 9100/tcp ALLOW IN 172.16.0.0/12  # prometheus -> node_exporter

# Is Tailscale up? (node_exporter binds to the Tailscale IP)
tailscale ip -4                      # expect 100.66.160.124
sudo tailscale status
```

## 3. Fix

| Cause | Fix |
|---|---|
| Container stopped | `docker compose start <service>` |
| Container crash-looping (`Restarting`) | Read `docker compose logs <service> --tail 30`. If it's a config error, fix the file, validate (step 3a), then `docker compose restart <service>` |
| curl works but Prometheus says timeout | UFW rule missing → `sudo ufw allow from 172.16.0.0/12 to any port 9100 proto tcp comment 'prometheus -> node_exporter'` |
| Tailscale down / IP changed | `sudo systemctl restart tailscaled` then `sudo tailscale up`; if the 100.x IP changed, update `prometheus.yml`, `compose.yaml` ports, and `--web.listen-address` |
| Whole Beelink unreachable | Check power/cable; try LAN SSH `ssh mmoxey@<beelink-LAN-IP>`; check the Archer's client list; power-cycle |

### 3a. Validate before restarting (always)
```bash
cd /opt/stacks/monitoring
docker run --rm -v "$PWD/prometheus:/etc/prometheus" --entrypoint promtool \
  prom/prometheus:v3.13.5 check config /etc/prometheus/prometheus.yml
```
Must say **SUCCESS** for the config **and** the rules file. Use `check config`, not `check rules` — only `check config` validates `prometheus.yml`.

## 4. Verify

- [ ] Target health shows **UP**
- [ ] Query `up` returns **1** for that target
- [ ] **Resolved** notification arrives on the phone (~1–2 min after recovery)
- [ ] `docker compose ps` — every container **Up**, none **Restarting**

## 5. Follow up

- [ ] Not a drill? Write a postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Add a row to the brag doc's Incidents table
- [ ] Was a step here missing or wrong? Update this runbook and commit

## History

| Date | What happened | Detect | Fix | Postmortem |
|---|---|---|---|---|
| 2026-11-08 | node_exporter stopped (drill) | ~3 min | <1 min | `docs/postmortems/2026-11-08-node-exporter-drill.md` |
