# Notification Content Reference

This document shows exactly what each notification type looks like when delivered to the user.

---

## 1. Bedtime Log Reminder

**Category:** `BEDTIME_LOG`  
**Trigger:** Daily repeating at configured hour (default 9:00 PM)  
**Badge:** None (could add count of unlogged days in future)

### Appearance
```
┌─────────────────────────────────────┐
│  healthsync                    9:00 PM │
│                                       │
│  Time to log                         │
│  How was today?                      │
└─────────────────────────────────────┘
```

### Behavior
- **Tap:** Opens app to Log tab
- **Swipe away:** Dismissed (will repeat tomorrow)
- **Long press:** Shows notification options (Turn Off, Settings)

### Implementation
```swift
let content = UNMutableNotificationContent()
content.title = "Time to log"
content.body = "How was today?"
content.sound = .default
content.categoryIdentifier = "BEDTIME_LOG"
```

---

## 2. Medication Dose Reminder

**Category:** `MED_DOSE`  
**Trigger:** Specific time based on dose schedule from `/api/flare-status`  
**Scheduled:** Once per dose, for tomorrow's doses  

### Appearance
```
┌─────────────────────────────────────┐
│  healthsync                    8:00 AM │
│                                       │
│  Medication Reminder                 │
│  Time for 4mg methylprednisolone     │
└─────────────────────────────────────┘
```

### Behavior
- **Tap:** Opens app to Log tab (where doses are logged)
- **Swipe away:** Dismissed (won't repeat — one-time notification)

### Implementation
```swift
for dose in doses {
    let content = UNMutableNotificationContent()
    content.title = "Medication Reminder"
    content.body = "Time for \(dose.doseLabel) \(dose.drugName)"
    content.sound = .default
    content.categoryIdentifier = "MED_DOSE"
    // Scheduled for tomorrow at dose.scheduledTime
}
```

### Example Doses
- **8:00 AM:** "Time for 4mg methylprednisolone"
- **12:00 PM:** "Time for 4mg methylprednisolone"
- **4:00 PM:** "Time for 4mg methylprednisolone"
- **8:00 PM:** "Time for 4mg methylprednisolone"

*(Typical medrol pack taper schedule)*

---

## 3. Flare Risk Alert — Threshold Crossed

**Category:** `FLARE_THRESHOLD`  
**Trigger:** Immediate when evening sync detects `predicted_flare == true`  
**De-duplication:** Won't re-alert same day

### Appearance
```
┌─────────────────────────────────────┐
│  healthsync                     Now │
│                                       │
│  Flare Risk Elevated                 │
│  Flare risk is elevated — score 9.2/ │
│  20. Take it easy tomorrow.          │
└─────────────────────────────────────┘
```

### Behavior
- **Tap:** Opens app (no specific tab)
- **High priority:** Uses default sound, shows on lock screen

### Implementation
```swift
let content = UNMutableNotificationContent()
content.title = "Flare Risk Elevated"
content.body = "Flare risk is elevated — score \(score)/\(maxScore). Take it easy tomorrow."
content.sound = .default
content.categoryIdentifier = "FLARE_THRESHOLD"
```

### When It Fires
- Server calculates flare score >= threshold (default: 8.0)
- Returns `predicted_flare: true` in /api/flare-status
- Background sync evaluates condition, schedules notification
- Typical timing: Between 8-10 PM (during background sync window)

---

## 4. Flare Risk Alert — Rapid Trend

**Category:** `FLARE_TREND`  
**Trigger:** Immediate when evening sync detects score_delta >= threshold (default 3.0)  
**De-duplication:** Won't re-alert same day

### Appearance
```
┌─────────────────────────────────────┐
│  healthsync                     Now │
│                                       │
│  Risk Score Rising                   │
│  Risk score jumped +3.5 today — watch│
│  for flare signals.                  │
└─────────────────────────────────────┘
```

### Behavior
- **Tap:** Opens app (no specific tab)
- **High priority:** Uses default sound, shows on lock screen

### Implementation
```swift
let content = UNMutableNotificationContent()
content.title = "Risk Score Rising"
content.body = "Risk score jumped +\(delta) today — watch for flare signals."
content.sound = .default
content.categoryIdentifier = "FLARE_TREND"
```

### When It Fires
- Server calculates: today's score - yesterday's score >= 3.0
- Returns `score_delta: 3.5` (or higher) in /api/flare-status
- Background sync evaluates condition, schedules notification
- Can fire same evening as threshold alert (independent conditions)

---

## Alert Combinations

User can receive multiple alerts in one evening:

### Example: Bad Day
```
8:30 PM - "Risk Score Rising" (delta +3.5)
8:30 PM - "Flare Risk Elevated" (score 9.2/20)
9:00 PM - "Time to log" (bedtime reminder)
```

All three are independent and provide different information:
- **Trend alert** → Things got worse quickly today
- **Threshold alert** → Absolute risk level is high
- **Bedtime reminder** → Time to log the day

---

## Notification Timing

### Scheduled (Repeating)
- **Bedtime Log:** Daily at configured hour (9:00 PM default)

### Scheduled (One-time)
- **Med Doses:** Tomorrow at specific times (8:00 AM, 12:00 PM, etc.)

### Immediate (During Background Sync)
- **Flare Threshold:** Fires during evening sync (~8-10 PM)
- **Flare Trend:** Fires during evening sync (~8-10 PM)

---

## Testing Notifications

### Quick Test (10-second delay)
Add to SyncSettingsView for testing:
```swift
Button("Test Notification") {
    let content = UNMutableNotificationContent()
    content.title = "Test Alert"
    content.body = "This is a test notification"
    content.sound = .default
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
    let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}
```

### View Scheduled Notifications
Add debug button:
```swift
Button("Show Scheduled") {
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
        print("Scheduled notifications:")
        for req in requests {
            print("- \(req.identifier): \(req.content.title)")
        }
    }
}
```

### View Delivered Notifications
```swift
Button("Show Delivered") {
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
        print("Delivered notifications:")
        for notif in notifications {
            print("- \(notif.request.content.title)")
        }
    }
}
```

---

## Notification Permissions

User sees this system prompt on first launch:

```
┌─────────────────────────────────────┐
│  "healthsync" Would Like to Send    │
│  You Notifications                   │
│                                       │
│  Notifications may include alerts,  │
│  sounds, and icon badges. These     │
│  can be configured in Settings.     │
│                                       │
│     [ Don't Allow ]  [ Allow ]      │
└─────────────────────────────────────┘
```

**If user taps "Don't Allow":**
- Master toggle in app settings shows OFF
- Tapping toggle shows system prompt to open Settings
- User must manually enable in iOS Settings → Notifications → healthsync

**If user taps "Allow":**
- All notification types enabled by default
- User can configure in app settings (enable/disable, change times)
- Can also customize in iOS Settings (turn off sounds, badges, etc.)

---

## Notification Settings Hierarchy

### App-Level Controls
In app (SyncSettingsView):
- **Master toggle:** Enable/disable all notifications
- **Bedtime hour:** When to send log reminder
- **Sync hour:** When to run background sync (affects flare alert timing)
- **Trend threshold:** How much delta triggers trend alert

### iOS System Controls
In Settings → Notifications → healthsync:
- **Allow Notifications:** ON/OFF (master)
- **Show in Notification Center:** ON/OFF
- **Sounds:** ON/OFF
- **Badges:** ON/OFF
- **Show on Lock Screen:** ON/OFF
- **Show in CarPlay:** ON/OFF
- **Notification Grouping:** Automatic/By App/Off

### Focus Mode
User can silence notifications during Focus modes:
- Settings → Focus → [Mode] → Apps → healthsync
- Options: Allow Notifications / Silence Notifications
- Can set different rules per Focus mode (Sleep, Work, etc.)

---

## Accessibility

### VoiceOver
All notifications are VoiceOver-compatible:
- Speaks title + body
- Can navigate to app via tap

### Font Size
Notification text respects iOS Dynamic Type:
- Larger text sizes render correctly
- Body text may truncate if very long

### Reduce Motion
Notification banners respect Reduce Motion setting:
- Fade in instead of slide if enabled

---

## Best Practices

### Keep Body Text Concise
- Notifications truncate after ~150 characters
- Most important info should be in first ~60 characters
- Use em dash (—) not hyphen (-) for readability

### Actionable Information
- Tell user what to do: "Take it easy tomorrow"
- Give context: "score 9.2/20" (not just "high risk")
- Be specific: "4mg methylprednisolone" (not just "your med")

### Avoid Notification Fatigue
- De-duplicate: Don't re-alert same day
- Consolidate: One notification per event, not multiple
- Respect user settings: Honor master toggle

### Timing
- Bedtime reminder: After dinner, before bed (9 PM works well)
- Med reminders: At actual dose times (not "you have doses today")
- Flare alerts: Evening so user can plan tomorrow

---

## Future Enhancements (Not Implemented Yet)

### Notification Actions
Add quick actions to notifications:

**Med Dose:**
- "Mark Taken" → POST to server without opening app
- "Skip Dose" → Log as skipped

**Bedtime Log:**
- "Log Now" → Deep link with quick entry form
- "Remind Me in 30 Min" → Snooze

**Flare Alert:**
- "View Risk Factors" → Open to Risk tab
- "Dismiss" → Standard dismissal

### Rich Notifications
- Attach small chart image showing score trend
- Show avatar/icon for med type

### Notification Grouping
- Group all med doses under one expandable notification
- Separate thread IDs for flare alerts vs reminders

### Critical Alerts
- For extremely high flare risk (score > 15?)
- Bypasses Do Not Disturb
- Requires special entitlement

---

## Notification Content Guidelines

### Title
- 3-5 words max
- Action-oriented or state-indicating
- Examples:
  - ✅ "Time to log"
  - ✅ "Medication Reminder"
  - ✅ "Flare Risk Elevated"
  - ❌ "healthsync notification"
  - ❌ "You have an alert"

### Body
- One sentence preferred, two max
- Include actionable data (numbers, specifics)
- End with what user should do
- Examples:
  - ✅ "How was today?" (clear CTA)
  - ✅ "Time for 4mg methylprednisolone" (specific)
  - ✅ "Risk score jumped +3.5 today — watch for flare signals." (data + action)
  - ❌ "You should check the app"
  - ❌ "Something happened with your biotracker account"

### Sound
- Use `.default` for most notifications
- Consider silent for low-priority info
- Critical alerts get special sound (not implemented)

---

## Debugging Notification Issues

### Notifications Not Appearing

**Check 1:** Permission granted?
```swift
UNUserNotificationCenter.current().getNotificationSettings { settings in
    print("Authorization status: \(settings.authorizationStatus)")
    // .authorized = good
    // .denied = user declined
    // .notDetermined = haven't asked yet
}
```

**Check 2:** Notification scheduled?
```swift
UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
    print("Pending: \(requests.count)")
    for req in requests {
        print("- \(req.identifier) at \(req.trigger?.nextTriggerDate())")
    }
}
```

**Check 3:** Focus mode blocking?
- Check Control Center → Focus indicator
- Disable temporarily to test

**Check 4:** Notification delivered but cleared?
```swift
UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
    print("Delivered: \(notifications.count)")
}
```

### Duplicate Notifications

**Issue:** Same notification fires multiple times  
**Cause:** Not removing old requests before scheduling new  
**Fix:** Call `removePendingNotificationRequests()` first

Example in NotificationManager:
```swift
// Remove old bedtime reminders before scheduling new one
center.removePendingNotificationRequests(withIdentifiers: ["bedtime_log_daily"])
```

### Wrong Timing

**Issue:** Notification fires at unexpected time  
**Cause:** Timezone mismatch or calendar component error  
**Fix:** Always use `Calendar.current` and verify components

```swift
var components = DateComponents()
components.hour = 21
components.minute = 0
// Use current calendar, not UTC!
let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
```

---

## Summary

Your app has 4 notification types with clear purposes:

1. **Bedtime Log** → Habit formation (daily log entry)
2. **Med Doses** → Medication adherence (take on time)
3. **Flare Threshold** → Risk awareness (score crossed threshold)
4. **Flare Trend** → Early warning (rapid score increase)

All are scheduled locally (no server push), respect user preferences, and provide actionable information. Implementation is complete and ready to test! 🔔
