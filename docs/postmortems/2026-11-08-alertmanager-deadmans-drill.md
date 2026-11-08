# Postmortem: Alertmanager outage / dead man's switch drill

**Date:** 2026-11-08
**Author:** Marc Moxey
**Status:** Complete
**Severity:** Low (planned drill, no user impact)

## Summary
As a planned drill, I stopped the Alertmanager container on the Beelink to test
whether a failure of the alerting stack itself would be detected. Because
Alertmanager was down, no alerts could reach my phone through ntfy. The dead man's
switch (Watchdog alert → healthchecks.io) caught this: healthchecks.io stopped
receiving pings and emailed me that the check was DOWN ~10 minutes after the
outage began.

## Impact
- Alertmanager was down for ~[X] minutes.
- During that window, no alerts (e.g. TargetDown) could have reached my phone.
- No user-facing services were affected.

## Timeline (EST)
| Time      | Event |
|-----------|-------|
| 3:52 PM   | Watchdog alert starts firing; pings begin reaching healthchecks.io |
| ~3:54 PM  | Alertmanager stopped (`docker compose stop alertmanager`); pings stop |
| 4:04 PM   | healthchecks.io emails "beelink-watchdog is DOWN" (5 min period + 5 min grace) |
| [ ] PM    | Alertmanager restarted (`docker compose start alertmanager`) |
| [ ] PM    | healthchecks.io emails "beelink-watchdog is UP" |

## Detection
- Detected by healthchecks.io, which runs outside my homelab, when expected pings stopped.
- Time to detect: ~10 minutes.
- Notification channel: email, independent of the Beelink, Tailscale, and ntfy.

## Root cause
Planned: the Alertmanager container was stopped on purpose.

## How the dead man's switch works
1. Prometheus evaluates an always-firing `Watchdog` rule (`expr: vector(1)`).
2. Alertmanager routes Watchdog to a webhook that pings healthchecks.io every ~1 minute.
3. healthchecks.io expects a ping every 5 minutes (+5 minute grace).
4. If Prometheus, Alertmanager, Docker, the Beelink, or its internet connection
   fails, pings stop and healthchecks.io alerts me by email.

## What went well
- The outage of the alerting system was detected through a fully independent path.
- The ping payload confirmed the whole chain (Prometheus rule → Alertmanager → outbound HTTP).
- Secrets (ping URL) are kept out of Git with `url_file` and a git-ignored folder.

## What could be improved
- Detection takes ~10 minutes; the period and grace could be lowered to ~2 + 3 minutes.
- Email is the only independent channel; a second one (e.g. Telegram or Pushover)
  would add redundancy.
- During setup, a typo in `prometheus.yml` (`evalutation_interval`) caused a crash loop
  that went unnoticed until checked manually. Running `promtool check config` before
  every restart would have caught it.

## Action items
- [ ] Lower the healthchecks.io period/grace to 2 min / 3 min
- [ x ] Add a second independent notification channel to healthchecks.io
- [ x ] Always run `promtool check config` (not just `check rules`) before restarting Prometheus
- [ ] Pin the Alertmanager image to an exact version (currently `latest`)
- [ ] Write runbook: `docs/runbooks/watchdog-down.md`

## Lessons learned
Monitoring can fail silently, and silence looks the same as "all good." A dead man's
switch turns the absence of a signal into an alert, and it has to run outside the
system it watches.
