# Biotracker — Help Guide

*A plain-English guide to using the app and understanding what it's tracking.*

---

## What Is This App?

Biotracker is a personal health logging app built specifically for people managing photosensitive autoimmune and rheumatic conditions — things like lupus, mixed connective tissue disease, or any illness where symptoms are unpredictable, hard to explain to doctors, and deeply affected by things like sun exposure, sleep, and hormonal cycles.

It was built by Alaric, who has lupus, because she couldn't find a tool that did what she actually needed: connect the dots between daily life and disease activity, and produce something useful to bring to a 15-minute doctor's appointment.

Your data lives on Alaric's private server. It is not sold, shared, or sent anywhere. UV index data is pulled from a public weather API anonymously — that's the only outside connection the app makes.

---

## What Should I Log Every Day?

The daily entry form is the core of the app. You don't have to fill out every field — log what feels relevant. The more consistently you log, even minimally, the more useful the patterns become over time.

**The most important fields for the prediction model are:**
- Symptoms (how many, how severe)
- Sleep quality
- UV index (auto-filled based on your location, but you can adjust it)
- Flare: yes or no

Everything else adds context and richness over time.

**On hard days**, there's a simplified quick-entry mode that shows only the fields the model needs. You can reach it by adding `?mode=quick` to the end of the daily entry URL.

---

## What the Numbers Mean

### Pain Scale (1–10)
- **1–3**: Mild, noticeable but not limiting
- **4–6**: Moderate, affecting what you can do
- **7–9**: Severe, significantly limiting
- **10**: Worst pain imaginable / emergency territory

### Fatigue Scale (1–10)
Same idea. A 7 fatigue day is "I cannot get up even though I want to." A 3 is "tired but functional."

### UV Index
This is a measure of how strong the ultraviolet radiation from the sun is on a given day, on a scale from 0 to 11+.

| UV Index | Level |
|----------|-------|
| 0–2 | Low |
| 3–5 | Moderate |
| 6–7 | High |
| 8–10 | Very High |
| 11+ | Extreme |

For photosensitive conditions, UV exposure on one day can trigger a flare one, two, or even three days later — not necessarily the same day. The app tracks this lag and shows you your personal pattern.

---

## What Is HRV?

**HRV stands for Heart Rate Variability.** It sounds technical but the concept is simple.

Your heart doesn't beat like a metronome. Even at rest, the time between beats varies slightly — sometimes a bit longer, sometimes a bit shorter. That variation is HRV.

**Higher HRV** generally means your nervous system is relaxed, recovered, and adaptable. Your body has resources to work with.

**Lower HRV** generally means your body is under stress — from illness, poor sleep, inflammation, or overexertion.

For people with autoimmune conditions, HRV can drop noticeably in the day or two *before* a flare becomes obvious. It's your body signaling that something is off before you fully feel it.

You can track HRV with a wearable like an Apple Watch, Garmin, Fitbit, or Whoop. The app lets you log your morning HRV reading and visualize how it trends alongside your symptoms over time.

You don't have to track HRV to use the app — it's an optional field. But if you have a device that measures it, it's one of the more interesting things to correlate with flare activity.

---

## What Is Basal Body Temperature (BBT)?

**Basal body temperature is your body temperature at complete rest** — typically measured first thing in the morning before getting up, eating, or doing anything. It's usually taken with a special BBT thermometer that reads to two decimal places (like 97.42°F rather than just 97.4°F), though a regular digital thermometer works too.

### Why does it matter for autoimmune disease?

BBT does two useful things in this context:

**1. It can signal inflammation.** When your immune system is active — fighting something, reacting to a trigger — your resting temperature can shift subtly before you feel obviously sick. A pattern of slightly elevated morning temperatures can be an early signal.

**2. It tracks your menstrual cycle phase.** This matters because hormonal cycles interact with immune activity. After ovulation, progesterone causes BBT to rise by about 0.2–0.5°F and stay elevated until your next period. The app detects this shift to figure out which phase of your cycle you're in — which is much more accurate than just counting days, especially if steroids or disease activity make your cycle irregular.

### How to log it

Take your temperature first thing in the morning, before getting out of bed, and log it in the daily entry. Even just a few months of data starts to reveal patterns.

---

## The Forecast Model

After 7 days of logging, the app starts generating a daily flare risk score. This is not a medical prediction — it's a statistical pattern based on *your own* historical data.

The model looks at:
- Yesterday's and today's UV index
- Your symptom levels over the past few days
- Sleep quality
- HRV trends (if logged)
- Cycle phase (if cycle tracking is enabled)

It compares current conditions to the conditions that preceded past flares in your own history, and produces a risk score from 0 to 25.

**The more data you have, the more accurate it becomes.** Early on it will be rough. Over months, it gets meaningful.

You can see the breakdown of what's contributing to today's score on the Forecast page.

---

## The Clinical Record

This section is for organizing the medical side of your life — not just symptoms.

- **Labs**: Log test results with values, reference ranges, and dates
- **Medications**: Track what you've taken and when, with start and end dates
- **Clinical Events**: Appointments, ER visits, procedures — with notes
- **Clinicians**: A directory of your care team
- **ANA Tracking**: Specialized tracking for ANA titers and patterns (relevant for lupus diagnosis)

You can export any of these as a CSV file, which is useful for sending to a new provider, requesting records, or just keeping a personal copy.

---

## Notifications (ntfy)

The app can send you a daily reminder to log, and an alert if your flare risk is elevated. This uses a free service called ntfy — you install the ntfy app on your phone, subscribe to a private channel, and that's it. No account required.

Setup instructions are in your account profile.

---

## Auto-Sync from Apple Health (iOS Shortcut)

If you have an Apple Watch, you can set up your iPhone to automatically send your health data to the biotracker every night — no manual entry required for steps, HRV, resting heart rate, or basal body temperature.

This uses **iOS Shortcuts**, a built-in iPhone feature that lets you chain together small actions (like "read my step count" and "send it to a website") without writing any code.

### What gets synced

- **Steps** — your total for the day
- **HRV** — heart rate variability from your watch
- **Resting heart rate** — useful for tracking tachycardia or inflammation patterns
- **Basal body temperature** — the delta your watch calculates from your personal baseline

### What doesn't get synced

- **Sleep** — Apple Health has trouble with polyphasic sleep and sleepwalking, so sleep is better entered manually
- **Sun exposure minutes** — Apple tracks "Time in Daylight" on the watch but doesn't make it available to Shortcuts (thanks, Apple)
- **Symptoms, flare status, notes** — these are personal observations that only you can provide

### How to set it up

1. Open the **Shortcuts** app on your iPhone (it's pre-installed — blue and pink icon)
2. Tap **+** to create a new shortcut, name it something like "Health Sync"
3. Use the search bar to add these actions in order:

**Get the date:**
- Add a **Date** action
- Add a **Format Date** action — set to Custom format: `yyyy-MM-dd`

**Pull your health data (add four "Find Health Samples" actions):**
- Step Count — sort by Start Date, Most Recent, limit 1
- Heart Rate Variability — sort by Start Date, Most Recent, limit 1
- Resting Heart Rate — sort by Start Date, Most Recent, limit 1
- Body Temperature — sort by Start Date, Most Recent, limit 1

For Steps, make sure you're getting the sum for the day, not just the last sample.

**Build the data package:**
- Add a **Dictionary** action with these keys:
  - `user_id` (Number) — your user ID, usually `1`
  - `date` (Text) — select the formatted date from earlier
  - `steps` (Number) — select the step count result
  - `hrv` (Number) — select the HRV result
  - `resting_heart_rate` (Number) — select the resting HR result
  - `basal_temp_delta` (Number) — select the body temperature result

**Send it:**
- Add **Get Contents of URL**
  - URL: your biotracker address followed by `/api/health-sync`
  - Method: POST
  - Add header `Authorization` with value `Bearer` followed by your API token (from config.json on the server)
  - Add header `Content-Type` with value `application/json`
  - Request Body: JSON — select the Dictionary

**Test it** by tapping the play button. You should see a response with `"ok": true`.

### Make it automatic

Go to the **Automation** tab in Shortcuts and set your shortcut to run automatically. Good trigger options:

- **Bedtime begins** — syncs when your wind-down starts
- **Time of Day** — set to late evening (like 11:50 PM)

Set it to **Run Immediately** so it doesn't ask for confirmation each time.

Once set up, your phone handles this in the background every night. On bad days — the days you need the data most — it's one less thing to do.

### A note about your API token

The token in your Shortcut gives write access to a limited set of biometric fields. It cannot touch your symptoms, medications, flare logs, or notes. But treat it like a password — don't share your Shortcut with anyone you wouldn't trust with your biotracker login.

---

## A Note on What This Is (and Isn't)

This app is not a medical device and does not give medical advice. It is a record-keeping and pattern-visualization tool.

What it does well:
- Helps you notice your own patterns
- Gives you something concrete to bring to appointments
- Creates a longitudinal record that would otherwise exist only as fragmented memories

What it can't do:
- Diagnose anything
- Replace your doctors
- Predict the future with certainty

Use it as evidence for conversations with your care team, not as a substitute for those conversations.

---

## Tips for Getting Started

**Log daily, even briefly.** Consistency matters more than completeness. A 30-second entry every day is worth more than a detailed entry once a week.

**Mark your flare days.** This is the most important thing for the prediction model. If you're having a bad day, check the flare box.

**Don't stress about missing days.** Life happens. A gap in the data is fine — the model works around it.

**Use the notes fields.** You don't have to write much, but "started new medication today" or "out in the sun for two hours" adds context that pure numbers can't capture.

**Come back to the Timeline.** After a month or two of data, the Timeline view starts showing you things. UV spikes followed by symptom spikes a day later. Sleep drops before flares. Patterns you couldn't see in the day-to-day.

---

*Built by C. Alaric Moore. Hosted privately. Your data stays here.*

*If something isn't working or you want a feature added, just ask.*
