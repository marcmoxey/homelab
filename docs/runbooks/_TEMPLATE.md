# Runbook: <AlertName>

| | |
|---|---|
| **Alert** | `<AlertName>` (severity: <critical/warning>) |
| **Rule** | `<PromQL expr>` for <Xm> — `monitoring/prometheus/rules/alerts.yml` |
| **Fires when** | <plain English: what is true when this fires> |
| **Impact** | <who/what is affected: friends can't join, no metrics, data at risk…> |
| **Notified via** | Alertmanager → ntfy-alertmanager → ntfy `homelab-alerts` → phone |
| **Expected detection time** | ~<N> min (15s scrape + <for> + 30s group_wait) |
| **Does NOT cover** | <what this alert can't see, and which alert/check does> |

## How the check works
<1–3 sentences or a small diagram: what is measured, where, by what.>

| Piece | Where | Details |
|---|---|---|
| <service> | <host, file path> | <image/version, port> |
| <exporter> | <host, file path> | <port, bound to Tailscale IP> |
| Scrape job | Beelink, `prometheus.yml` | `job_name: <job>` |

---

## 1. Confirm (1 min)
1. Prometheus → Alerts: `http://100.66.160.124:9090/alerts`. Which label is firing?
2. <one command that shows the raw problem>
   ```bash
   <command>
   ```
   <what "bad" looks like vs "good">

## 2. Diagnose
```bash
ssh <host>
cd <folder>          # ALWAYS run docker compose from here
<command 1>
<command 2>
```

| What you see | Usually means |
|---|---|
| <symptom> | <cause> |
| <symptom> | <cause> |

## 3. Fix
| Cause | Fix |
|---|---|
| <cause> | `<command>` |
| <cause> | `<command>` |

**Don't:** <the dangerous shortcut, and why>

## 4. Verify (the incident isn't over until all are true)
- [ ] <the thing is healthy: command + expected output>
- [ ] Prometheus → Alerts → `<AlertName>` **Inactive**
- [ ] **`[RESOLVED] <AlertName>` arrived on the phone**
- [ ] <user-facing check: can join / can load / file opens>

## 5. Follow up
- [ ] Real outage or drill? Postmortem in `docs/postmortems/YYYY-MM-DD-<name>.md`
- [ ] Row in the History table below + the brag doc's Incidents table
- [ ] Step missing or wrong? Fix this runbook and commit

## History
| Date | What happened | Detect | Down for | Postmortem |
|---|---|---|---|---|
| YYYY-MM-DD | Drill: <what you broke> | ~N min | ~N min | <link or "none"> |
