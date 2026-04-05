# Biotracker iOS App Testing Guide

## Pre-Testing Setup

1. **Xcode Project Configuration**
   - [ ] Verify Info.plist has `BGTaskSchedulerPermittedIdentifiers` array
   - [ ] Verify Info.plist has `NSHealthShareUsageDescription`
   - [ ] Check Signing & Capabilities → HealthKit is enabled
   - [ ] Check Signing & Capabilities → Background Modes includes "Background processing"
   - [ ] Verify healthsync.entitlements includes:
         - `com.apple.developer.healthkit`
         - `com.apple.developer.healthkit.background-delivery`

2. **Server Setup**
   - [ ] Add `/api/flare-status` endpoint to Flask app.py
   - [ ] Deploy updated Flask app to <YOUR_SERVER>
   - [ ] Test endpoint manually: `curl -H "Authorization: Bearer YOUR_TOKEN" "https://<YOUR_SERVER>/api/flare-status?user_id=1"`

3. **Device Setup**
   - [ ] Install app on iPhone via Xcode
   - [ ] Ensure Tailscale is connected
   - [ ] Enable notifications in iOS Settings → healthsync → Notifications

## Feature Testing

### 1. HealthKit Authorization ✓
- [ ] Launch app → Sync tab
- [ ] Tap "Authorize HealthKit"
- [ ] Verify permission sheet appears
- [ ] Grant all requested permissions
- [ ] Confirm "HealthKit authorized" message

### 2. Manual Sync ✓
- [ ] Fill in Server URL: `https://<YOUR_SERVER>/api/health-sync`
- [ ] Fill in API Token (from your Flask config)
- [ ] Fill in User ID: `1`
- [ ] Tap "Sync Health Data" button
- [ ] Verify "syncing..." state with progress indicator
- [ ] Wait for completion
- [ ] Verify "synced X fields: steps, hrv, ..." message
- [ ] Check Flask server logs for successful POST
- [ ] Verify data appears in biotracker web UI

### 3. WKWebView Integration ✓
- [ ] Tap "Log" tab
- [ ] Verify loading indicator appears
- [ ] Verify biotracker log page loads
- [ ] Test entering data in the web form
- [ ] Tap "Risk" tab
- [ ] Verify forecast/status page loads
- [ ] Test navigation between web pages
- [ ] Disconnect Tailscale
- [ ] Verify error message: "Can't reach biotracker — Is Tailscale connected?"
- [ ] Tap "Retry" button
- [ ] Reconnect Tailscale, verify page loads

### 4. Notifications Setup ✓
- [ ] Go to Sync tab → Notifications section
- [ ] Toggle "Enable Notifications" ON
- [ ] Verify system permission prompt (if first time)
- [ ] Change "Bedtime Reminder" to desired hour
- [ ] Change "Auto-Sync Target" to desired hour
- [ ] Set "Trend Alert Threshold" (e.g., 3.0)

### 5. Bedtime Notification (Quick Test) 🧪
**For testing, manually schedule a notification 10 seconds from now:**

In `SyncSettingsView.swift`, temporarily add a debug button:
```swift
Button("Test Bedtime Notification (10s)") {
    let content = UNMutableNotificationContent()
    content.title = "Time to log"
    content.body = "How was today?"
    content.sound = .default
    content.categoryIdentifier = NotificationManager.bedtimeLogCategory
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
    let request = UNNotificationRequest(identifier: "test_bedtime", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}
```

- [ ] Tap test button
- [ ] Wait 10 seconds
- [ ] Verify notification appears
- [ ] Tap notification
- [ ] Verify app opens to Log tab
- [ ] Remove debug button after testing

### 6. Background Sync (Xcode Simulator) 🧪
**Testing background tasks requires Xcode debugging:**

1. Run app on device from Xcode
2. Ensure settings are configured (server URL, token, etc.)
3. In Xcode → Debug menu → Pause execution (or just let it run)
4. In Xcode Console (Cmd+Shift+Y), paste:
   ```
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.biotracking.healthsync.daily"]
   ```
5. Resume execution
6. Watch console logs for:
   - "Starting background sync..."
   - HealthKit queries
   - Network requests
   - "Background sync completed"
7. Check:
   - [ ] lastSyncTimestamp updated in app UI
   - [ ] Data synced to server
   - [ ] Flare status fetched
   - [ ] Notifications scheduled (check Notification Center → Scheduled)

### 7. Flare Alerts (Mock Data) 🧪
**To test flare alerts, you need to:**

Option A: Modify server to return mock data:
- Temporarily edit `/api/flare-status` to return `predicted_flare: true` and `score_delta: 4.0`
- Trigger background sync (method above)
- Verify both flare threshold AND trend alerts fire

Option B: Add debug button to force-fetch:
```swift
Button("Test Flare Check") {
    FlareChecker.shared.fetchStatus(
        serverURL: serverURL, 
        apiToken: apiToken, 
        userID: userID
    ) { status in
        if let status = status, status.ok,
           let eval = FlareChecker.shared.evaluate(status: status, trendThreshold: 3.0) {
            if eval.thresholdCrossed {
                NotificationManager.shared.scheduleFlareThresholdAlert(
                    score: eval.score, 
                    maxScore: eval.maxScore
                )
            }
            if eval.trendAlert {
                NotificationManager.shared.scheduleFlareTrendAlert(delta: eval.scoreDelta)
            }
        }
    }
}
```

- [ ] Trigger flare check
- [ ] Verify threshold alert fires when `predicted_flare == true`
- [ ] Verify trend alert fires when delta >= threshold
- [ ] Tap alerts, verify app behavior
- [ ] Check de-duplication (shouldn't re-alert same day)

### 8. Med Dose Reminders 🧪
**Requires Flask dose schedule implementation:**

If you have a dose schedule system:
- [ ] Add doses for tomorrow in Flask
- [ ] Trigger background sync (simulates evening sync)
- [ ] Check iOS Settings → Notifications → Scheduled
- [ ] Verify dose reminders scheduled for tomorrow at correct times
- [ ] Let one fire (or simulate time)
- [ ] Tap notification, verify opens to Log tab

### 9. Shortcuts Integration ✓
- [ ] Open iOS Shortcuts app
- [ ] Create new shortcut
- [ ] Search for "Open Biotracker Log"
- [ ] Add action, save shortcut
- [ ] Run shortcut
- [ ] Verify app opens to Log tab

- [ ] Create another shortcut
- [ ] Search for "Sync Biotracker"
- [ ] Add action, save shortcut
- [ ] Run shortcut
- [ ] Verify sync completes, check return message

- [ ] Optional: Create automation (Settings → Automation)
  - Trigger: Time of Day (9:00 PM)
  - Action: Run "Open Biotracker Log" shortcut
  - Test at 9 PM

### 10. Historical Backfill ✓
- [ ] Go to Sync tab
- [ ] Scroll to "Historical Data" section
- [ ] Select a preset (e.g., "Week" = 7 days)
- [ ] Tap "Start Backfill"
- [ ] Verify progress bar appears
- [ ] Verify status updates: "Processing 2026-04-04 (1/7)..."
- [ ] Wait for completion
- [ ] Verify final message: "Completed! Synced X days, skipped Y (no data)"
- [ ] Check server to confirm historical data populated

## Production Testing

After Xcode testing passes:

1. **Real-world background sync**
   - [ ] Set syncHour to current time + 1 hour
   - [ ] Close app completely (swipe up from app switcher)
   - [ ] Wait for the target hour
   - [ ] Re-open app after ~5-15 minutes past target hour
   - [ ] Check "Last auto-sync" timestamp
   - [ ] Verify data synced

2. **Multi-day usage**
   - [ ] Use app naturally for 3-5 days
   - [ ] Monitor notification delivery
   - [ ] Check sync reliability
   - [ ] Review battery impact (Settings → Battery)

3. **Error handling**
   - [ ] Disconnect Tailscale, verify graceful degradation
   - [ ] Invalid API token → verify error messages
   - [ ] Airplane mode → verify no crashes, proper errors

## Troubleshooting

### Background sync not firing
- Check: Settings → General → Background App Refresh → healthsync (must be ON)
- Check: Device has power (iOS throttles background tasks on low battery)
- Check: Device is not in Low Power Mode
- Try: Plug in device overnight (iOS prioritizes background tasks when charging)

### Notifications not appearing
- Check: Settings → Notifications → healthsync → Allow Notifications (ON)
- Check: Settings → Screen Time → Content & Privacy Restrictions → Allowed Apps → healthsync (ON if Screen Time is used)
- Check: Do Not Disturb / Focus mode settings

### HealthKit data not syncing
- Check: iPhone has HealthKit data (Health app → Browse)
- Check: HealthKit permissions granted (Health app → Sharing → Apps → healthsync)
- Try: Re-authorize in app

### Web views not loading
- Check: Tailscale connection (Tailscale app → verify green)
- Check: Server URL is correct (no typos, includes https://)
- Check: Flask server is running
- Try: Open <YOUR_SERVER> in Safari first

## Completion Criteria

✅ App is ready for production when:
- [ ] All manual tests pass
- [ ] Background sync works at least once
- [ ] Notifications deliver reliably
- [ ] No crashes in 3 days of testing
- [ ] Battery usage acceptable (<5% per day)
- [ ] Web views load consistently on Tailscale
- [ ] Shortcuts execute successfully

---

**Note:** Background task scheduling on iOS is not guaranteed. Apple controls when background tasks actually run based on device usage patterns, battery level, and other factors. The app requests a specific time, but iOS may execute it earlier or later (typically within 1-4 hours of the requested time).
