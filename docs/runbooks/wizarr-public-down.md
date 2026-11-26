# Runbook: ServiceDown — wizarr-public

| | |
|---|---|
| **Alert** | `ServiceDown` with `service="wizarr-public"` (severity: warning) |
| **Rule** | `probe_success{service="wizarr-public"} == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't load `https://invite.<your-domain>` with a 2xx/3xx answer for 2 minutes |
| **Impact** | Friends can't use invite links to sign up. Existing users are **not** affected: Jellyfin and Seerr keep working. |

## What's involved

| Piece | Where | Details |
|---|---|---|
| Wizarr | NAS, `nas/media/compose.yml`, container `wizarr` | Port 5690, bound to LAN + Tailscale only |
| Data | NAS NVMe | `/opt/appdata/wizarr/database`, `/opt/appdata/wizarr/wizard_steps` |
| Public route | Caddy, `nas/media/caddy/Caddyfile` | `invite.<your-domain>` → CrowdSec → `wizarr:5690` |
| DNS | Cloudflare (grey cloud), kept current by `nas/ddns` | `invite` must be in the DDNS `DOMAINS` list |
| Secrets | Wizarr's own database | Admin login in the password manager; Jellyfin API key "Wizarr" |

If **every** public site is down at once (`jellyfin-public`, `seerr-public` too), start with [caddy-down.md](caddy-down.md) instead: it's Caddy, the router or the ISP, not Wizarr.

## Check

    cd /opt/stacks/nas/media
    docker compose ps wizarr                                   # running?
    docker compose logs --tail=50 wizarr                       # errors?
    docker exec caddy wget -qO- http://wizarr:5690 | head -3   # Caddy can reach it?
    curl -sI https://invite.<your-domain> | head -1            # 302 = fine
    dig +short invite.<your-domain> @1.1.1.1                   # public IP, same as watch.

## Diagnose

| Symptom | Likely cause |
|---|---|
| `wizarr` not running / restarting | Crash or bad config: read its logs |
| Caddy `wget` says `bad address` | Wizarr not on Caddy's Docker network (not in the same compose file) |
| `dig` returns nothing or a 192.168.x.x address | Cloudflare record missing or wrong; `invite` dropped from DDNS `DOMAINS` |
| Certificate error in the browser | Caddy couldn't get a certificate (usually DNS was wrong when it tried) and is in back-off |
| Works outside, fails at home | Pi-hole cached an old "doesn't exist" answer |

## Fix

| Problem | Fix |
|---|---|
| Container stopped/crashed | `docker compose up -d wizarr` (in `nas/media`) |
| DNS wrong | Fix the Cloudflare record (public IP, grey cloud), check `DOMAINS` in `nas/ddns/compose.yml`, `docker compose up -d` there |
| Certificate back-off | After DNS is right: `docker compose restart caddy`, then `docker logs caddy --since 2m \| grep -i invite` → "certificate obtained successfully" |
| Pi-hole cache | On the Pi: `sudo systemctl restart pihole-FTL`; on the NAS: `sudo resolvectl flush-caches` |

**Don't:** publish port 5690 to the internet directly (always through Caddy + CrowdSec); turn off "hide new users from login screens"; share the admin login.

## Verify

- [ ] `docker compose ps wizarr` → running
- [ ] `curl -sI https://invite.<your-domain>` → `HTTP/2 302`
- [ ] Prometheus → Targets → `wizarr-public` **UP**
- [ ] Prometheus → Alerts → `ServiceDown{service="wizarr-public"}` **Inactive**
- [ ] **`[RESOLVED]` arrived on the phone**

## History

| Date | What happened | Down | Fixed | Postmortem |
|---|---|---|---|---|
| 2026-11-26 | Set up. Caddy and Pi-hole cached NXDOMAIN because the Caddy block went live before the DNS record existed | — (not live yet) | Restart Caddy + pihole-FTL | — |
