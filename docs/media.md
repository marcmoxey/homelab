# Media stack (nas/media)

Request → download → organize → watch, all on the NAS, reachable only from the home LAN and Tailscale.

```
Seerr (request) → Radarr / Sonarr → Prowlarr (indexers) → SABnzbd (Usenet)
   → /data/usenet/complete/{movies,tv} → hardlinked into /data/media/{movies,tv,anime}
   → Jellyfin (watch)   + Bazarr (subtitles)   + Clonarr (TRaSH profiles)   + Jellystat (stats)
```

TRaSH Guides layout: every app that moves files mounts the whole `/data`, so imports are
**hardlinks** (instant, no extra space) and every app sees identical paths, so **no path
mappings are needed anywhere**.

## Services

| App | Browser | From other containers | Config (NVMe) | Data mount |
|---|---|---|---|---|
| SABnzbd | http://nas:8085 | `sabnzbd:8080` | `/opt/appdata/media/sabnzbd` | `/data/usenet` |
| Prowlarr | http://nas:9696 | `prowlarr:9696` | `/opt/appdata/media/prowlarr` | none |
| Radarr | http://nas:7878 | `radarr:7878` | `/opt/appdata/media/radarr` | `/data` |
| Sonarr | http://nas:8989 | `sonarr:8989` | `/opt/appdata/media/sonarr` | `/data` |
| Jellyfin | http://nas:8096 | `jellyfin:8096` | `/opt/appdata/media/jellyfin` | `/data/media` (read-only) + `/dev/dri` |
| Seerr | http://nas:5055 | `seerr:5055` | `/opt/appdata/media/seerr` | none |
| Bazarr | http://nas:6767 | `bazarr:6767` | `/opt/appdata/media/bazarr` | `/data` |
| Clonarr | http://nas:6060 | `clonarr:6060` | `/opt/appdata/media/clonarr` | none |
| Jellystat | http://nas:3001 | `jellystat:3000` | `/opt/appdata/media/jellystat` | none |
| Jellystat DB | — | `jellystat-db:5432` | `/opt/appdata/media/jellystat/db` | none |
| Caddy | — (public: 80/443) | `caddy` | `/opt/appdata/media/caddy/{data,config}` + `nas/media/caddy/Caddyfile` | none |
| cloudflare-ddns | — (no ports) | — | none (`nas/ddns/.env` holds the token) | separate stack: `nas/ddns` |

All browser ports are bound to `192.168.0.231` and `100.105.219.6` only (Docker bypasses UFW).
Caddy binds 80/443 on `192.168.0.231` only (the router forwards there).
The apps run as UID/GID 1000 (mmoxey); Seerr does so by default, the others via PUID/PGID.

## Public access (friends and family outside the house)

Exactly two services are reachable from the internet, both through Caddy over HTTPS:

| URL | Goes to | Used for |
|---|---|---|
| https://watch.marcshometheater.org | `jellyfin:8096` | Jellyfin apps and browser (same address at home and away) |
| https://request.marcshometheater.org | `seerr:5055` | Requesting movies and shows |

Everything else (Vaultwarden, *arr apps, SABnzbd, BookStack, Immich, SSH, Samba) stays
LAN + Tailscale only.

**How a request gets in**

```
friend → watch.marcshometheater.org
       → (Cloudflare DNS, A record, grey cloud — updated every 5 min by the cloudflare-ddns container)
       → home public IP
       → router port forward 443 → 192.168.0.231:443 → Caddy → jellyfin:8096
```

| Piece | Where | Notes |
|---|---|---|
| Domain | Cloudflare Registrar: `marcshometheater.org` | Auto-renew on. Account has 2FA; login in Vaultwarden |
| DNS | Cloudflare: A records `watch` and `request` → home public IP | **DNS only (grey cloud).** Proxying (orange) is against Cloudflare's terms for video streaming. Records are managed by the DDNS container — don't edit them by hand |
| Dynamic IP | `nas/ddns` stack: `cloudflare-ddns` container (favonia/cloudflare-ddns) | Checks the public IP every 5 min and updates both A records when it changes. Runs as UID 1000, read-only, no capabilities |
| DDNS token | Cloudflare API token `nas-ddns-marcshometheater` | Scope: **Zone → DNS → Edit on `marcshometheater.org` only**. Stored in Vaultwarden and `nas/ddns/.env` (git-ignored). If leaked: Cloudflare → My Profile → API Tokens → Roll, update `.env`, `docker compose up -d` |
| Minecraft | TP-Link router DDNS `marcshomeserever.tplinkdns.com` | Separate; still used by Minecraft players. Not part of the media path |
| Port forwards | TP-Link router → NAT Forwarding → Virtual Servers | 80/TCP and 443/TCP+UDP → `192.168.0.231`. Plus 25565 for Minecraft. **Nothing else** |
| Reverse proxy | Caddy (`nas/media/caddy/Caddyfile`) | Only the two hostnames above are configured; any other name or bare IP gets nothing |
| Certificates | Let's Encrypt via Caddy, stored in `/opt/appdata/media/caddy/data` | Renewed automatically; `CertExpiringSoon` alerts at < 14 days |
| Home devices | Pi-hole local DNS: both names → `192.168.0.231` | Avoids hairpin NAT; home traffic goes straight to the NAS |

**App settings for the proxy**
- Jellyfin → Networking: Known proxies `caddy`; Published Server URIs `all=https://watch.marcshometheater.org`;
  LAN Networks `192.168.0.0/24`; internet streaming bitrate limit (e.g. 20 Mbps).
- Jellyfin → Users: strong passwords; login attempts before lockout 5.
- Seerr → General: Application URL `https://request.marcshometheater.org`; Enable Proxy Support on.

**Monitoring:** Beelink blackbox probes `https://watch.marcshometheater.org/health`
(`service: jellyfin-public`, critical) and `https://request.marcshometheater.org/api/v1/status`
(`service: seerr-public`, warning). Runbook: [caddy-down.md](runbooks/caddy-down.md).

**To check from outside:** phone on cellular (Wi-Fi off) → open both URLs; expect the login page and a padlock.

## Folders (ZFS pool, tank/data mounted at /data)

| Path | What |
|---|---|
| `/data/usenet/incomplete` | SABnzbd in-progress downloads |
| `/data/usenet/complete/movies`, `/tv` | Finished downloads (SABnzbd categories `movies`, `tv`), removed after import |
| `/data/media/movies` | Radarr root folder → Jellyfin "Movies" |
| `/data/media/tv` | Sonarr root folder → Jellyfin "Shows" |
| `/data/media/anime` | Sonarr anime root folder (Series Type: Anime) → Jellyfin "Anime" |

## Quality profiles (managed by Clonarr from TRaSH Guides)

| App | Profile | Used for |
|---|---|---|
| Radarr | HD Bluray + WEB | Default for movies |
| Sonarr | WEB-1080p | Default for TV |
| Sonarr | [Anime] Remux-1080p | Anime series (Language: Not Original, never "Not English") |

Auto-sync is **off**; review TRaSH updates in Clonarr → History, dry-run, then apply.
Change scores in Clonarr, not in Radarr/Sonarr (Clonarr overwrites them on sync).
Never run Recyclarr alongside Clonarr.

## Settings that live outside Git (set in each app's UI)

**SABnzbd** (`sabnzbd.ini`, edit only while the container is stopped):
- `local_ranges = 192.168.0.0/24, 100.64.0.0/10, 172.16.0.0/12` — LAN, Tailscale, Docker.
  Without it: "External internet access denied" in the browser, 403 from other apps.
- `host_whitelist = sabnzbd, nas` — without it: 403 when apps call it by name.
- Folders: temporary `/data/usenet/incomplete`, completed `/data/usenet/complete`.
- Categories: `tv` → `tv`, `movies` → `movies`.

**Radarr / Sonarr:** root folders above; Use Hardlinks instead of Copy = on; download client
SABnzbd (`sabnzbd`, `8080`, API key, category, no username/password); Connect → Jellyfin
(`jellyfin`, `8096`, Update Library on, Send Notifications off).

**Prowlarr:** Apps → Radarr (`http://radarr:7878`) and Sonarr (`http://sonarr:8989`),
Prowlarr server `http://prowlarr:9696`.

**Jellyfin:** libraries Movies / Shows / Anime (paths above); Intel QuickSync (QSV) hardware
transcoding; artwork saved in /config (media mount is read-only); separate API keys for
radarr, sonarr, bazarr, jellystat.

**Seerr:** Jellyfin sign-in (`http://jellyfin:8096`); Radarr and Sonarr as default servers with
the profiles above and anime root folder `/data/media/anime`; users imported from Jellyfin;
auto-approve for family, request limits for everyone.

**Bazarr:** hostname `bazarr`; Forms authentication; Sonarr/Radarr under Settings → Library
(SSL off, no path mappings, monitored-only on, defer search off, exclude season zero on);
English language profile as default for series and movies; providers OpenSubtitles.com +
1–2 free ones; Jellyfin media server with refresh after subtitle download.

**Clonarr:** Radarr and Sonarr instances by container name + API keys.

**Jellystat:** connected to `http://jellyfin:8096` with its own API key.

## Secrets (Vaultwarden + `nas/media/.env`, never in Git)

Usenet provider login, indexer API keys, every app's login and API key,
`JELLYSTAT_DB_PASSWORD`, `JELLYSTAT_JWT_SECRET`. `.env.example` shows the format.

## Common fixes

| Symptom | Fix |
|---|---|
| SABnzbd 403 / "API key incorrect" from an app | Check `local_ranges`, `host_whitelist`, and that the app has the current API key (the log shows the caller's IP and user agent) |
| Download never imports | Radarr/Sonarr → Activity → Queue shows the reason (usually paths or permissions) |
| Hardlink check | `ls -li` on the download and the library file: same inode number = hardlink |
| New subtitle not in player | Bazarr → Jellyfin integration on; or refresh the item in Jellyfin |
| Wrong poster/match | Jellyfin → item → Identify |# Media stack (nas/media)

Usenet → SABnzbd → Sonarr/Radarr → /data/media → Jellyfin. TRaSH Guides layout:
every app that moves files mounts the whole `/data`, so imports are hardlinks.

| App | Browser | From other containers | Config |
|---|---|---|---|
| SABnzbd | http://nas:8085 | sabnzbd:8080 | /opt/appdata/media/sabnzbd |
| Prowlarr | http://nas:9696 | prowlarr:9696 | /opt/appdata/media/prowlarr |

## SABnzbd settings that aren't in Git (sabnzbd.ini)
Edit only while the container is stopped (`docker compose stop sabnzbd`), or SABnzbd overwrites the file.

- `local_ranges = 192.168.0.0/24, 100.64.0.0/10, 172.16.0.0/12` — LAN, Tailscale, Docker.
  Without it: "External internet access denied" (browser over Tailscale) or 403 (other containers).
- `host_whitelist = sabnzbd, nas` — without it: 403 when apps call it by name.
- Folders: incomplete `/data/usenet/incomplete`, complete `/data/usenet/complete`.
- Categories: `tv` → `tv`, `movies` → `movies`.

## Secrets (in Vaultwarden, never in Git)
Usenet provider login, indexer API keys, each app's login and API key.
