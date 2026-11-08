# Postmortem: node_exporter outage (planned drill)

**Date:** 2026-11-08
**Author:** Marc Moxey
**Status:** Complete
**Severity:** Low (planned drill, no user impact)

## Summary
As a planned drill, I stopped the node_exporter container on the Beelink to test the
alerting pipeline end to end. The TargetDown alert reached my phone ~3 minutes after
the outage began, and the resolved notification arrived ~2 minutes after recovery.

## Impact
- Beelink host metrics (CPU, memory, disk, network) were not collected for ~3 minutes.
- No user-facing services were affected.

## Timeline (EST)
| Time    | Event |
|---------|-------|
| 3:04 PM | node_exporter stopped (`docker compose stop node-exporter`) |
| ~3:05 PM | Prometheus scrape of `node` fails; `up{job="node"} = 0` |
| ~3:06 PM | TargetDown alert enters Pending (`for: 2m`) |
| 3:07 PM | Alert fires → Alertmanager → ntfy bridge → phone notification |
| 3:07 PM | node_exporter restarted (`docker compose start node-exporter`) |
| 3:09 PM | Resolved notification received on phone |

## Detection
- Detected by the TargetDown rule (`up == 0 for 2m`).
- Time to detect: ~3 minutes.

## Root cause
Planned: the container was stopped on purpose to test alerting.

## Resolution
Restarted the container. Time to resolve after the alert: <1 minute.

## What went well
- The full alert pipeline (Prometheus → Alertmanager → ntfy bridge → ntfy → phone) worked.
- Resolved notifications work, so I know when an issue is over.
- The `for: 2m` delay would prevent alerts for brief blips.

## What could be improved
- Rule evaluation runs at the 1-minute default, which adds up to 1 minute of delay.
- If the Beelink, Tailscale, or ntfy itself goes down, no alert would reach me
  (no dead man's switch).
- There's no runbook for TargetDown yet.

## Action items
- [ x ] Set `evaluation_interval: 15s` in prometheus.yml
- [ x ] Add a dead man's switch (always-firing Watchdog alert → healthchecks.io)
- [ ] Write `docs/runbooks/target-down.md`
- [ x ] Run the same drill again after these changes and compare detection time

## Lessons learned
Alert latency is the sum of scrape interval + rule evaluation + `for` duration +
Alertmanager grouping. Tuning detection speed means trading it against alert noise.
