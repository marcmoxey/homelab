# Postmortem #3: Monitoring stack down ~10 hours after unclean power loss

| | |
|---|---|
| **Date** | 2026-11-08 → 2026-11-09 |
| **Author** | Marc Moxey |
| **Status** | Resolved |
| **Severity** | High: all monitoring and alerting down |
| **Duration** | ~10h 20m (≈11:29 PM → 9:50 AM ET) |
| **Type** | Real incident (not a drill) |
| **Host** | beelink (monitoring host) |

> Blameless format: this document is about how the system behaved and how to make it more resilient, not about who did what.

## Summary

The Beelink lost power or crashed hard around 11:29 PM ET. When it booted again, only 2 of 6 monitoring containers came back. Prometheus, Grafana, ntfy and Alertmanager stayed down overnight, so there were no metrics and no alerts for about 10 hours. Recovery the next morning exposed two more problems: containers that were restarted rather than recreated came back without working networking, and Alertmanager crash-looped on a clustering feature that wasn't needed. All three are fixed, and a deliberate reboot test confirmed the stack now recovers on its own.

## Impact

- **Monitoring:** No metrics collected for ~10 hours. There's a permanent gap in Grafana for that window.
- **Alerting:** Prometheus and Alertmanager were both down, so **no alert of any kind could fire**. TargetDown could not fire because Prometheus itself was down.
- **Users:** None. The Beelink only runs monitoring; no friend-facing services are hosted on it yet.
- **Data loss:** Only the metrics gap. Configs, Grafana dashboards and ntfy users were unaffected, since they're stored in Git and Docker volumes.

## Timeline (ET; server logs are in UTC, so ET = UTC − 5)

| Time (ET) | Event |
|---|---|
| Nov 8, ~11:29 PM | Last journal entry from the previous boot (04:29 UTC). Routine log lines, then nothing. **No shutdown messages**, so this was an unclean power loss or hard crash, not a reboot. |
| ~11:35 PM | Beelink boots again (worked out from `uptime`: up 10:07 at 14:42 UTC). |
| ~11:35 PM | `node-exporter` and `ntfy-alertmanager` start. `prometheus`, `grafana`, `ntfy` and `alertmanager` stay in **Exited (255)**. |
| ~11:45 PM | healthchecks.io stops receiving Watchdog pings; DOWN email expected. *(TODO: confirm when the DOWN email arrived.)* |
| Nov 9, 9:41 AM | **Detected** manually: `docker ps` shows 4 containers Exited 10 hours ago. |
| 9:42 AM | Ran `docker compose up -d`. Prometheus, Grafana and ntfy show "Up", but with **no published ports**. Alertmanager enters a crash loop: `Restarting (1)`. |
| 9:43 AM | Alertmanager logs: `unable to initialize gossip mesh ... no private IP address found`. (My first guess, corrupted data from the power cut, was wrong. The logs disproved it.) |
| 9:48 AM | Added `--cluster.listen-address=` to turn off clustering; recreated Alertmanager. It stays Up and has `172.18.0.3` on the Docker network. |
| 9:49 AM | Noticed the PORTS column was empty for grafana, ntfy and prometheus. Only the recreated container had working networking. |
| 9:50 AM | `docker compose up -d --force-recreate` → all 6 Up with their Tailscale ports. **Service restored.** |
| 9:51 AM | Applied `net.ipv4.ip_nonlocal_bind = 1` in `/etc/sysctl.d/99-tailscale-bind.conf`, then ran `sudo reboot` as a test. |
| 9:53 AM | **Reboot test passed:** all 6 containers came back on their own with their ports, with nothing done by hand. |

## Root cause and contributing factors

**Trigger:** unclean power loss or hard crash at about 11:29 PM. The exact cause is unknown. The Beelink is not on a UPS.

**1. Containers bound to the Tailscale IP couldn't start at boot (main cause).**
Prometheus, Grafana, ntfy and Alertmanager publish their ports on `100.66.160.124`, the Tailscale IP, so they're only reachable over Tailscale. At boot, Docker started before Tailscale had assigned that IP, so Docker couldn't open those ports and gave up on those containers. Docker's `restart: unless-stopped` does not retry this kind of startup failure.
- *Evidence:* Exactly the containers with published Tailscale ports failed. node-exporter (host networking, which retries on its own) and ntfy-alertmanager (no published ports) survived. After applying `ip_nonlocal_bind`, a reboot brought everything back.
- *Gap:* The original Docker error message (`State.Error`) was cleared by the restart before I captured it, so the exact error text is inferred, not seen.

**2. Restarting old containers didn't restore their networking.**
`docker compose up -d` restarted the existing stopped containers instead of recreating them. They reported "Up" but had **no published ports**, and Alertmanager had no IP on the Docker network. Recreating them (`--force-recreate`) fixed it immediately. The exact Docker mechanism isn't known, but the pattern was clear: recreated containers worked and restarted ones didn't.

**3. Alertmanager clustering was on by default.**
Clustering lets several Alertmanagers coordinate with each other. With only one instance, it does nothing useful, but on startup it still requires a private IP, and **exits with an error if it can't find one**. Combined with factor 2, this turned "missing network" into a crash loop.

**4. Detection depended on someone reading email.**
The dead man's switch worked as designed: it covers exactly this case, where Prometheus itself is down. But it notifies by email, and nobody saw an email overnight. The outage was actually found by a person running `docker ps`.

## What went well
- **The dead man's switch design was right.** When Prometheus is down, nothing inside the homelab can alert, and healthchecks.io sits outside it for exactly this reason.
- **Diagnosis followed the evidence.** The wrong first guess (corrupted data) was disproved by the logs within minutes. Comparing working and broken containers found the real pattern.
- **SSH over the LAN worked as a fallback** while Tailscale-only services were down.
- **The fix was verified, not assumed.** A deliberate reboot test proved the stack recovers without manual steps.
- **Everything was in Git,** so recovery required no rebuilding from memory.

## What went wrong
- No UPS, so a short power blip took down the whole host.
- The boot order between Docker and Tailscale was never tested, because the stack had never been rebooted since it was built.
- `docker compose up -d` was assumed to fully restore a stack. After a crash it didn't.
- A default feature (clustering) was running without being needed.
- The only overnight alert path was email.

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Set `net.ipv4.ip_nonlocal_bind = 1` so Docker can bind to the Tailscale IP before Tailscale is up | Prevent | ✅ Done, reboot-tested |
| 2 | Disable Alertmanager clustering (`--cluster.listen-address=`) | Prevent | ✅ Done |
| 3 | Add "after power loss or crash: `docker compose up -d --force-recreate`" to `target-down.md` and `watchdog-down.md` | Mitigate | ⬜ TODO |
| 4 | Put the Beelink on the CyberPower UPS with the NAS | Prevent | ⬜ TODO |
| 5 | Set up NUT (Network UPS Tools) for clean shutdown on long outages, with a power-loss alert to ntfy | Prevent / Detect | ⬜ Later |
| 6 | Add a healthchecks.io notification that reaches the phone (push/SMS or a public ntfy.sh topic), not only email | Detect | ⬜ TODO |
| 7 | Add reboot testing to the change process: after host-level changes, `sudo reboot` and check `docker compose ps` | Prevent | ⬜ TODO (add to `monitoring-changes.md`) |
| 8 | Confirm when the healthchecks.io DOWN email arrived and fill in the timeline | Follow-up | ⬜ TODO |

## Lessons learned
1. **A system that has never been rebooted hasn't been tested.** Boot-order bugs only show up on restart.
2. **"Up" isn't the same as "working."** Check the published ports and a real request, not just the status column.
3. **After a crash, recreate, don't just restart.** `docker compose up -d --force-recreate`.
4. **Turn off defaults you don't use.** Clustering did nothing for a single instance, and it took down alerting.
5. **The dead man's switch is only as good as its notification channel.** If it only reaches you by email, an overnight outage goes unnoticed until morning.

## Related
- Runbooks: `docs/runbooks/target-down.md`, `docs/runbooks/watchdog-down.md`, `docs/runbooks/monitoring-changes.md`
- Previous postmortems: `2026-11-08-node-exporter-drill.md`, `2026-11-08-alertmanager-deadmans-drill.md`
