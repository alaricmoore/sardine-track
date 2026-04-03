# Flare Prediction Model

A transparent, statistical model for predicting lupus flare risk from daily observations. No black box -- you can see exactly how every prediction is made, and tune it yourself.

---

## How It Works

Each day, the model computes a **flare risk score** (0-25) by summing weighted contributions from multiple input categories. A score at or above the **threshold** (default 8.0) is a predicted flare.

Before scoring, each observation is enriched with multi-day context via `_inject_scoring_context()`, which pre-computes rolling metrics that span multiple days. This means the model isn't just looking at today -- it's looking at patterns building over the past 1-3 weeks.

---

## Scoring Categories

### 1. UV Dose

UV exposure is the strongest environmental predictor (Cohen's d = +1.29, p < 0.0001 for 3-day cumulative sun exposure).

The dose is computed as an interaction: `(weighted_UV_index ^ 1.5) x sun_exposure_minutes x protection_factor`. This captures that 30 minutes at UV index 10 is much worse than 30 minutes at UV index 3.

| Condition | Points |
|-----------|--------|
| UV dose >= 800 | +3.0 x uv_weight |
| UV dose >= 400 | +1.25 x uv_weight |
| 3-day cumulative UV >= 1500 | +1.5 x uv_weight |
| 3-day cumulative UV >= 1000 | +0.75 x uv_weight |

The cumulative UV load uses a decay-weighted sum of the prior 3 days (yesterday 0.7x, 2 days ago 0.4x, 3 days ago 0.2x). UV lag analysis shows 24-hour lag has the strongest flare correlation in this dataset.

Protection factors: none (1.0), SPF + hat (0.3), full cover (0.1), indoors only (0.0).

### 2. Physical Overexertion

Steps relative to personal baseline, adjusted for sleep.

| Condition | Points |
|-----------|--------|
| Overexertion ratio >= 1.8 | +2.0 x exertion_weight |
| Overexertion ratio >= 1.4 | +1.5 x exertion_weight |

Overexertion = `(steps / personal_step_baseline) x (8 / hours_slept)`. Falls back to raw steps/hours ratio if no baseline is set.

### 3. Basal Temperature Delta

Deviation from personal temperature baseline in Fahrenheit.

| Condition | Points |
|-----------|--------|
| Delta >= 0.8 F | +3.0 x temperature_weight |
| Delta >= 0.5 F | +2.0 x temperature_weight |
| Delta >= 0.3 F | +1.0 x temperature_weight |

### 4. Individual Symptoms

Each symptom category is a binary flag (present/absent) with its own weight:

| Symptom | Weight | Notes |
|---------|--------|-------|
| Neurological | 1.5 | Numbness, tingling, vision changes |
| Cognitive | 1.0 | Brain fog, memory, word recall |
| Musculature | 1.5 | Muscle pain, cramping, weakness |
| Migraine | 1.0 | Headaches, light sensitivity |
| Pulmonary | 1.0 | Air hunger, chest discomfort |
| Dermatological | 0.75 | Rash, photosensitivity |
| Mucosal | 0.25 | Dry mouth, dry eyes |
| Rheumatic | 0.5 base | Joint pain without specificity |
| -- major joints | 2.0 | Hip, knee, shoulder, elbow, ankle, wrist, jaw |
| -- minor joints | 1.0 | Finger, toe, hand |

Rheumatic scoring parses the notes field for joint names to differentiate severity.

### 5. Pain & Fatigue

| Condition | Points |
|-----------|--------|
| Pain scale >= 7 | +1.0 x pain_fatigue_weight |
| Fatigue >= 7 | +3.0 x pain_fatigue_weight |
| Fatigue > 5 | +1.0 x pain_fatigue_weight |
| Fatigue > 3 | +0.5 x pain_fatigue_weight |
| Emotional state <= 4 | +2.0 x pain_fatigue_weight |

### 6. Symptom Burden Delta

**The strongest predictor in the model.** Raw symptom count saturates when you have chronic daily symptoms (e.g., neurological 76% of days, rheumatic 82%, dermatological 62%). What predicts a flare isn't *having* symptoms -- it's having *more than your usual number* of them.

**Computation:**
- **Recent**: Mean daily symptom count over days -1, -2, -3
- **Baseline**: Mean daily symptom count over days -17 through -3 (14-day window)
- **Delta** = recent - baseline

The gap between the acute window (days -1 to -3) and the baseline window (days -3 to -17) is critical. Without it, the 3-day pre-flare symptom ramp bleeds into the baseline and dulls the signal.

| Condition | Points |
|-----------|--------|
| Delta >= 3.0 | +3.0 x symptom_burden_weight |
| Delta >= 2.0 | +2.0 x symptom_burden_weight |
| Delta >= 1.0 | +1.0 x symptom_burden_weight |

Falls back to 0 contribution with fewer than 7 days of baseline history.

### 7. RMSSD Baseline Deviation

Based on the cholinergic anti-inflammatory pathway: the vagus nerve tonically suppresses systemic inflammation. RMSSD (root mean square of successive differences in heartbeat intervals) is the best time-domain proxy for vagal tone. If vagal tone drops, the cholinergic brake weakens, and inflammation runs hotter.

**Computation:**
- **Recent**: 7-day rolling average of nightly RMSSD (days -1 through -7)
- **Baseline**: 30-day rolling average (days -8 through -37, avoids overlap)
- **Deviation** = `(recent - baseline) / baseline x 100`

| Condition | Points |
|-----------|--------|
| Deviation <= -25% | +1.5 x rmssd_deviation_weight |
| Deviation <= -15% | +0.75 x rmssd_deviation_weight |

Conservative default weight (0.5) because the signal is mechanistically grounded but not yet statistically significant at current sample size (Cohen's d = -0.35, p = 0.11, n = 25 major/ER events). Apple Watch RMSSD has ~29% measurement error vs chest strap, but tracks relative within-person changes adequately for this purpose.

Returns no contribution with fewer than 4 values in either window.

### 8. Cycle Phase (Disabled)

Weight set to 0.0. Fisher exact tests showed no predictive signal in this patient's data:
- Bleeding days: lower flare rate than non-bleeding (15.6% vs 20.9%, OR = 0.70, p = 0.24)
- PMS window: no signal (OR = 1.12, p = 0.70)

With post-steroid cycles averaging 15.7 days (range 12-29) versus the model's 28-day assumption, ~90% of days were flagged as high-risk, making the signal a constant bias offset. May be revisited as an interaction variable (UV x cycle phase) if cycles stabilize.

---

## Multi-Day Context Injection

The model doesn't just score today's snapshot. Before `calculate_flare_prime_score()` runs, `_inject_scoring_context()` enriches each observation with:

| Field | What It Is |
|-------|-----------|
| `_uv_row` | UV index data for the date (from weather API) |
| `_cumulative_uv_dose` | Decay-weighted UV dose from prior 3 days |
| `_symptom_burden_delta` | Symptom acceleration above personal baseline |
| `_rmssd_deviation` | HRV deviation from 30-day personal baseline |

This runs at every call site: the forecast page, history view, accuracy analysis, forecast lab simulations, and the daily alert check. All paths get the same context.

---

## Tuning

All weights are adjustable through the **Forecast Lab** (`/forecast/lab`):

- **Symptom weights**: 0-3 range per symptom
- **Category multipliers**: UV, exertion, temperature, pain/fatigue (0-2 range)
- **Multi-day predictor weights**: symptom_burden_weight, rmssd_deviation_weight
- **Flare threshold**: 4-20 range

The lab lets you adjust weights, run simulations to see accuracy/recall/precision impact, preview which predictions would flip, and apply or revert changes. Custom weights are stored per-user in the database (or in `config/custom_weights.json` as fallback).

---

## Model Dashboard

The **model dashboard** (`/timeline`, nav label "model") provides score transparency over time:

- **Score attribution chart**: Stacked bars showing daily score broken down by component, with flare event markers and threshold line
- **Symptom burden delta**: Line chart of the baseline-relative delta, showing symptom acceleration
- **RMSSD deviation**: Line chart showing vagal tone deviation from personal baseline
- **Score distribution**: Summary statistics comparing flare days vs non-flare days
- **Prediction accuracy strip**: Per-day colored dots (green = correct, red = missed, orange = false alarm)

---

## RMSSD Trajectory Analysis

The **pre-flare pattern analysis** page (`/forecast/patterns`) includes an RMSSD trajectory chart showing the 7 days before each ER visit and major flare:

- Individual event lines (color-coded by severity)
- Aggregate mean line with +/- 1 SD confidence band
- Baseline reference line (non-flare day average)
- Trend direction indicator (rising/falling/flat with magnitude)

This was built to test the hypothesis that RMSSD may behave differently before flares than the simple "vagal withdrawal = drop" model predicts.

---

## Data Sources

| Metric | Source |
|--------|--------|
| Symptoms, pain, fatigue, emotional state | Manual daily entry |
| Steps, HRV (SDNN), resting HR, SpO2, respiratory rate | Apple Watch via iOS health sync app |
| RMSSD | Computed from RR interval heartbeat series (overnight window, 10pm-8am) |
| Basal body temperature | Apple Watch wrist temperature |
| UV index | Open-Meteo and Visual Crossing weather APIs |
| Sun exposure minutes | Manual daily entry |
| Flare events and severity | Manual daily entry |

---

## Relevant Literature

- Huston & Tracey (2011): Cholinergic anti-inflammatory pathway -- vagal tone suppresses systemic inflammation via acetylcholine on macrophage nicotinic receptors. Proposed HRV as a predictor of impending relapse.
- Bhatt/Engel group (ACR abstracts): 58 SLE patients, 505 visit pairs. RMSSD and HF-HRV increased during clinical improvement, decreased during flares, inverse correlation to SLEDAI.
- Apple Watch HRV validation (2024): Underestimates HRV by ~8.3ms vs Polar H10 (MAPE ~29%), but tracks relative within-person changes adequately for longitudinal monitoring.
