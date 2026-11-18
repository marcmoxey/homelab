# Postmortem #4: MinecraftDown drill — alert worked, server left down ~9 hours

| | |
|---|---|
| **Date** | 2026-11-17 → 2026-11-18 |
| **Author** | Marc Moxey |
| **Status** | Resolved |
| **Severity** | Low (drill; only the owner was affected) |
| **Duration** | ~9 h (≈11:00 PM → 8:01 AM ET) |
| **Type** | Drill that turned into a real outage |
| **Host** | nas (`prominence2`, Prominence II v4.1.8) |

> Blameless format: this document is about how the process behaved and how to make it more reliable, not about who did what.

## Summary

The new `MinecraftDown` alert was tested by stopping the Minecraft server on purpose. The alert fired and reached the phone in about 3–4 minutes, which proves the full chain: mc-monitor → Prometheus → Alertmanager → ntfy → iPhone. But the drill was never finished: the server was not started again afterwards, and it stayed down for about 9 hours until it was noticed the next morning while setting up cAdvisor. An earlier attempt the same evening also failed to fire, because the way the server was being restarted kept resetting the alert's timer.

## Impact

- **Players:** Minecraft unavailable ~9 hours overnight. No friends were using it yet (LAN only, no port forward).
- **Data:** None lost. `Exited (0)` = clean shutdown.
- **Monitoring:** Worked as designed the whole time; the alert stayed firing.

## Timeline (ET)

| Time | Event |
|---|---|
| Nov 17, ~11:05 PM | Swapped the modpack and renamed the service `minecraft` → `prominence2`, using `docker compose down` / `up`. Server down for several minutes. **No alert.** |
| ~11:20 PM | Server back up; joined successfully. Noticed the phone got no alert. |
| ~11:22 PM | **Drill started:** `docker compose stop prominence2` (mc-monitor kept running). |
| ~11:24 PM | Prometheus: `MinecraftDown` **Pending** (yellow). |
| ~11:25 PM | Prometheus: **Firing** (red). |
| 11:26 PM | **Phone alert received** via ntfy. Detection ≈ 3–4 min, as expected. |
| — | Server **not restarted**. Drill considered done. |
| Nov 18, ~8:00 AM | Setting up cAdvisor: `prominence2` missing from its container list. `docker ps -a` → `Exited (0) 9 hours ago`. |
| 8:01 AM | `docker compose start prominence2` → `Up (healthy)`. **Service restored.** |

## Root cause and contributing factors

**1. The drill had no "finish" step (main cause).**
The goal was "does the alert reach my phone?". Once it did, the drill felt finished. Restarting the server and confirming the **Resolved** notification was not written down as part of it, so it didn't happen.

**2. `restart: unless-stopped` does what it says.**
A container stopped by hand stays stopped, even across Docker restarts. That's correct behavior, but it means a manual stop is never undone automatically.

**3. The alert kept firing, but one notification is easy to dismiss.**
The alert was firing all night, but it was expected — it was the drill. There was no separate signal that the drill had been *left* in a broken state.

**Why the earlier attempt (~11:05 PM) didn't alert — not a bug, but worth knowing:**
- `docker compose down` stopped **mc-monitor too**. No data is not the same as `0`, so the 2-minute timer reset.
- The rename changed the label `server_host="minecraft"` → `"prominence2"`. Prometheus treats that as a new series, so the timer reset again.
- The alert only fires after **2 unbroken minutes of the same series at 0**. Neither stretch qualified.

## What went well

- **The alert chain works end to end** — Prometheus → Alertmanager → ntfy → iPhone in ~3–4 min, matching the expected 15s + 2m + 30s.
- **Monitoring caught it, indirectly:** cAdvisor's container list made the missing server obvious.
- **Diagnosis was fast:** `docker ps -a` showed `Exited (0)` straight away, which pointed to a manual stop, not a crash.
- **No data loss** — clean shutdown.

## What went wrong

- The drill had no written steps, so the recovery half was skipped.
- The first test used `docker compose down`, which also removed the thing doing the checking.
- A firing alert that you *expect* gets ignored.
- The ntfy notification arrived, but the message didn't show up in the app's homelab-alerts list. (Still open.)

## Action items

| # | Action | Type | Status |
|---|---|---|---|
| 1 | Runbook `docs/runbooks/minecraft-down.md` with a **Verify** section that ends with "Resolved arrived on the phone" | Prevent | ✅ Done |
| 2 | Add `runbook_url` to the `MinecraftDown` alert | Mitigate | ✅ Done |
| 3 | Write drills as a checklist before starting: break → alert → **fix → Resolved** | Prevent | ⬜ TODO (add to future drill postmortems) |
| 4 | Runbook rule: restart with `stop`/`start`, never `down`, so mc-monitor keeps running | Prevent | ✅ In runbook |
| 5 | Find out why the ntfy message isn't in the iPhone app's list even though the notification arrives | Detect | ⬜ TODO |
| 6 | Turn on the whitelist before opening port 25565 to friends | Prevent | ⬜ TODO |

## Lessons learned

1. **A drill isn't over until you see Resolved.** Testing the alarm is only half of it; recovery is the other half.
2. **Don't remove the thing doing the checking.** `docker compose down` stops mc-monitor with the server. No data ≠ down.
3. **Alerts need the same series for the whole `for:` window.** Renames and gaps reset the timer.
4. **`unless-stopped` means a manual stop stays stopped** — on purpose.

## Related

- Runbook: `docs/runbooks/minecraft-down.md`
- Previous postmortems: `2026-11-08-node-exporter-drill.md`, `2026-11-08-alertmanager-deadmans-drill.md`, `2026-11-09-power-loss-monitoring-outage.md`
