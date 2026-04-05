# Biotracker iOS Companion App — Architecture Overview

**Version:** 1.0  
**Date:** 2026-04-05  
**Platform:** iOS 17+, Swift 5  
**Author:** Alaric + Aplaude (Claude Opus)

---

## Executive Summary

The Biotracker iOS companion app extends the Flask-based biotracker web app with:
- **Automatic daily sync** of HealthKit data (steps, HRV, heart rate, sleep temp, UV exposure, etc.)
- **Embedded web views** for accessing biotracker mobile pages (log, forecast) without switching apps
- **Local push notifications** for medication reminders, bedtime logging, and flare risk alerts
- **iOS Shortcuts integration** for automation and Siri support

The app follows Apple's best practices for health apps: background delivery, privacy-first design, and seamless HealthKit integration.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     iOS healthsync App                      │
│                                                             │
│  ┌───────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Sync Tab     │  │   Log Tab    │  │   Risk Tab      │  │
│  │               │  │              │  │                 │  │
│  │ Settings      │  │  WKWebView   │  │   WKWebView     │  │
│  │ Manual Sync   │  │  /mobile/log │  │  /mobile/status │  │
│  │ Backfill      │  │              │  │                 │  │
│  └───────┬───────┘  └──────┬───────┘  └────────┬────────┘  │
│          │                 │                   │           │
│          └─────────────────┴───────────────────┘           │
│                            │                               │
│         ┌──────────────────┴──────────────────┐            │
│         │       HealthSyncer (Core Logic)     │            │
│         │  - Query HealthKit data             │            │
│         │  - Compute RMSSD from RR intervals  │            │
│         │  - POST to /api/health-sync         │            │
│         │  - Backfill historical data         │            │
│         └──────────────────┬──────────────────┘            │
│                            │                               │
│    ┌───────────────────────┴────────────────────────────┐  │
│    │        BackgroundSyncTask (Automation)             │  │
│    │  - Triggered daily via BGTaskScheduler            │  │
│    │  - Calls HealthSyncer.syncNowSilent()             │  │
│    │  - Fetches FlareChecker.fetchStatus()             │  │
│    │  - Schedules notifications via NotificationMgr    │  │
│    └───────────────────────┬────────────────────────────┘  │
│                            │                               │
│    ┌───────────────────────┼────────────────────────────┐  │
│    │         FlareChecker  │  NotificationManager        │  │
│    │  - GET /api/flare-   │  - Bedtime log reminder     │  │
│    │    status             │  - Med dose reminders       │  │
│    │  - Evaluate alerts    │  - Flare threshold alert    │  │
│    │  - Return structured  │  - Flare trend alert        │  │
│    │    data               │  - Deep linking to tabs     │  │
│    └───────────────────────┴────────────────────────────┘  │
│                                                             │
│    ┌─────────────────────────────────────────────────────┐ │
│    │           iOS Shortcuts (AppIntents)                 │ │
│    │  - "Open Biotracker Log" → deep link to Log tab     │ │
│    │  - "Sync Biotracker" → trigger manual sync          │ │
│    └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTPS (Bearer token auth)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Flask Biotracker Server                        │
│              (https://<YOUR_SERVER>)                │
│                                                             │
│  ┌──────────────────┐   ┌────────────────────────────────┐ │
│  │ /api/health-sync │   │  /api/flare-status             │ │
│  │ (existing)       │   │  (NEW — returns JSON for iOS)  │ │
│  │ - Receives       │   │  - Current flare score         │ │
│  │   HealthKit data │   │  - Predicted flare bool        │ │
│  │ - Stores in DB   │   │  - Score delta (trend)         │ │
│  │                  │   │  - Doses due today             │ │
│  └──────────────────┘   └────────────────────────────────┘ │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │            Mobile Web Pages (existing)                │  │
│  │  - /mobile/log   → Embedded in iOS Log tab WKWebView │  │
│  │  - /mobile/status → Embedded in iOS Risk tab         │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### 1. Manual Sync (User-Initiated)

```
User taps "Sync Health Data" button
  ↓
ContentView → HealthSyncer.syncNow()
  ↓
HealthSyncer queries HealthKit for today:
  - Steps (sum)
  - HRV SDNN (average)
  - Resting heart rate (average)
  - SpO2 (most recent)
  - Respiratory rate (most recent)
  - Time in daylight (sum)
  - Wrist temperature (average)
  - Body temperature (most recent)
  - RMSSD (computed from overnight RR intervals)
  ↓
HealthSyncer.postToServer()
  ↓
POST /api/health-sync with Bearer token
  {
    "user_id": 1,
    "date": "2026-04-05",
    "steps": 8432,
    "hrv": 45.2,
    ...
  }
  ↓
Flask receives, validates, stores in HealthData table
  ↓
Response: {"ok": true, "fields_updated": [...]}
  ↓
HealthSyncer updates @Published lastResult
  ↓
UI shows "synced 9 fields: steps, hrv, ..."
```

### 2. Automatic Evening Sync (Background)

```
iOS triggers BGAppRefreshTask at ~8 PM
  ↓
BackgroundSyncTask.handle()
  ↓
Step 1: HealthSyncer.syncNowSilent()
  - Same HealthKit queries as manual sync
  - Silent (no UI updates)
  - Callback on completion
  ↓
Step 2: FlareChecker.fetchStatus()
  - GET /api/flare-status?user_id=1
  - Returns: score, predicted_flare, score_delta, doses_due
  ↓
Step 3: Evaluate alert conditions
  - If predicted_flare == true → threshold alert
  - If score_delta >= 3.0 → trend alert
  ↓
Step 4: NotificationManager schedules notifications
  - Flare alerts (immediate)
  - Med dose reminders for tomorrow
  - Bedtime log reminder (daily repeating)
  ↓
Step 5: Update lastSyncTimestamp in UserDefaults
  ↓
Step 6: task.setTaskCompleted(success: true)
  ↓
Step 7: BackgroundSyncTask.scheduleNextSync()
  - Queues next day's background task
```

### 3. Notification Delivery → User Action

```
iOS delivers notification at scheduled time
  ↓
User taps notification
  ↓
NotificationManager.userNotificationCenter(didReceive:)
  ↓
If category == BEDTIME_LOG or MED_DOSE:
  Post Notification.Name.openLogTab
  ↓
ContentView receives notification
  ↓
Sets selectedTab = 1 (Log tab)
  ↓
App opens with Log web view visible
```

---

## Key Components

### HealthSyncer.swift
**Purpose:** Core HealthKit integration and network sync  
**Responsibilities:**
- Request HealthKit authorization for all needed data types
- Query HealthKit using optimized methods (sum, average, most recent)
- Compute RMSSD from heartbeat series (RR intervals during sleep)
- Format data as JSON payload
- POST to /api/health-sync with Bearer token authentication
- Handle backfill for historical data (days 0 to N in reverse chronological order)
- Provide both UI-updating (`syncNow()`) and silent (`syncNowSilent()`) variants

**Key Methods:**
- `requestAuthorization()` — one-time HealthKit permission request
- `syncNow()` — interactive sync with UI feedback
- `syncNowSilent()` — background sync with completion callback
- `backfillHealthData()` — batch sync for historical days
- Query helpers: `querySum()`, `queryAverage()`, `queryMostRecent()`, `queryRMSSD()`

### BackgroundSyncTask.swift
**Purpose:** Automated daily sync via BGTaskScheduler  
**Responsibilities:**
- Register `com.biotracking.healthsync.daily` task with iOS
- Schedule next execution around target hour (default 8 PM)
- Execute full sync → flare check → notification scheduling pipeline
- Handle task expiration gracefully
- Update last sync timestamp

**Key Methods:**
- `register()` — called once at app init
- `scheduleNextSync()` — queues next day's task
- `handle(task:)` — executes the background workflow

**Important:** iOS controls actual execution time. App *requests* 8 PM but may run earlier/later based on system heuristics.

### FlareChecker.swift
**Purpose:** Fetch flare risk data from Flask API  
**Responsibilities:**
- GET /api/flare-status with Bearer token
- Decode JSON response into Swift structs
- Evaluate alert conditions (threshold crossed, rapid trend)
- Return structured data for notification scheduling

**Data Models:**
- `FlareStatus` — decoded API response
- `FlareStatusFactor` — individual risk factors (UV, symptoms, etc.)
- `DoseReminder` — medication doses due
- `AlertEvaluation` — processed alert decision

**Key Methods:**
- `fetchStatus()` — async network call
- `evaluate()` — business logic for alert triggers

### NotificationManager.swift
**Purpose:** All local notification handling  
**Responsibilities:**
- Request notification permissions
- Register notification categories (BEDTIME_LOG, MED_DOSE, FLARE_THRESHOLD, FLARE_TREND)
- Schedule notifications with appropriate triggers
- Handle notification taps (deep linking)
- De-duplicate alerts (don't re-alert same day)
- Present notifications even when app is in foreground

**Notification Types:**
1. **Bedtime Log Reminder** — daily repeating at configured hour
2. **Med Dose Reminders** — scheduled per /api/flare-status response
3. **Flare Threshold Alert** — when predicted_flare == true
4. **Flare Trend Alert** — when score_delta exceeds threshold

**Key Methods:**
- `setup()` — register categories, set delegate
- `requestAuthorization()` — iOS permission prompt
- `scheduleBedtimeReminder()` — UNCalendarNotificationTrigger (repeating)
- `scheduleDoseReminders()` — batch schedule tomorrow's doses
- `scheduleFlareThresholdAlert()` — immediate trigger with de-dupe
- `scheduleFlareTrendAlert()` — immediate trigger with de-dupe

### BioTrackerWebView.swift
**Purpose:** Embed Flask mobile pages in native UI  
**Responsibilities:**
- Wrap WKWebView in SwiftUI view
- Handle loading states and errors
- Persist cookies for authentication
- Prevent external navigation (open in Safari instead)
- Show user-friendly error when Tailscale unreachable

**Features:**
- Loading indicator during page load
- Retry button on network failure
- Gestural back/forward navigation
- Domain-scoped navigation (stays within <YOUR_SERVER>)

### SyncSettingsView.swift
**Purpose:** User-facing settings and sync controls  
**Responsibilities:**
- Display server configuration (URL, token, user ID)
- Manual sync button with visual feedback
- HealthKit authorization trigger
- Notification settings (enable/disable, timing, thresholds)
- Historical backfill with progress tracking
- Display last sync timestamp

**Configuration Keys (AppStorage):**
- `serverURL` — Flask endpoint
- `apiToken` — Bearer token
- `userID` — numeric user ID
- `notificationsEnabled` — master toggle
- `bedtimeReminderHour` — notification time
- `syncHour` — background task target time
- `flareScoreTrendThreshold` — delta for trend alerts
- `lastSyncTimestamp` — last successful sync ISO date

### ShortcutIntents.swift
**Purpose:** iOS Shortcuts integration  
**Responsibilities:**
- Expose app actions to Shortcuts app
- Handle deep linking from Shortcuts
- Execute background sync via Shortcuts/Siri

**Actions:**
1. **Open Biotracker Log** — posts notification to switch to Log tab
2. **Sync Biotracker** — executes `syncNowSilent()`, returns success message

**Usage:**
- Add to Shortcuts app for manual triggers
- Use in iOS Automations (e.g., "Every day at 9 PM → Open Biotracker Log")
- Invoke via Siri ("Hey Siri, sync biotracker")

---

## Security & Privacy

### HealthKit Data
- **Never leaves the device unencrypted** — only transmitted over HTTPS
- **User controls permissions** — can revoke HealthKit access anytime via Health app
- **No HealthKit data stored locally** — queried on-demand, sent to server, discarded
- **Background delivery respects user permissions** — if user revokes access, sync fails gracefully

### Network Authentication
- **Bearer token authentication** — token stored in iOS Keychain via `@AppStorage` (Keychain-backed)
- **HTTPS only** — all network requests use TLS
- **No hardcoded credentials** — user must configure token manually

### Notification Privacy
- **All processing on-device** — app fetches data, decides alerts locally
- **No remote notifications (APNs)** — no third-party servers involved
- **User controls notification permissions** — can disable per-category in iOS Settings

### Web View Isolation
- **Default WKWebView data store** — persistent cookies, but isolated from Safari
- **No JavaScript injection** — web view displays biotracker pages unmodified
- **Domain-scoped navigation** — can't navigate to external sites (opens Safari instead)

---

## Scalability & Performance

### HealthKit Query Optimization
- **Predicate-based queries** — only fetch data for specific date ranges
- **Aggregated results** — use HKStatisticsQuery for sums/averages (efficient)
- **Asynchronous execution** — all queries run in background, callback on completion
- **Rate limiting on backfill** — 0.5s delay between days to avoid server overload

### Background Task Efficiency
- **Minimal execution time** — queries + network typically complete in <30 seconds
- **Expiration handling** — abort gracefully if iOS terminates task early
- **Battery awareness** — iOS automatically throttles background tasks on low battery

### Network Resilience
- **Timeout handling** — 15-second timeout on API requests
- **Error recovery** — failed sync doesn't crash, retries next cycle
- **Offline graceful degradation** — web views show error, notifications don't fire

---

## Future Enhancements (Out of Scope for v1.0)

### Potential Additions
- **Widget** — Today's flare score on home screen
- **Watch app** — Quick log entry, step count display
- **HealthKit write** — Update HealthKit with corrected data from server
- **APNs integration** — Server-initiated push notifications (requires server changes)
- **Local caching** — Store last flare status for offline viewing
- **Charts** — Native Swift Charts views for historical trends (instead of web views)
- **Siri suggestions** — Proactive suggestions based on usage patterns

---

## Maintenance & Troubleshooting

### Common Issues

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Background sync never runs | Low battery / Low Power Mode | Charge device, disable LPM |
| Notifications don't fire | Permissions denied | Check Settings → Notifications |
| HealthKit data missing | Permissions not granted | Health app → Sharing → healthsync |
| Web views blank | Tailscale disconnected | Reconnect Tailscale VPN |
| Sync fails with 401 | Invalid API token | Re-enter token in settings |

### Debugging Tools
- **Xcode Console** — view HealthKit query results, network responses
- **BGTaskScheduler simulation** — force background task execution
- **Notification Inspector** — view scheduled notifications in Settings
- **Charles Proxy** — inspect network traffic (HTTPS decryption)

### Logging Strategy
- Print statements in key methods (sync start/end, notification schedule)
- Log API responses (status code, body)
- Track background task execution (start time, completion status)

**Production:** Consider integrating OSLog for persistent logging without performance penalty.

---

## Dependencies

### Apple Frameworks
- **HealthKit** — health data access
- **BackgroundTasks** — BGTaskScheduler for daily sync
- **UserNotifications** — UNUserNotificationCenter for local notifications
- **WebKit** — WKWebView for embedded web pages
- **SwiftUI** — declarative UI
- **AppIntents** — Shortcuts integration

### Third-Party Libraries
- **None** — pure Apple frameworks, no external dependencies

### Server Dependencies
- Flask biotracker at `https://<YOUR_SERVER>`
- `/api/health-sync` endpoint (existing)
- `/api/flare-status` endpoint (NEW, must be implemented)

---

## Versioning

**Current Version:** 1.0  
**iOS Minimum:** 17.0  
**Swift Version:** 5.x  

**Change Log:**
- 2026-04-05: Initial implementation (all features from spec)

---

## Credits

**Developer:** Alaric Moore  
**AI Assistant:** Aplaude (Claude Opus)  
**Spec Author:** Alaric + Wolf (Claude Opus)  
**Platform:** iOS / Swift / HealthKit  

---

## License

Personal project — all rights reserved.  
Code is for Alaric's personal biotracker system and is not open source.

---

**For implementation details, see:**
- `XCODE_SETUP.md` — Project configuration checklist
- `TESTING_GUIDE.md` — Comprehensive testing procedures
- `flask_flare_status_endpoint.py` — Server-side API implementation guide
