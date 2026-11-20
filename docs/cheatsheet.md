# Homelab Command Cheat Sheet

Last updated: 2026-11-20

## Golden rules

Every one of these comes from a real mistake in this homelab.

1. **Check where you are before `up -d` or `rm`:** run `hostname` and `pwd`. `nas/` folders run on the NAS; `monitoring/` runs on the Beelink.
2. **Validate, then restart:** run `docker compose config -q` before `up -d`, and `promtool check config` before restarting Prometheus.
3. **Drills use `stop <service>`, never `down`.** `down` also removes the monitor, so the alert can't fire.
4. **A drill isn't done until RESOLVED arrives** on your phone.
5. **ZFS commands use by-id disk names**, never `/dev/sdX`.
6. **No secrets in Git:** `.env`, ping URLs and API keys stay out. Commit `.env.example` with placeholders instead.
7. **Bind container ports to specific IPs** (`192.168.0.231`, `100.105.219.6`, or `127.0.0.1`). Docker-published ports bypass UFW.
8. **Test a whitelist name with `rcon whitelist add` before putting it in `.env`.** A bad name in `.env` crash-loops the server.
9. **Edit `sabnzbd.ini` only while SABnzbd is stopped,** or it overwrites your change.
10. **`cat >` replaces a file; `cat >>` appends to it.**

## Where things live

Two machines, one repo cloned to `/opt/stacks` on both; each runs only its own folders.

| Machine | LAN IP | Tailscale IP | Runs |
| --- | --- | --- | --- |
| NAS (`nas`) | 192.168.0.231 | 100.105.219.6 | Everything in `nas/`: Minecraft, BookStack, Vaultwarden, Immich, media stack, exporters, Samba, NUT server |
| Beelink (`beelink`) | — | 100.66.160.124 | Everything in `monitoring/`: Prometheus, Grafana, Alertmanager, ntfy, blackbox exporter |

| Path (NAS) | What goes there | In Git? |
| --- | --- | --- |
| `/opt/stacks/` | Instructions: `compose.yml`, scripts, configs | Yes |
| `/opt/appdata/` | Live app data on the NVMe: databases, Minecraft world, app settings | No |
| `/tank/files` | Samba file share | No |
| `/tank/photos` | Immich photos | No |
| `/tank/backups` | Backups (Minecraft, BookStack, Vaultwarden) | No |
| `/data/media`, `/data/usenet` | Media library and downloads (TRaSH layout) | No |
| `.env` files | Secrets for each stack | Never |

## Shell basics

Paths starting with `/` work from anywhere; paths without it are relative to `pwd`.

| Command | What it does |
| --- | --- |
| `hostname` / `pwd` | Which machine / which folder you're in |
| `cd /opt/stacks/nas/media` | Go to a folder (`cd ..` = up one) |
| `ls -la` | List files, including hidden ones like `.env` |
| `cat file` | Print a file |
| `nano file` | Edit a file (Ctrl+O save, Ctrl+X exit, Ctrl+W search; a `>` at a line's end = it continues off-screen) |
| `cat > file <<'EOF' … EOF` | Write a whole file in one paste (replaces it) |
| `cat >> file <<'EOF' … EOF` | Append to the end of a file |
| `grep -n "text" file` | Find lines containing text, with line numbers |
| `sed -i 's\|old\|new\|' file` | Replace text in a file |
| `mkdir -p a/{b,c}` | Make folders (`{b,c}` makes both) |
| `sudo chown -R mmoxey:mmoxey path` | Make yourself the owner |
| `chmod 600 .env` | Only you can read/write (secrets) |
| `chmod +x script.sh` | Make a script runnable |
| `cp a b` / `mv a b` / `rm file` | Copy / move or rename / delete (no trash: gone for good) |
| `rm -rf dir` | Delete a folder and everything in it. Check `hostname` and the path first |
| `find /data -maxdepth 3 -type d \| sort` | List folders |
| `du -sh path` / `ls -lh path` | Folder size / file sizes (on ZFS, `du` right after a write can show 512) |
| `openssl rand -hex 24` | Generate a random password |
| `curl -I http://host:port` | Is a web service answering? (200/302 = yes) |

## Docker and Compose

Run `docker compose` from the stack's folder (where `compose.yml` is); add a service name to act on just that one.

| Command | What it does |
| --- | --- |
| `docker compose config -q` | Check the file. No output = valid |
| `docker compose up -d [svc]` | Create/update and start. Re-reads `compose.yml` and `.env` (recreates the container if they changed) |
| `docker compose stop svc` / `start svc` | Pause / resume with the same settings. Use for drills |
| `docker compose restart svc` | Stop + start. Does **not** re-read `.env` |
| `docker compose down` | Remove the stack's containers. Avoid for drills |
| `docker compose ps` | This stack's containers, status, ports |
| `docker compose logs -f --tail=50 svc` | Follow logs (Ctrl+C to stop watching) |
| `docker compose pull` | Download newer images for the pinned tags |
| `docker ps` / `docker ps -a` | All running / all including stopped containers |
| `docker exec -it name sh` | Shell inside a container |
| `docker inspect name --format '{{.RestartCount}} {{.State.OOMKilled}}'` | Crash-looping? Out of memory? |
| `docker inspect name --format '{{range .Config.Env}}{{println .}}{{end}}'` | Settings the container is actually running with |
| `docker inspect IMAGE --format '{{index .Config.Labels "build_version"}}'` | Exact version of a LinuxServer image, for pinning |
| `docker stats --no-stream` | CPU and RAM per container |
| `docker image prune -a` | Delete unused images (frees disk) |

**Reading `docker ps`:** `Restarting (2)` = crash loop; `Exited (0)` = stopped on purpose; `(healthy)` = healthcheck passing; CREATED older than "Up" = stopped/started, not recreated. In PORTS, `0.0.0.0:` = open to every network.

**Container to container** in the same stack: use the container name and its *inside* port, e.g. `sabnzbd:8080`, not the host port.

## Git workflow

The everyday loop, from `/opt/stacks` on either machine:

```bash
git pull                 # get the other machine's changes first
git status               # what changed? no .env, no .tfstate, no ping URLs
git add path/to/file     # add specific files, not everything
git commit -m "area: what changed"
git push
```

| Situation | Fix |
| --- | --- |
| `pull` says an **untracked** file would be overwritten | Delete or move that local file, then `git pull` |
| `status` shows a file **deleted** that you still want in the repo | `git restore path/to/file` |
| Undo uncommitted edits to a file | `git restore path/to/file` |
| Unstage something you `add`-ed by mistake | `git restore --staged path/to/file` |
| `push` rejected (remote has newer commits) | `git pull` (merge), then `git push`. Never `git push --force` |
| Check a secret isn't tracked | `git ls-files \| grep -i env` should list only `.env.example` files |
| See recent history | `git log --oneline -10` |

## Minecraft

Server container `prominence2`, stack in `nas/gameservers/minecraft`, world in `/opt/appdata/minecraft/prominence`. Prominence II v4.1.8, Fabric 1.20.1.

| Command | What it does |
| --- | --- |
| `docker exec prominence2 rcon-cli list` | Who's online |
| `docker exec prominence2 rcon-cli whitelist add NAME` | Add to whitelist instantly, no restart (spelling must be exact; case doesn't matter) |
| `docker exec prominence2 rcon-cli whitelist remove NAME` | Remove from whitelist |
| `docker exec prominence2 rcon-cli whitelist list` | Show the whitelist |
| `docker exec prominence2 rcon-cli op NAME` | Make someone an operator |
| `docker exec prominence2 rcon-cli say Restarting in 5 min` | Message everyone in game |
| `docker logs -f prominence2 \| grep -i done` | Wait for startup to finish (2–5 min) |
| `docker compose stop prominence2` | Drill: stop the server only (mc-monitor keeps running) |
| `./backup.sh hourly` / `./backup.sh daily` | Take a backup now (to `/tank/backups/minecraft/prominence2/`) |
| `tail -20 /home/mmoxey/mc-backup.log` | Recent backup results |

**Whitelist rule:** `rcon whitelist add` first; only once it works, add the name to `WHITELIST=` in `.env`. Don't recreate the container just for that; `.env` is picked up at the next recreate.

## Monitoring (Beelink)

All from `/opt/stacks/monitoring` on the Beelink. Alerts reach the phone via Alertmanager → ntfy, about 3 minutes after a failure; RESOLVED takes up to 5 more.

| Command | What it does |
| --- | --- |
| `docker exec prometheus promtool check config /etc/prometheus/prometheus.yml` | Validate config **and** rule files. Run before every restart |
| `docker compose restart prometheus` | Load new config/rules (only after SUCCESS) |
| `docker exec prometheus wget -qO- "http://blackbox:9115/probe?target=URL&module=http_2xx&debug=true"` | See exactly what a probe sees and why it fails |
| `curl -s http://100.105.219.6:2283/api/server/ping` | Immich health (`{"res":"pong"}`) |
| `curl -I https://nas.tailf2e508.ts.net/alive` | Vaultwarden health, through HTTPS |
| `curl -I http://100.105.219.6:6875/login` | BookStack health |
| `curl -s http://100.105.219.6:9150/metrics \| grep healthy` | Minecraft health (via mc-monitor) |

**Useful Prometheus queries:** `probe_success` (all probed apps, 1 = up), `up` (all scrape targets), `minecraft_status_healthy`, `node_zfs_zpool_state{state="online"}`.

**Planned maintenance:** add a silence in Alertmanager (matcher on `instance` or `service`) before you start, and expire it when you're done.

## ZFS, drives and system health (NAS)

Pool `tank`: RAIDZ1 on 4× 18 TB, about 47 TiB usable. Survives one drive failing.

| Command | What it does |
| --- | --- |
| `zpool status -x` | "all pools are healthy" = fine |
| `zpool status tank` | Each drive's state and READ/WRITE/CKSUM error counts |
| `zpool list` / `zfs list` | Pool size and free space / each dataset's usage |
| `sudo zpool scrub tank` | Check every block (also runs monthly from cron) |
| `ls -l /dev/disk/by-id/ \| grep ZVT \| grep -v part` | Drive by-id names (use these, never `/dev/sdX`) |
| `sudo smartctl -H /dev/sdX` | Drive's own health verdict: PASSED / FAILED |
| `sudo smartctl -A /dev/sdX` | Temperatures and warning counters (reallocated, pending sectors) |
| `df -h /data /tank/files /opt/appdata` | Free space where it matters |
| `free -h` | RAM (look at "available") |
| `awk '/^size/ {printf "%.1f GiB\n", $3/2^30}' /proc/spl/kstat/zfs/arcstats` | ZFS cache (ARC) size; capped at 16 GiB |
| `sudo dmesg -T \| tail -30` | Recent kernel messages (disk errors, OOM kills) |
| `timedatectl` | Time zone and clock |
| `systemctl status smbd` | Is a system service running? |

## Networking and access

Port-forwarded, and nothing else: **80/443 → Caddy** (`watch.` → Jellyfin, `request.` → Seerr) and **25565 → Minecraft** (whitelisted). Everything else is LAN + Tailscale only; never forward 445 (Samba) or any app port.

| Command | What it does |
| --- | --- |
| `sudo ufw status numbered` | Firewall rules (edit them in `ansible/group_vars/storage.yml`, then run the playbook) |
| `ansible-playbook site.yml --limit nas --check --diff` | Dry run: show what would change |
| `ansible-playbook site.yml --limit nas` | Apply |
| `tailscale status` | Your devices and how they're connected |
| `tailscale serve status` | The HTTPS proxy for Vaultwarden |
| `sudo ss -tlnp \| grep PORT` | What's listening on a port |
| `curl -4 -s ifconfig.me` | Your current public IP |
| `nslookup NAME 1.1.1.1` | What a DNS name points to (`NXDOMAIN` under an answer = no IPv6, ignore) |
| `cd /opt/stacks/nas/media && docker compose logs -f caddy` | Caddy log (certificates, errors); Ctrl+C to stop watching |
| `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile` | Check the Caddyfile before restarting Caddy |
| `curl -sI --resolve watch.marcshometheater.org:443:192.168.0.231 https://watch.marcshometheater.org/health` | Test Caddy + certificate + Jellyfin from inside, skipping DNS and the router |
| `docker compose -f /opt/stacks/nas/ddns/compose.yml logs --tail=20` | DDNS: did the A records update? |
| `ssh nas` / `ssh beelink` | Log in (SSH keys only) |
| `scp file nas:/path/` | Copy a file to the NAS (needs an SSH key on the sending machine) |
| `testparm -s` | Check the Samba config |
| `sudo systemctl restart smbd` | Apply Samba changes |

**File share:** Mac `smb://nas/nasfileshare`; Windows `\\192.168.0.231\nasfileshare` (or map it as a drive: `net use Z: \\192.168.0.231\nasfileshare /user:mmoxey /persistent:yes`). Lands in `/tank/files`.

**From Windows:** `Test-NetConnection 192.168.0.231 -Port 445` checks a port is reachable.

## Backups and cron

Every backup pings healthchecks.io on success, so a missed run alerts. All live on the pool; nothing is off-site until restic → B2.

| Backup | Run it now | Schedule | Goes to | Keeps |
| --- | --- | --- | --- | --- |
| Minecraft | `nas/gameservers/minecraft/backup.sh hourly` (or `daily`) | Hourly :00, daily 4:30 | `/tank/backups/minecraft/prominence2/` | 24 hourly, 7 daily |
| BookStack | `nas/bookstack/backup.sh` | Daily 3:15 | `/tank/backups/bookstack/` | 7 |
| Vaultwarden | `sudo nas/vaultwarden/backup.sh` (root cron) | Daily 3:45 | `/tank/backups/vaultwarden/` | 30 |
| Immich database | Built in (Administration → Settings → Backup) | Daily | `/tank/photos/backups/` | Set in Immich |

| Command | What it does |
| --- | --- |
| `crontab -l` / `crontab -e` | Your scheduled jobs: list / edit |
| `sudo crontab -l` | Root's scheduled jobs (Vaultwarden backup) |
| `ls -1t /tank/backups/bookstack/ \| head` | Newest backups first |
| `tail -20 /home/mmoxey/bookstack-backup.log` | Recent results (also `mc-backup.log`; root's in `/var/log/vaultwarden-backup.log`) |

**Cron format:** `minute hour day month weekday`. `0 * * * *` = every hour on the hour; `15 3 * * *` = 3:15 every day.

**Restore tests:** each runbook has the exact steps. The rule: restore into a throwaway container, check real content came back, then delete the throwaway.

## Service quick links

At home use `192.168.0.231` (NAS); away, turn on Tailscale and use `nas` or `100.105.219.6`. Logins are in Vaultwarden.

| Service | Browser | From other containers | Stack folder |
| --- | --- | --- | --- |
| Vaultwarden | https://nas.tailf2e508.ts.net | — | `nas/vaultwarden` |
| Immich | http://nas:2283 | — | `nas/immich` |
| BookStack | http://nas:6875 | — | `nas/bookstack` |
| SABnzbd | http://nas:8085 | `sabnzbd:8080` | `nas/media` |
| Prowlarr | http://nas:9696 | `prowlarr:9696` | `nas/media` |
| Sonarr | http://nas:8989 | `sonarr:8989` | `nas/media` |
| Radarr | http://nas:7878 | `radarr:7878` | `nas/media` |
| Jellyfin | https://watch.marcshometheater.org (anywhere) or http://nas:8096 | `jellyfin:8096` | `nas/media` |
| Seerr | https://request.marcshometheater.org (anywhere) or http://nas:5055 | `seerr:5055` | `nas/media` |
| Bazarr / Clonarr / Jellystat | http://nas:6767 / :6060 / :3001 | — | `nas/media` |
| Minecraft | Game address on port 25565 (public) | `prominence2:25565` | `nas/gameservers/minecraft` |
| File share | `smb://nas/nasfileshare` | — | `/etc/samba/smb.conf` (copy in `nas/samba`) |
| Prometheus | http://100.66.160.124:9090 | `prometheus:9090` | `monitoring` (Beelink) |
| Grafana | http://100.66.160.124:3000 | — | `monitoring` (Beelink) |
| Alertmanager | http://100.66.160.124:9093 | — | `monitoring` (Beelink) |

Sonarr, Radarr and Jellyfin are listed with their planned ports; they aren't running yet. Prometheus, Grafana and Alertmanager ports are their defaults; change them here if yours differ.
