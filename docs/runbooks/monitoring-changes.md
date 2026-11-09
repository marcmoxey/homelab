# Runbook: Making changes to the monitoring stack safely

Use this every time you edit anything in `/opt/stacks/monitoring`. Every rule below comes from a real mistake on 2026-11-08.

## Layout (Beelink)

```
/opt/stacks/                        ← Git repo (github.com/marcmoxey/homelab)
├── .gitignore
├── docs/
│   ├── postmortems/
│   └── runbooks/
└── monitoring/                     ← ALWAYS run `docker compose` from here
    ├── compose.yaml
    ├── .env                        ← SECRET (Grafana admin) — git-ignored
    ├── prometheus/
    │   ├── prometheus.yml
    │   └── rules/alerts.yml
    ├── grafana/provisioning/datasources/
    ├── ntfy/server.yml
    ├── ntfy-alertmanager/config    ← SECRET (ntfy token) — git-ignored
    └── alertmanager/
        ├── alertmanager.yml
        └── secrets/healthchecks_url  ← SECRET (ping URL) — git-ignored
```

## Services and ports (all bound to Tailscale IP 100.66.160.124)

| Service | Port | Image (pinned) |
|---|---|---|
| prometheus | 9090 | `prom/prometheus:v3.13.5` (LTS) |
| node-exporter | 9100 (host network) | `quay.io/prometheus/node-exporter:v1.12.1` |
| grafana | 3000 | `grafana/grafana-oss:13.0.2` |
| ntfy | 8080 → 80 | `binwiederhier/ntfy:v2.37.2` |
| alertmanager | 9093 | `prom/alertmanager:v0.34.2` (clustering off: `--cluster.listen-address=`) |
| ntfy-alertmanager | none (internal only) | `xenrox/ntfy-alertmanager:1.0.2` |

---

## The change procedure

### 1. Go to the right folder
```bash
cd /opt/stacks/monitoring
```
`docker compose` only works where `compose.yaml` lives. From `/opt/stacks` it fails with *"no configuration file provided."*

### 2. Create files BEFORE `docker compose up`
If a bind-mounted file doesn't exist when a container starts, **Docker creates a root-owned empty directory in its place**, and the container fails with *"Are you trying to mount a directory onto a file?"*
```bash
ls -la <folder>/        # the file must show as -rw-, owned by mmoxey
```
Fix if it happened: `docker compose down`, `sudo rm -r <path>`, recreate the file.

### 3. Validate before restarting
```bash
# Prometheus — validates prometheus.yml AND every rules file
docker run --rm -v "$PWD/prometheus:/etc/prometheus" --entrypoint promtool \
  prom/prometheus:v3.13.5 check config /etc/prometheus/prometheus.yml

# Alertmanager
docker run --rm -v "$PWD/alertmanager:/etc/alertmanager" --entrypoint amtool \
  prom/alertmanager:v0.34.2 check-config /etc/alertmanager/alertmanager.yml

# Compose file
docker compose config > /dev/null && echo "compose OK"
```
- Run these from `/opt/stacks/monitoring`. Running promtool from inside `prometheus/` creates a stray root-owned `prometheus/prometheus/` directory.
- Use `check config`, not `check rules` — `check rules` skips `prometheus.yml` (that's how the `evalutation_interval` typo got through).

### 4. Apply
| You changed | Run |
|---|---|
| `compose.yaml` (images, ports, volumes, env, command) | `docker compose up -d` — changed services should say **Recreated** |
| Anything, after a power loss or crash | `docker compose up -d --force-recreate` |
| `prometheus.yml` or rules | `docker compose restart prometheus` |
| `alertmanager.yml` | `docker compose restart alertmanager` |
| ntfy `server.yml` / bridge `config` | `docker compose restart ntfy` / `ntfy-alertmanager` |

### 5. Confirm it's actually running
```bash
docker compose ps           # every container "Up" — "Restarting (N)" means it's crash-looping
docker compose logs <service> --tail 20
```
Wait ~30 seconds and run `docker compose ps` again — a crash loop can look "Up" for the first second.
Also check the **PORTS** column: prometheus, grafana, ntfy and alertmanager must show `100.66.160.124:...`. "Up" with no ports means broken networking → `docker compose up -d --force-recreate`.

### 5b. After host-level changes, test a reboot
Changed anything on the host itself (sysctl, UFW, Docker, Tailscale, packages)? Run `sudo reboot`, then **without touching anything** run `docker compose ps`. All 6 must come back Up with ports. A setup that has never been rebooted hasn't been tested.

### 6. Commit
```bash
cd /opt/stacks
git status                  # these must NEVER appear:
                            #   monitoring/.env
                            #   monitoring/ntfy-alertmanager/config
                            #   monitoring/alertmanager/secrets/
git add -A monitoring docs .gitignore
git commit -m "<what changed and why>"
git push
```

---

## YAML rules of thumb
- Spaces only, never tabs. Each nesting level = **2 spaces**. In nano, `Alt+P` shows whitespace.
- Items in the same list (e.g. each `- job_name:`) start in the **same column**.
- Bind mounts start with `./` or `/`. A bare name (`alertmanager_data`) is a **named volume** and must be declared under the top-level `volumes:`.
- Image tags use a colon: `prom/alertmanager:v0.xx.y` — not a slash.

## Image tags
- Pin full versions (`v3.13.5`, `1.0.2`). Avoid `latest`, `main`, nightly, and floating tags like `v0`.
- Prometheus: stay on the **LTS** line (3.13.x, supported until 2027-07-31).
- Upgrade on purpose: change the tag → `docker compose up -d` → verify → commit. To roll back, change the tag back.

## Things that live OUTSIDE Git (rebuild checklist)
| Item | Where | Restore from |
|---|---|---|
| UFW rule | `sudo ufw allow from 172.16.0.0/12 to any port 9100 proto tcp comment 'prometheus -> node_exporter'` | This runbook |
| Bind to Tailscale IP before it's up | `/etc/sysctl.d/99-tailscale-bind.conf` → `net.ipv4.ip_nonlocal_bind = 1` | This runbook |
| Grafana admin creds | `monitoring/.env` | Password manager |
| ntfy users | `ntfy` volume: `shadvonic` (admin), `alertmanager` (write-only on `homelab-alerts`) | Recreate with `docker exec -it ntfy ntfy user add ...` |
| ntfy bridge token | `monitoring/ntfy-alertmanager/config` | `docker exec -it ntfy ntfy token add alertmanager` |
| healthchecks ping URL | `monitoring/alertmanager/secrets/healthchecks_url` | Password manager / healthchecks.io |
| healthchecks.io integrations | Discord + email on check `beelink-watchdog` | healthchecks.io → Integrations |
| Grafana dashboard 1860 | `grafana_data` volume | Re-import from grafana.com |

