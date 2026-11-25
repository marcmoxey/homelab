# Rebuild: NAS from scratch

> **Last tested:** never · **Measured RTO:** ___ (fill in after the DR drill)

Use this when the NAS's OS is gone (dead boot drive, bad upgrade, reinstall) or the whole machine is replaced.
Everything that *can* be code is in this repo; everything secret comes from the password manager.

## 0. Which scenario?

| Scenario | Pool `tank` | App data `/opt/appdata` | Path |
|---|---|---|---|
| A. OS disk died / reinstall | Intact | Intact (separate NVMe) | Steps 1–5, skip 6 |
| B. App-data NVMe died | Intact | Lost | Steps 1–6 (restore app data) |
| C. Whole machine lost | Lost | Lost | Steps 1–6, data from B2 only |

## Before you start: secrets you need

Vaultwarden runs **on the NAS**, so it's down too. Use the Bitwarden app's offline copy on the phone/laptop (log in there at least once a month so the cache is fresh).

| Secret | Goes to |
|---|---|
| Each stack's `.env` | `nas/<stack>/.env` (git-ignored) |
| restic repository password + B2 key | See [backups.md](backups.md), "Recovery needs three things" |
| NUT `upsd.users`, `upsmon.conf` | `/etc/nut/` (root:nut, 0640) |
| Samba user password | `smbpasswd` |
| Tailscale login | `tailscale up` |

## 1. Install the OS

- Ubuntu Server 26.04, user `mmoxey`, OpenSSH on.
- Static LAN IP **192.168.0.231** (router DHCP reservation).

## 2. Get the repo and Ansible

~~~bash
sudo apt update && sudo apt install -y git ansible
sudo mkdir -p /opt/stacks && sudo chown mmoxey: /opt/stacks
git clone https://github.com/marcmoxey/homelab.git /opt/stacks
~~~

## 3. Tailscale (before the playbook)

Services bind to the Tailscale IP **100.105.219.6**. A new install gets a new IP, so:

1. Tailscale admin console: remove the old `nas` machine.
2. `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up`
3. Admin console: rename the new machine to `nas`, **Edit IP → 100.105.219.6**.

## 4. Run the playbook

~~~bash
cd /opt/stacks/ansible
ansible-playbook -i inventory.yml site.yml --limit nas -e ansible_connection=local --check --diff -K   # dry run
ansible-playbook -i inventory.yml site.yml --limit nas -e ansible_connection=local -K
~~~

This installs/configures: base hardening + UFW, Docker, Tailscale, ZFS (imports `tank`, never creates it), the `/opt/appdata` mount, Samba, NUT, and all backup schedules.
Log out and back in afterwards (docker group).

> Scenario B/C: the mount task needs an ext4 partition labelled `appdata` first:
> `sudo mkfs.ext4 -L appdata /dev/nvmeXn1p1` (**check the device name twice**).
> Scenario C: create the pool by hand first (RAIDZ1, 4 disks); Ansible only imports.

## 5. Secrets, then services

~~~bash
# Secrets from the password manager
nano /opt/stacks/nas/<stack>/.env                # one per stack
sudo install -o root -g nut -m 0640 upsd.users upsmon.conf /etc/nut/
sudo systemctl restart nut-server nut-monitor
sudo smbpasswd -a mmoxey

# Start stacks, Vaultwarden first
cd /opt/stacks/nas/vaultwarden && docker compose up -d
find /opt/stacks/nas -name 'compose.y*ml' -printf '%h\n' | sort -u | while read -r d; do
  (cd "$d" && docker compose up -d)
done
~~~

## 6. Restore data (Scenario B/C only)

~~~bash
sudo -i
# load the restic env (see backups.md), then:
restic snapshots
restic restore latest --target / --include /opt/appdata/<app>     # one app at a time
~~~

Then load each app's database dump with its runbook (`vaultwarden-down.md`, `bookstack-down.md`, `minecraft-down.md`).
Local backups in `/tank/backups` are faster than B2 if the pool survived.

## 7. Verify

- [ ] `zpool status -x` → all pools are healthy
- [ ] `findmnt /opt/appdata`
- [ ] `upsc $(upsc -l | head -1) ups.status` → `OL`
- [ ] `crontab -l` (3 `#Ansible` jobs) and `sudo crontab -l` (2)
- [ ] Prometheus (Beelink) → Targets all **UP**, Alerts all **Inactive**
- [ ] Jellyfin plays from outside the house; friends can join Minecraft
- [ ] Second playbook run → `changed=0`
- [ ] Write down the RTO at the top of this file

## Lessons from drills

| Date | Scenario | RTO | What broke / what changed |
|---|---|---|---|
| | | | |
