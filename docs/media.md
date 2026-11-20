# Media stack (nas/media)

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
