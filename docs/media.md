# Media stack (nas/media)

Request → download → organize → watch, all on the NAS, reachable only from the home LAN and Tailscale.

```
Seerr (request) → Radarr / Sonarr → Prowlarr (indexers) → SABnzbd (Usenet, preferred)
                                                         → qBittorrent via gluetun VPN (torrents, fallback)
   → /data/usenet/complete/{movies,tv} or /data/torrents/{movies,tv}
   → hardlinked into /data/media/{movies,tv,anime}
   → Jellyfin (watch)   + Bazarr (subtitles)   + Clonarr (TRaSH profiles)   + Jellystat (stats)
```

TRaSH Guides layout: every app that moves files mounts the whole `/data`, so imports are
**hardlinks** (instant, no extra space) and every app sees identical paths, so **no path
mappings are needed anywhere**.

## Services

| App | Browser | From other containers | Config (NVMe) | Data mount |
|---|---|---|---|---|
| SABnzbd | http://nas:8085 | `sabnzbd:8080` | `/opt/appdata/media/sabnzbd` | `/data/usenet` |
| gluetun (VPN) | — (publishes qBittorrent's 8090) | `gluetun` | `/opt/appdata/media/gluetun` | none |
| qBittorrent | http://nas:8090 | **`gluetun:8090`** (shares gluetun's network) | `/opt/appdata/media/qbittorrent` | `/data` |
| Prowlarr | http://nas:9696 | `prowlarr:9696` | `/opt/appdata/media/prowlarr` | none |
| Radarr | http://nas:7878 | `radarr:7878` | `/opt/appdata/media/radarr` | `/data` |
| Sonarr | http://nas:8989 | `sonarr:8989` | `/opt/appdata/media/sonarr` | `/data` |
| Jellyfin | http://nas:8096 | `jellyfin:8096` | `/opt/appdata/media/jellyfin` | `/data/media` (read-only) + `/dev/dri` |
| Seerr | http://nas:5055 | `seerr:5055` | `/opt/appdata/media/seerr` | none |
| Navidrome (music) | http://nas:4533 | `navidrome:4533` | `/opt/appdata/media/navidrome` | `/data/media/music` (read-only) |
| Bazarr | http://nas:6767 | `bazarr:6767` | `/opt/appdata/media/bazarr` | `/data` |
| Clonarr | http://nas:6060 | `clonarr:6060` | `/opt/appdata/media/clonarr` | none |
| Jellystat | http://nas:3001 | `jellystat:3000` | `/opt/appdata/media/jellystat` | none |
| Jellystat DB | — | `jellystat-db:5432` | `/opt/appdata/media/jellystat/db` | none |
| Caddy (custom build + CrowdSec bouncer) | — (public: 80/443) | `caddy` | `/opt/appdata/media/caddy/{data,config,logs}` + `nas/media/caddy/{Caddyfile,Dockerfile}` | none |
| CrowdSec | — (no ports) | `crowdsec:8080` (bouncer API) | `/opt/appdata/media/crowdsec/{config,data}` + `nas/media/crowdsec/{acquis,whitelist}.yaml` | reads Caddy + Jellyfin logs (read-only) |
| cloudflare-ddns | — (no ports) | — | none (`nas/ddns/.env` holds the token) | separate stack: `nas/ddns` |

All browser ports are bound to `192.168.0.231` and `100.105.219.6` only (Docker bypasses UFW).
Caddy binds 80/443 on `192.168.0.231` only (the router forwards there).
The apps run as UID/GID 1000 (mmoxey); Seerr does so by default, the others via PUID/PGID.

## Public access (friends and family outside the house)

**Live since 2026-11-20.** Verified from cellular: padlock on both sites, admin login refused,
viewing account streams, real client IP in Jellyfin's Activity log; Apple TV (Swiftfin) works with
Quick Connect. Caddy drill: FIRING 5:38 PM → RESOLVED 5:43 PM.

Exactly three services are reachable from the internet, all through Caddy (+ CrowdSec) over HTTPS:

| URL | Goes to | Used for |
|---|---|---|
| https://watch.marcshometheater.org | `jellyfin:8096` | Jellyfin apps and browser (same address at home and away) |
| https://request.marcshometheater.org | `seerr:5055` | Requesting movies and shows |
| https://music.marcshometheater.org | `navidrome:4533` | Music (web player + Subsonic apps), added 2026-11-21 |

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
- Jellyfin → Networking: Known proxies `caddy`; Published Server URI `https://watch.marcshometheater.org`
  (with "use same URI for internal and external" on); LAN networks `192.168.0.0/24, 100.64.0.0/10`;
  internet streaming bitrate limit ~20 Mbps; auto discovery off; Jellyfin's own HTTPS off (Caddy does TLS).
- Seerr → General: Application URL `https://request.marcshometheater.org`; Enable Proxy Support on;
  Enable CSRF Protection on.

## Hardening (internet-facing: Jellyfin + Seerr)

| Control | Setting |
|---|---|
| Exposure | Only Caddy (80/443) is forwarded; only `watch.` and `request.` route anywhere |
| Admin account (`mmoxey`) | **Remote connections disabled** — admin works only from the home LAN or Tailscale (both listed in LAN networks) |
| Viewing account (`marc`) | Separate non-admin account for TVs/phones away from home |
| Every user | Strong unique password (Vaultwarden), lockout after 5 failed attempts, hidden from login screens, no "manage server", library access limited, Live TV off |
| TV logins | **Quick Connect** on — TVs sign in with a 6-digit code approved from a phone; passwords never typed on a TV |
| Seerr logins | Jellyfin sign-in only (**local sign-in off**), so Jellyfin's lockout protects Seerr too; new Jellyfin users can sign in without import |
| Seerr permissions | Default: Request + View Recently Added + Report Issues; auto-approve per family member; limits 10 movies / 5 series per 7 days |
| Patching | Jellyfin, Seerr and Caddy updated within ~a week of releases (pinned tags, changed deliberately) |
| Intrusion prevention | **CrowdSec** (below): bans scanners and brute-force IPs at Caddy, before they reach Jellyfin or Seerr |

## CrowdSec (intrusion prevention)

```
visitor → Caddy ── bouncer asks CrowdSec "is this IP banned?" (refreshed every 15 s) → 403 if yes
                └→ jellyfin / seerr
CrowdSec engine ← reads Caddy JSON access logs + Jellyfin log_*.log ← + community blocklist
```

| Piece | Where |
|---|---|
| Engine | `crowdsec` container (`crowdsecurity/crowdsec:v1.8.2`), no published ports |
| Detection packs | `crowdsecurity/caddy` (+ base HTTP scenarios), `crowdsecurity/http-cve`, `LePresidente/jellyfin` (failed logins) |
| What it reads | `nas/media/crowdsec/acquis.yaml`: `/var/log/caddy/*.log` (type caddy), `/var/log/jellyfin/log_*.log` (type jellyfin) |
| Never banned | `nas/media/crowdsec/whitelist.yaml`: `192.168.0.0/24` (home) and `100.64.0.0/10` (Tailscale) |
| Bouncer | Caddy built with `github.com/hslatman/caddy-crowdsec-bouncer/http` (`nas/media/caddy/Dockerfile`), `route { crowdsec … }` in each site |
| Key | `CROWDSEC_CADDY_KEY` in `nas/media/.env` + Vaultwarden (`cscli bouncers add caddy-bouncer` shows it once) |
| Caddy logs | JSON, `/opt/appdata/media/caddy/logs/access.log`, rotated at 50 MiB × 5 |

Caddy **refuses to start** if `CROWDSEC_CADDY_KEY` is empty ("crowdsec API key must not be empty"). A
"variable is not set" warning from `docker compose` is an error here; fix `.env` before `up -d`.

Devices at home must use Pi-hole, so they reach Caddy from `192.168.0.x` (whitelisted). A device that
resolves the public IP shows up as the **home public IP**, which is *not* whitelisted.

```bash
docker exec crowdsec cscli decisions list                    # who is banned right now
docker exec crowdsec cscli alerts list                       # what was detected
docker exec crowdsec cscli decisions delete --ip 1.2.3.4     # unban
docker exec crowdsec cscli bouncers list                     # caddy-bouncer must show a recent pull
docker exec crowdsec cscli metrics show acquisition          # are both logs being read?
```

Verified 2026-11-21: a test ban on a phone's cellular IP returned 403 at Caddy; unban restored access.

## Monitoring

| What | How | Severity |
|---|---|---|
| Jellyfin | Blackbox `http://100.105.219.6:8096/health` → `ServiceDown` | critical |
| Seerr, Sonarr, Radarr, Prowlarr, SABnzbd | Blackbox probes (`/api/v1/status`, `/ping`, `/`) → `ServiceDown` | warning |
| Public path (DNS, router, Caddy, certs) | Blackbox `https://watch…/health` (`jellyfin-public`, critical), `https://request…/api/v1/status` (`seerr-public`, warning) | critical / warning |
| Certificates | `CertExpiringSoon` (< 14 days) from the public probes | warning |
| Public path from outside | **UptimeRobot** (free): `jellyfin-public` (`/health`), `seerr-public` (keyword `version` must exist), every 5 min, email + app push | — |
| DDNS container | healthchecks.io ping (`HEALTHCHECKS` in `nas/ddns/.env`) | — |
| Disk space | `DiskSpaceLow` (ext4 < 15%), `PoolSpaceLow` (tank < 7 TiB), `DiskWillFillIn24h` | warning / critical |

Runbooks: [media-down.md](runbooks/media-down.md), [caddy-down.md](runbooks/caddy-down.md),
[disk-space-low.md](runbooks/disk-space-low.md). Per-service link files (`jellyfin-down.md`, …) point to these.

The Beelink resolves the public names through Pi-hole, so the public probes test Caddy +
certificates + apps but not the router forward or public DNS. **To check from outside:** phone on
cellular (Wi-Fi off) → open both URLs; expect the login page and a padlock.

## Adding a friend or family member

Nobody can sign up; every account is created by hand. One Jellyfin account covers both sites.

1. **Password:** Vaultwarden → Generator → Passphrase (4 words, `-`, capitalize, number). Save as a
   login item `Jellyfin – <name>` in the **Jellyfin users** folder.
2. **Jellyfin → Dashboard → Users → +**, then on the user:

   | Setting | Value |
   |---|---|
   | Administrator | off |
   | Allow remote connections | on |
   | Allow media deletion / remote control of others | off |
   | Library access | all, or only what they should see |
   | Max parental rating | set for kids |
   | Max active sessions | 2–3 (stops a login being passed around) |

3. **Send the invite** by direct text (not a group chat): the two URLs, their username and password,
   "install Jellyfin on the TV (Apple TV: **Swiftfin** or **Infuse**), server
   `https://watch.marcshometheater.org`, sign in with **Quick Connect**". Quick Connect is approved
   from a device that's already signed in, so they log in on their phone first.
4. **Seerr:** their first sign-in at `request.` creates their Seerr account (or Users → Import
   Jellyfin Users first). Family: Users → them → Permissions → **Auto-Approve**. Everyone else:
   requests wait for approval, within the limits.

**Removing someone:** Jellyfin → Users → them → disable (keeps watch history) or delete; their
Seerr sign-in stops working at the same time. Delete their Vaultwarden item.

**Forgotten password:** Jellyfin → Users → them → Password → set a new one; lockouts clear the same way.

## Music (Navidrome)

Music I own (CD rips, purchases, collections) lives in `/data/media/music`, one folder per artist.
Navidrome plays it; there is no downloader for music (Lidarr was tried and removed).

| Piece | Setting |
|---|---|
| Container | `deluan/navidrome:0.64.2`, runs as UID 1000, `/music` mounted **read-only** |
| Public URL | `https://music.marcshometheater.org` (Caddy + CrowdSec, same DDNS + Pi-hole setup as watch/request) |
| Adding music | Samba share **`\\192.168.0.231\music`** (= `/data/media/music`). Drop `Artist/Album/` folders at the top level |
| Library | Watcher picks up new files within seconds; full scan every hour (`ND_SCANSCHEDULE=1h`) |
| Tags | Navidrome builds artists/albums from **tags**, not folders. Official albums: MusicBrainz Picard. Unreleased/sessions: Mp3tag, Artist + Album Artist set, `ALBUM = %_directory%` |
| Accounts | Admin (strong password, Vaultwarden) + one **non-admin** user per person. No "admin only at home" option exists, so admin is protected by password + Navidrome's login rate limit (5 / 20 s) + CrowdSec |
| Apps | iPhone: Amperfy (Subsonic), Android: Symfonium, or the web player. Offline downloads supported |
| Privacy | `ND_ENABLEINSIGHTSCOLLECTOR=false` |
| Backup | `/data/media/music` is in the restic paths (it's not re-downloadable) |

## Adding anime (avoiding wrong-season imports)

Release groups and TheTVDB often number long anime differently (e.g. a group's "S02E08" is an old
episode, while TheTVDB's Season 2 is a newer series). Checklist for every new anime:

1. Add with **Series Type: Anime / Absolute**, root `/data/media/anime`, [Anime] profile, **Season Folder on**,
   **no automatic search**. Requested via Seerr? TMDB often shows one long season, so open the show in
   Sonarr afterwards and **monitor the other seasons**.
2. Note Sonarr's seasons and the absolute number in brackets, e.g. `1 (171)`.
3. Search **Prowlarr** (English + Japanese title) and compare names: absolute numbers (`- 171`) or
   clear season names (`2nd Season S2E01`) are safe; plain `S02E01` that means a different season is not.
4. If there's a mismatch: tag the series and add a **Release Profile → Must Not Contain** for that tag.
   Current guards: `apothecary` → `/Kusuriya[ ._]no[ ._]Hitorigoto[ ._]S01[ ._]\(25-48\)/i`;
   `blackclover` → `/Black[ ._]Clover[ ._](2017[ ._])?S0[2-4](E\d+)?\b/i`.
5. Download **one season at a time** with Interactive Search (prefer full batches). Never "Search All
   Missing" on long anime: dozens of queries per episode trip indexer rate limits (HTTP 429).
6. Check episode 1's file name matches Sonarr's title before letting the rest run.

Grabbed outside Sonarr (from Prowlarr)? **Wanted → Manual Import** → the download folder → set series,
season, episodes → Move (Usenet) or Hardlink/Copy (torrents, so they keep seeding).

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

## Torrents (qBittorrent behind a VPN)

Usenet is preferred; torrents (Nyaa.si for anime) are the fallback. qBittorrent has **no route to
the internet except the VPN**: it runs with `network_mode: service:gluetun`, so if ProtonVPN drops,
it has no network at all (kill switch). Public trackers see Proton's IP, never the home IP.

| Piece | Setting |
|---|---|
| VPN | ProtonVPN Plus, WireGuard, P2P servers only (`PORT_FORWARD_ONLY=on`), US. Key: `PROTON_WG_PRIVATE_KEY` in `nas/media/.env` (made at account.protonvpn.com → Downloads → WireGuard, **NAT-PMP on**) |
| Port forwarding | Proton assigns a port on each connect; gluetun's `VPN_PORT_FORWARDING_UP_COMMAND` pushes it into qBittorrent (needs qBittorrent "Bypass authentication for clients on localhost") |
| Second kill switch | qBittorrent → Advanced → Network interface `tun0` |
| Folders | Default save path `/data/torrents`; categories `movies` → `/data/torrents/movies`, `tv` → `/data/torrents/tv` (anime uses `tv`; Sonarr's root folder puts it in `/data/media/anime`) |
| Seeding | Ratio 1.0 → pause; Sonarr/Radarr "Remove Completed" cleans up |
| Sonarr / Radarr | Download client qBittorrent: host **`gluetun`**, port `8090`, category `tv` / `movies`. Delay profile: Preferred Protocol **Usenet** |

**Restart rule:** if gluetun restarts, qBittorrent loses its network. Restart them together:
`docker compose restart gluetun qbittorrent` (gluetun retries the port push until qBittorrent is up).

**Leak test (after any VPN change)**
```bash
curl -4 -s ifconfig.me; echo                          # home IP
docker exec qbittorrent curl -s ifconfig.me; echo     # must be different (Proton)
docker compose stop gluetun
docker exec qbittorrent curl -m 5 -s ifconfig.me || echo "BLOCKED - kill switch works"
docker compose restart gluetun qbittorrent
docker compose logs --since 2m gluetun | grep -E "port forwarded|awaiting response"   # port + 200
```
Verified 2026-11-21: Proton IP shown, kill switch blocked, port pushed (200).

## Settings that live outside Git (set in each app's UI)

**SABnzbd** (`sabnzbd.ini`, edit only while the container is stopped):
- `local_ranges = 192.168.0.0/24, 100.64.0.0/10, 172.16.0.0/12` — LAN, Tailscale, Docker.
  Without it: "External internet access denied" in the browser, 403 from other apps.
- `host_whitelist = sabnzbd, nas` — without it: 403 when apps call it by name.
- Folders: temporary `/data/usenet/incomplete`, completed `/data/usenet/complete`.
- Categories: `tv` → folder `tv`, `movies` → folder `movies`. **The folder column must be filled in**;
  if it's empty, downloads land loose in `/data/usenet/complete/` and Sonarr asks for a manual import.

**Radarr / Sonarr:** root folders above; Use Hardlinks instead of Copy = on; download client
SABnzbd (`sabnzbd`, `8080`, API key, category, no username/password); Connect → Jellyfin
(`jellyfin`, `8096`, Update Library on, Send Notifications off).

**Prowlarr:** Apps → Radarr (`http://radarr:7878`) and Sonarr (`http://sonarr:8989`),
Prowlarr server `http://prowlarr:9696`. Download clients (for grabbing from Prowlarr's own search):
`SABnzbd` (category `movies`), `SABnzbd TV` (category `tv`), `qBittorrent` (host `gluetun`, port `8090`,
category `tv`). Use **Grab with override** to pick the client and category.

**Indexers:** NZB-Geek, altHUB (Usenet, priority 25); AnimeTosho (Usenet, `https://feed.animetosho.net`,
API key `0`, priority 25, limits 60 queries / 20 grabs per hour, "Anime Standard Format Search" off in
Sonarr); Nyaa.si (torrent, priority 50, Sonarr/Radarr compatibility options on). Delay profiles:
default **Prefer Usenet**; tag `anime` → **Prefer Torrent** (anime groups often release on Nyaa first).

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

**qBittorrent:** Web UI login (Vaultwarden), localhost bypass on, ban after 5 failures, UPnP off,
Automatic torrent management, save path and categories above, network interface `tun0`, ratio 1.0.

**Clonarr:** Radarr and Sonarr instances by container name + API keys.

**Jellystat:** connected to `http://jellyfin:8096` with its own API key.

## Secrets (Vaultwarden + `nas/media/.env`, never in Git)

Usenet provider login, indexer API keys, every app's login and API key,
`JELLYSTAT_DB_PASSWORD`, `JELLYSTAT_JWT_SECRET`, `PROTON_WG_PRIVATE_KEY` (anyone with it can use
the VPN account: if leaked, delete it in Proton and make a new one). `.env.example` shows the format.

## Common fixes

| Symptom | Fix |
|---|---|
| SABnzbd 403 / "API key incorrect" from an app | Check `local_ranges`, `host_whitelist`, and that the app has the current API key (the log shows the caller's IP and user agent) |
| qBittorrent "not reachable" / no peers | Port not pushed: `docker compose logs gluetun \| grep -E "port forwarded\|awaiting"` should end in `200`; 403 = localhost bypass off; then `docker compose restart gluetun qbittorrent` |
| Sonarr/Radarr can't reach qBittorrent | Host must be `gluetun`, not `qbittorrent`; check the login |
| gluetun unhealthy / restarting | `docker compose logs --tail=40 gluetun`; key missing from `.env` ("variable is not set") or Proton outage |
| Download never imports | Radarr/Sonarr → Activity → Queue shows the reason (usually paths or permissions) |
| Hardlink check | `ls -li` on the download and the library file: same inode number = hardlink |
| New subtitle not in player | Bazarr → Jellyfin integration on; or refresh the item in Jellyfin |
| Wrong poster/match | Jellyfin → item → Identify |
| "Unable to parse" / "manual import required" | Sonarr → Activity → Queue → 👤 → set series/season/episode → Import. If it's every download: SABnzbd category has no folder (see SABnzbd settings) |
| Anime episodes in the wrong season | See "Adding anime" above: Manual Import with the right season, then add a release-profile guard |
| Sonarr says "Indexers unavailable due to failures" | Usually 429 rate limiting after big searches; wait 1 h, then Test the indexer in Sonarr to clear it |
| Search spins for minutes | Backlog of searches: System → Tasks → Queue. `docker compose restart sonarr` clears it |
| Music not showing in Navidrome | Files outside `/data/media/music`, or missing tags (`[Unknown Album]`); fix in Mp3tag, then Settings → Scan Library |

## Friend sign-ups (Wizarr)

Friends get a one-time invite link (`https://invite.<your-domain>`) instead of me creating accounts by hand.

| | |
|---|---|
| Container | `wizarr` in `nas/media/compose.yml`, data in `/opt/appdata/wizarr` |
| Public route | Caddy `invite.<your-domain>` → CrowdSec → `wizarr:5690` |
| Jellyfin link | Internal `http://jellyfin:8096`, API key named "Wizarr"; external URL `https://watch.<your-domain>` |
| New users | Hidden from Jellyfin login screens; only the libraries chosen per invite |
| Seerr | Informational connection only. Friends sign into Seerr with their Jellyfin login; Seerr creates the account on first sign-in ("Enable Jellyfin Sign-In" for new users is on) |
| Runbook | [wizarr-public-down.md](runbooks/wizarr-public-down.md) |

## Jellyfin plugins

Plugins live in `/opt/appdata/jellyfin` (backed up by restic). After a rebuild, re-add the repositories and reinstall these.
Most UI plugins only change the **web interface** (browser, desktop, phone apps); native TV apps (Android TV, Roku, Swiftfin) don't show them.

| Plugin | Repository | What it does |
|---|---|---|
| TheTVDB | Jellyfin Stable | Season numbering matches Sonarr (fixes anime seasons) |
| Intro Skipper | `https://intro-skipper.org/manifest.json` | Skip intro/credits (works on most apps via media segments) |
| File Transformation | (dependency) | Lets the web plugins below load safely |
| Playback Reporting | Jellyfin Stable | Watch history (overlaps with Jellystat) |
| Jellyfin Enhanced | `https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/manifest.json` | Seerr requests inside Jellyfin, shortcuts, subtitle styling. Seerr URL: `http://seerr:5055` |
| InPlayerEpisodePreview | `https://raw.githubusercontent.com/Namo2/InPlayerEpisodePreview/master/manifest.json` | Episode list inside the player |
| Jellyfin Featured | `https://raw.githubusercontent.com/spkesDE/jellyfin-featured-plugin/main/manifest.json` | Home-page featured carousel |

Rules: only plugins with builds for the running Jellyfin version (12.x); back up the database first; one at a time, restart, check **Active**; uninstall anything that shows **NotSupported**.
