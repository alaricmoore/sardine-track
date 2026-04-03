---
name: Cycle phase not predictive of flares
description: Fisher exact tests show menstrual cycle phase has no predictive signal for lupus flares in Alaric's data - weight zeroed out 2026-04-03
type: project
---

Wolf Claude ran Fisher exact tests on Alaric's data (as of 2026-04-03):
- Bleeding days have *lower* flare rate than non-bleeding: 15.6% vs 20.9%, OR=0.70, p=0.24
- Major flares also less frequent on bleeding days: OR=0.51, p=0.27
- 3-day PMS window: no signal at all, OR=1.12, p=0.70

Three compounding problems:
1. Post-steroid cycles averaging 15.7 days (range 12-29) vs model assuming 28 days → 90% of days flagged
2. Follicular transition bug — phase doesn't reset properly with irregular bleeding patterns
3. The signal simply isn't there in the data

**Why:** cycle_phase weight was adding constant bias (+1.0 to ~90% of days), muddying the UV dose signal (Cohen's d=1.4) which is doing real work. Produced a false positive on 2026-04-02.

**How to apply:** Weight set to 0.0 in DEFAULT_WEIGHTS. May revisit as an interaction variable (UV × cycle phase) if cycles stabilize on HCQ. Don't re-enable without fresh statistical evidence.
