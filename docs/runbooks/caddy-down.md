# Runbook: Public access down (Caddy)

| | |
|---|---|
| **Alert** | `ServiceDown{service="jellyfin-public"}` (critical) or `ServiceDown{service="seerr-public"}` (warning); also `CertExpiringSoon` |
| **Rule** | `probe_success == 0` for 2m — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | The Beelink can't load `https://watch.marcshometheater.org/health` or `https://request.marcshometheater.org/api/v1/status` through the public path (DNS → router → Caddy → app) |
| **Impact** | Friends and family **outside** the house can't watch or request. Home users usually still work (Pi-hole sends them straight to the NAS), as does everything over Tailscale |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~3 min (15s scrape + 2m `for` + 30s `group_wait`) |
| **Does NOT cover** | Jellyfin or Seerr themselves being down (the internal probes `jellyfin`/`seerr` fire too → [media-down.md](media-down.md)); slow streaming; one friend's app misconfigured |

**Note:** the Beelink is inside the house. If it uses Pi-hole for DNS, its probe of the public
names goes straight to `192.168.0.231` and tests **Caddy + certificates + apps**, but not the
router forward or public DNS. Always confirm from outside (step 1).

## How public access works

```
friend → watch.marcshometheater.org
       → Cloudflare DNS (A record, grey cloud, kept current by the cloudflare-ddns container)
       → home public IP
       → router: 80/443 → 192.168.0.231
       → Caddy (container `caddy`, nas/media) → jellyfin:8096 / seerr:5055
```

| Piece | Where | Details |
|---|---|---|
| Caddy | NAS, `nas/media/compose.yml` + `nas/media/caddy/Caddyfile` | Binds `192.168.0.231:80/443` |
| Certificates | `/opt/appdata/media/caddy/data` | Let's Encrypt, auto-renewed by Caddy |
| DNS | Cloudflare dashboard → `marcshometheater.org` → DNS | A records `watch`, `request` → home public IP, DNS only (grey) |
| DDNS | NAS, `nas/ddns/compose.yml` (container `cloudflare-ddns`) | Updates both A records every 5 min; token in `nas/ddns/.env` + Vaultwarden |
| Port forwards | TP-Link router → NAT Forwarding → Virtual Servers | 80 TCP, 443 TCP+UDP → `192.168.0.231` |
| Home shortcut | Pi-hole → Local DNS | Both names → `192.168.0.231` |

---

## 1. Confirm (2 min) — from outside, then inside

From your phone **on cellular (Wi-Fi off)**: open `https://watch.marcshometheater.org`.

| Phone result | Means |
|---|---|
| Login page, padlock | Public path works — problem is the probe or the Beelink (go to 2, "probe only") |
| "Can't connect" / times out | DNS, router, or Caddy (go to 2) |
| Certificate warning | Certificates (go to 2) |
| `502 Bad Gateway` | Caddy is up, the app behind it is down → [media-down.md](media-down.md) |

On the NAS:

```bash
cd /opt/stacks/nas/media
docker compose ps caddy jellyfin seerr
docker compose logs --tail=50 caddy
curl -sI --resolve watch.marcshometheater.org:443:192.168.0.231 https://watch.marcshometheater.org/health
```

The last line tests Caddy + certificate + Jellyfin from inside, bypassing DNS and the router.

## 2. Diagnose

```bash
curl -4 -s ifconfig.me; echo                                  # current public IP
nslookup watch.marcshometheater.org 1.1.1.1                   # public DNS answer (should match)
docker compose -f /opt/stacks/nas/ddns/compose.yml ps         # DDNS container running?
docker compose -f /opt/stacks/nas/ddns/compose.yml logs --tail=20
sudo ss -tlnp | grep -E ':(80|443) '                          # Caddy listening?
```

| What you see | Usually means |
|---|---|
| `caddy` not running / restarting | Bad Caddyfile or container crashed — logs show the line |
| Logs: `crowdsec API key must not be empty` | `CROWDSEC_CADDY_KEY` missing from `nas/media/.env` (compose warned "variable is not set") |
| Some visitors get `403`, others fine | CrowdSec banned their IP: `docker exec crowdsec cscli decisions list` |
| Caddy logs: `obtaining certificate` errors, `timeout`, `connection refused` | Let's Encrypt can't reach you: port forward missing, ISP blocking, or DNS wrong |
| DNS IP ≠ current public IP | DDNS container stopped, or its logs show an auth error (token rolled/expired/deleted) |
| Public DNS NXDOMAIN for `watch` | A record deleted, container never ran, or domain expired (check auto-renew) |
| DNS right, Caddy fine from inside, phone can't connect | Router port forward gone (router reboot/reset/firmware update), or the NAS's LAN IP changed |
| `502` from Caddy | Jellyfin/Seerr down or renamed — Caddy reaches them by container name |
| Certificate expired / `CertExpiringSoon` | Renewals failing for weeks — see the Caddy logs for why (usually ports 80/443) |

## 3. Fix

| Cause | Fix |
|---|---|
| Caddy stopped | `docker compose up -d caddy` |
| CrowdSec key missing | `docker exec crowdsec cscli bouncers delete caddy-bouncer && docker exec crowdsec cscli bouncers add caddy-bouncer`; put the key in `.env` (`CROWDSEC_CADDY_KEY=`), `docker compose up -d caddy`. **Fast rollback:** comment out the `crowdsec {…}` block and the two `crowdsec` lines in the Caddyfile, `up -d caddy` |
| Someone wrongly banned | `docker exec crowdsec cscli decisions delete --ip <ip>`; if it's a regular, add their range to `crowdsec/whitelist.yaml` |
| Caddyfile error | Fix `nas/media/caddy/Caddyfile`, check with `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile`, then `docker compose restart caddy` |
| Port forward missing | Router → NAT Forwarding → Virtual Servers: 80 TCP, 443 TCP+UDP → `192.168.0.231` |
| NAS IP changed | Set a DHCP reservation for the NAS at `192.168.0.231` in the router, update the forwards |
| DDNS container stopped | `cd /opt/stacks/nas/ddns && docker compose up -d` — it re-checks and fixes the records on start |
| DDNS auth error | Token rolled/expired/deleted: Cloudflare → My Profile → API Tokens → Roll (DNS Edit, zone `marcshometheater.org` only), update `nas/ddns/.env` + Vaultwarden, `docker compose up -d` |
| DNS record wrong/missing | Let the container recreate it (`docker compose restart` in `nas/ddns`); records must be **A, grey cloud** — no CNAMEs on `watch`/`request` |
| Domain expired | Cloudflare → Registrar → renew; keep auto-renew on |
| Certificates stuck | Fix the port/DNS cause first, then `docker compose restart caddy` — Caddy retries automatically |

**Don't:** turn on the orange cloud (proxying) to "fix" it — streaming through Cloudflare's proxy
breaks their terms; forward any other port to "test"; delete `/opt/appdata/media/caddy/data`
(Let's Encrypt rate-limits re-issuing certificates).

## 4. Verify (the incident isn't over until all are true)

- [ ] Phone on cellular: both URLs load with a padlock; Jellyfin app plays a video
- [ ] Phone on home Wi-Fi: same URLs still work (Pi-hole path)
- [ ] `docker compose logs caddy` shows no new certificate errors
- [ ] Prometheus → Alerts → `ServiceDown` for jellyfin-public / seerr-public **Inactive**
- [ ] **`[RESOLVED] ServiceDown` arrived on the phone**

## 5. Follow up

- [ ] Real outage? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Tell friends/family it's back if they noticed
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History

| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| 2026-11-21 | **Real outage:** Caddy recreated with the CrowdSec bouncer while `CROWDSEC_CADDY_KEY` was missing from `.env`; Caddy refused to load its config (crash loop) | Found in `docker compose logs caddy` while checking the change | ~6 min (11:33 → 11:39 AM) | — (follow-up: treat compose "variable is not set" as an error) |
| 2026-11-20 | Drill: stopped Caddy right after go-live; both public probes (jellyfin-public critical, seerr-public warning) fired together as one grouped alert | FIRING 5:38 PM | ~5 min (RESOLVED 5:43 PM) | — |
