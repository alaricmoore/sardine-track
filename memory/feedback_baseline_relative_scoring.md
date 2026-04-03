---
name: Baseline-relative scoring pattern
description: When scoring chronic metrics, always use deviation from personal rolling baseline, not raw values — raw counts saturate for chronic conditions
type: feedback
---

When a metric is chronically elevated (symptoms present 60-80% of days), raw counts become constant offsets that don't distinguish flare from non-flare days. Always use baseline-relative deltas instead.

**Why:** Raw 3-day symptom count showed 15.1 on flare days vs 15.6 on non-flare days (p=0.51) — same structural problem as cycle_phase. Alaric has neuro 76%, rheumatic 82%, derm 62% of days. Presence doesn't predict; *acceleration* does.

**How to apply:**
- When adding any new scoring input derived from chronic metrics, compute a rolling baseline and score the delta
- Critical: gap the baseline window away from the acute window (e.g., days -17 through -3, NOT -14 through -1) so the pre-flare ramp doesn't contaminate the baseline
- Start with threshold tiers as estimates, then check actual delta distributions on flare vs non-flare days to calibrate
- Follow existing patterns: RMSSD deviation (7-day vs 30-day), symptom burden delta (3-day vs 14-day with gap), BBT delta (deviation from personal baseline)
