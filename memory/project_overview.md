---
name: Biotracker project overview
description: Flask health tracking app for lupus/SARD patients - tracks UV, symptoms, cycle, flare risk scoring. Runs on Raspberry Pi, accessed via <YOUR_SERVER>.
type: project
---

Flask-based health tracking app (app.py is the monolith) with SQLite backend (db.py).

**Why:** Built because the user needed to prove sun exposure correlation with lupus flares.

**Infrastructure:** Raspberry Pi 4 at home (Starlink) → Tailscale tunnel → Oracle Cloud VM → <YOUR_SERVER>

**Key features as of 2026-03-23:**
- Daily symptom/flare tracking with multi-category symptoms
- UV dose calculation with 3-day rolling cumulative sum
- Menstrual cycle tracking with BBT-based ovulation detection
- Flare risk forecasting model with customizable weights
- HRV trending with intervention before/after analysis
- Health-sync API endpoint (POST /api/health-sync) for iOS Shortcut auto-ingest
- Intervention color coding: teal (primary Rx), purple (secondary), orange (supplements)

**How to apply:** Changes should be careful and incremental. The user is both developer and primary patient-user. Cycle tracking, flare risk scoring, and UV dose calculations are interconnected — changes to one can affect the others. The app has a `before_request` login redirect — new API endpoints need to be added to the allowlist.
