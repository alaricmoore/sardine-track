---
name: Next session priorities
description: Queued work and things to watch as of 2026-04-03 — threshold tuning, delta validation, timeline/cycle still pending
type: project
---

Completed 2026-04-03:
- Cycle phase weight zeroed (no predictive signal)
- Symptom burden refactored to baseline-relative delta
- RMSSD baseline deviation added to scoring
- Centralized multi-day context injection
- Data export fixed (28 missing columns)
- Timeline replaced with model dashboard
- MODEL.md created, README and help page updated
- Forecast lab manual rewritten

Watch list (need live data before acting):
1. **Threshold may need re-tuning** — new components add up to ~3.75 points, old threshold 8.0 was calibrated without them. Check false alarm rate after 1-2 weeks.
2. **Run burden delta distribution check** — have Wolf compare delta on flare vs non-flare days to validate the refactor improved separation.
3. **BBT dip signal** (d=-0.45, p=0.051) — lower BBT before flares, just missed significance. Watch as n grows.
4. **Fatigue rate-of-change** (d=+0.43, p=0.076) — acceleration, not absolute level. Same baseline-relative philosophy. Candidate for future scoring input.

Still queued:
- Cycle calendar redesign (waiting for cycle biology to stabilize on HCQ)
- Possible "days like today" lookup feature
- Score component export for clinical use
- Sparkline trends per component on forecast page

**Why:** Building clinical evidence for next rheumatologist. Every model improvement strengthens the case.
