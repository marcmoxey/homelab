# Ansible

Host configuration as code. Docker Compose (in `nas/` and `monitoring/`) runs the apps; Ansible sets up the machines they run on.
A second run should always report **`changed=0`**: that proves the code matches the servers.

## Layout

~~~
ansible/
├── ansible.cfg
├── inventory.yml        # hosts: nas, beelink
├── group_vars/          # UFW rules and per-group settings
├── site.yml             # which roles run on which hosts
└── roles/
    ├── base/            # all hosts
    ├── docker/          # all hosts
    ├── tailscale/       # all hosts
    └── nas/             # NAS only
~~~

## Roles

| Role | Hosts | Manages |
|---|---|---|
| `base` | all | Base packages, SSH hardening, UFW (default deny + allow list), unattended-upgrades, timezone, binding to the Tailscale IP before it's up |
| `docker` | all | Docker Engine + Compose plugin, `mmoxey` in the docker group, starts on boot |
| `tailscale` | all | Tailscale package, starts on boot (login is manual: `sudo tailscale up`) |
| `nas` | nas | ZFS tools + 16 GiB ARC cap, imports `tank` (never creates), `/opt/appdata` mount, Samba (`smb.conf` from `nas/samba/`, checked by `testparm`), NUT config (non-secret files from `nas/nut/`), the 5 backup cron jobs |

## Not managed (secrets, from the password manager)

`.env` files, restic password/keys, NUT `upsd.users` + `upsmon.conf`, Samba user passwords, Tailscale login. See [`docs/rebuild.md`](../docs/rebuild.md).

## Running it

On the NAS itself (no SSH to itself needed):

~~~bash
cd /opt/stacks/ansible
ansible-playbook -i inventory.yml site.yml --limit nas -e ansible_connection=local --check --diff -K   # 1. dry run: read the diff
ansible-playbook -i inventory.yml site.yml --limit nas -e ansible_connection=local --diff -K           # 2. apply
ansible-playbook -i inventory.yml site.yml --limit nas -e ansible_connection=local -K | tail -3         # 3. expect changed=0
~~~

Beelink (over SSH from a machine with a key for it): same commands with `--limit beelink` and without `-e ansible_connection=local`.

| Flag | Meaning |
|---|---|
| `--check` | Dry run: report what *would* change |
| `--diff` | Show the before/after of each change |
| `--limit nas` | Only this host |
| `-K` | Ask for the sudo password |

## Backup schedules

Cron jobs live in `roles/nas/tasks/main.yml`, **not** in `crontab -e`. Each has a `#Ansible: <name>` marker so reruns update instead of duplicating.

| Job | User | When |
|---|---|---|
| bookstack-backup | mmoxey | 03:15 daily |
| vaultwarden-backup | root | 03:45 daily |
| minecraft-backup-daily | mmoxey | 04:00 daily |
| restic-b2 | root | 05:00 daily |
| minecraft-backup-hourly | mmoxey | every hour, :00 |

To change one: edit the task, dry run, apply. To remove one: set `state: absent` on the task, run once, then delete the task.

## Gotchas learned the hard way

- **Check mode skips `command` tasks.** Read-only checks (like `zpool list`) need `check_mode: false`, or later tasks see no result.
- **Module defaults can silently change things.** `ansible.posix.mount` defaults to `passno: 0`, which would have turned off fsck for `/opt/appdata`. Set every field to match what's live.
- **GPG-key tasks show `changed` in check mode** (the download can't be compared). Harmless.
- **Read the `--diff` before applying.** A "changed" with no visible diff usually means owner/mode or comments only; confirm with `diff` on the real files.
