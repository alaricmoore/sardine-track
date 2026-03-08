# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

[1.0.0] — 2026-03-06
Added

Initial public release
Daily symptom and biometric tracking
UV lag correlation analysis
Flare forecasting with model accuracy assessment
HRV and autonomic tracking with medication comparison
Clinical record: labs, ANA, medications, events, clinicians
The Forecast Lab
Clinical report generation with PDF export
Full data export and deletion
Apple Health import
Raspberry Pi remote access support via Tailscale

[2.1.0] - 2026-03-07
Added

Cycle Phase Flare Weighting
Added _inject_cycle_phase() and_compute_phase_by_date_from_obs() helpers — annotates observation dicts with cycle_in_high_risk_phase (bool) and cycle_phase_name using BBT-anchored ovulation detection
Added cycle_phase: 1.0 to DEFAULT_WEIGHTS — PMS/luteal phase contributes +1.0 to flare score (adjustable in Forecast Lab, no-op when track_cycle: false)
Updated calculate_flare_prime_score(), get_contributing_factors(), get_score_breakdown() to include cycle phase
Added cycle phase slider to Forecast Lab (/forecast/lab) — only visible when track_cycle: true
Called _inject_cycle_phase() in 6 forecast routes so phase is always annotated before scoring
Performance: recall improved 36.7% → 45.5%, false positives reduced 20% → 16.7%
Proactive Flare Risk Alerts (ntfy)
Added_send_ntfy_alert() — separate from medication reminder sender, supports priority and tags
Added _check_flare_risk_alert() — daily cron at configurable hour (default 8am), sends alert when weighted 3-day score ≥ 5.0 or when entering PMS/luteal phase tomorrow
High-risk alerts (≥ 8.0) use high priority and rotating_light tag
Rate-limited to once per calendar day via config/flare_alert_state.json
Config options: flare_alert_hour (default 8), disable by clearing ntfy_topic
Added to .gitignore: config/flare_alert_state.json
Quick Entry Mode
Added ?mode=quick URL param to /daily — shows only fields that feed the prediction model (pain, fatigue, emotional state, symptom checkboxes, flare flags, period flow)
All hidden fields carry existing values as hidden inputs so data isn't wiped on save
Symptom notes stripped in quick mode (checkboxes only, no expandable text areas)
Mode toggle link shown near page subtitle
Clinical Report Improvements
Clinical Summary: Added flare count for the period and date of most recent flare
Symptom Frequency table: New section, days each category flagged out of total tracked days, sorted by frequency, ≥30% highlighted
ANA — Positive Results (All Time): New section showing only non-negative ANA results with titer, pattern(s), and provider; includes clinical note explaining why negatives are excluded (ANA fluctuates in early disease)
Print header: Print-only div with patient name, period, generated date, primary intervention — hidden on screen, visible in PDF
Richer auto-findings: generate_findings() now produces flare frequency finding, highest-burden symptom category, neurological involvement flag (≥10% of days), medication-started-during-period findings
Typo fix: "Encounter's & Events" → "Encounters & Events"
Security Hardening
Debug off by default: debug=True replaced with debug=CONFIG.get('debug', False) — enable with "debug": true in config.json
SECRET_KEY: Auto-generated 32-byte hex key written by setup.py to config.json; fallback warning printed if missing from an existing install
Optional passcode lock: Add "passcode": "yourpin" to config.json to require login — session-based, before_request guard on all routes, login/logout routes, lock button in nav. No effect when key is absent.
CSRF protection: flask-wtf>=1.2.0 added; CSRFProtect(app) initialized; CSRF meta tag in base.html; JS auto-injector adds token to all POST forms at DOM load; window.csrfFetch() helper for fetch-based POST calls; all three template fetch calls updated to csrfFetch()
New template: templates/login.html — passcode form using existing design system
requirements.txt: Added flask-wtf>=1.2.0
Documentation
README: Cycle tracker section, luteal phase weighting rationale with real data
README: Push notifications section expanded (flare alerts, timing config, rate limiting)
README: Performance numbers updated (recall 36.7% → 45.5%, false positives 20% → 16.7%)
README: "From Apple Health — Menstrual Cycle Data" import section added
README: Optional Passcode section with step-by-step setup instructions
README: login.html added to project structure
README: Data Privacy & Security bullet added for passcode feature
