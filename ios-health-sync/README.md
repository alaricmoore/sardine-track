# Health Sync — iOS companion app for Biotracker

Reads Apple Health data and sends it to your biotracker instance. Replaces the iOS Shortcut with a native app that can access everything HealthKit offers.

## What it syncs

- Steps (daily total)
- HRV / SDNN (most recent)
- RMSSD (computed from overnight RR intervals, 10pm-8am)
- Resting heart rate
- Body temperature (BBT)
- SpO2 / blood oxygen
- Respiratory rate
- Time in daylight (sun exposure minutes)

## Xcode setup (one-time)

1. Open Xcode
2. File > New > Project > iOS > App
3. Product Name: **HealthSync**
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Save it somewhere (e.g., your Desktop)
7. Delete the default ContentView.swift that Xcode created
8. Drag these files from this folder into the Xcode project navigator:
   - `HealthSyncApp.swift`
   - `HealthSyncer.swift`
   - `ContentView.swift`
9. In Xcode, select the project (blue icon at top of navigator)
10. Select the **HealthSync** target
11. Go to **Signing & Capabilities** tab
12. Click **+ Capability** and add **HealthKit**
13. In the HealthKit capability that appears, check **Background Delivery** if available
14. Go to the **Info** tab and add these keys (or merge from Info.plist):
    - `NSHealthShareUsageDescription`: "Health Sync reads your health data to send it to your personal biotracker for flare pattern analysis."
15. Build and run on your iPhone (not simulator — simulator doesn't have HealthKit data)

## First run

1. The app will ask for HealthKit permissions — allow everything
2. Enter your server URL: `https://<YOUR_SERVER>/api/health-sync`
3. Enter your API token (from config.json on the Pi)
4. User ID: 1
5. Tap "Sync Now"
6. Check the status line — should show "synced X fields: steps, hrv, ..."

## Automation

To run automatically each night:

1. Open the Shortcuts app
2. Go to Automation tab
3. Create: When **Bedtime begins** > Run Shortcut
4. In the shortcut, add: **Open App** > HealthSync
5. Then add: **Wait** 5 seconds
6. Then add: **URL** > `shortcuts://x-callback-url/...` (or just let it open and sync)

Alternatively, you can add background refresh in a future version.

## Notes

- RMSSD uses RR intervals from 10pm-8am (overnight window). If your polyphasic sleep schedule means you're awake during this window sometimes, the readings may be noisier but still useful as a trend.
- The app computes RMSSD on-device and sends only the final value to your server.
- Free to sideload via Xcode with a personal Apple ID (no $99 developer account). Apps sideloaded this way expire after 7 days and need to be re-installed, but the data/settings persist.
- SpO2 data availability depends on your Apple Watch model (Series 6+).
