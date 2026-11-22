# PillBox — medication reminders that don't let you forget

PillBox is an iPhone app (SwiftUI, iOS 26) built for DU Hacksgiving.

1. **Scan each bottle's label.** Take a photo, or upload one. The app reads the label on the phone with Apple's Vision framework and fills in the details: medication name, strength, dose, how often and at what time of day, minimum hours between doses, expiration date, quantity, refills, Rx number, pharmacy and prescriber.
2. **Check the details.** A review screen highlights anything it couldn't find before you save. Every bottle is saved on its own, even two bottles of the same medicine, so each one's expiration date is tracked. A second bottle of a medication you already have joins that medication's schedule, so you don't get double reminders.
3. **Virtual pill box.** A week grid laid out like a real pill organizer, with morning, afternoon, evening and night compartments. Each compartment shows whether it was taken, missed, is due now, or is still coming up. You can set exact times instead of parts of the day. "Every 8 hours" and "12 hours apart" rules space the doses automatically.
4. **Reminders you can't ignore.**
   - At each dose time an **AlarmKit alarm** fills the Lock Screen and rings even when the phone is on Silent or in a Focus. It also shows on a paired Apple Watch.
   - The alarm has a **Taken** button. Pressing **Stop** instead opens the confirm screen.
   - Backup notifications repeat (at +5, 10, 15, 20, 30, 45, 60 and 90 minutes) until the dose is confirmed.
   - If you're using the app when a dose comes due, a full-screen **"Time for your meds"** screen covers it. That screen lists every med due at that time and has one confirm button.
   - **Snooze** makes you pick a time later the same day, inside the same part of the day: a morning dose can't be pushed past 11:59 AM. There's no way to dismiss the reminder for good.
5. **Expiration warnings** go out 1 month, 2 weeks and 1 week before each bottle's date, and on the day itself. Expired bottles get a red warning that asks you to scan your new bottle.
6. **Prescriber contact.** Add the doctor for each medication. When a bottle is expiring or running low, PillBox writes a refill request that you send by text or email.

Photos and health details never leave the phone.

## Run it

1. Open `PillBox.xcodeproj` in Xcode 26.
2. Choose the **PillBox** scheme and an iPhone simulator (or your iPhone).
3. Press Run. On the empty Today screen, tap **Load demo medications**, or go to Settings → Demo.

To run it on your own iPhone, change **Signing & Capabilities → Team** to your Apple account.

To try the reminders: Settings → **Send a test reminder in 1 minute**, then lock the phone.

> **Simulator note:** Xcode signs simulator apps without a team, and iOS 26 ignores alarm buttons (Taken, slide to stop) from an app with no team. So the PillBox scheme runs `Tools/sign-simulator-build.sh` after each build, which re-signs the simulator app with your Apple Development certificate for the project's team. If the alarm buttons do nothing in the simulator, check that your certificate is in Keychain Access and that **Signing & Capabilities → Team** is set. Builds for a real iPhone don't need this.

To try label reading: **+** → **Try a sample label**, or **Upload from Photos** and pick one of the images in `design/sample-labels/`.

> If you build from the command line, keep the build folder outside `~/Documents`. iCloud adds file attributes there that break code signing. For example: `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/PillBox`.

## Screens for Figma

Every screen is in [`design/screens/`](design/screens). Files ending in `b` or `c` are the same screen scrolled down.

| # | Screen |
|---|--------|
| 01 | Today (next dose, progress, expiration banner, today's schedule) |
| 02 | Pill Box week grid |
| 03 | Medications list + prescribers |
| 04 | Medication detail (times, bottles with label photos, prescriber) |
| 05 | Prescriber contact |
| 06 | Refill request message |
| 07 | Alerts (expired, expiring soon, running low) |
| 08 | Scan a label |
| 09 | Check the details (after reading a label) |
| 10 | "Time for your meds" full-screen confirm |
| 11 | Snooze (limited to the same part of the day) |
| 12 | Settings |
| 13 | Empty state (first launch) |

To retake them after UI changes, build and install the app on a booted simulator, load the demo data once, and run `Tools/screenshots.sh <simulator-udid>`. The app opens straight to any screen when launched with `-screen <name>` (`today`, `pillbox`, `meds`, `med`, `prescriber`, `message`, `alerts`, `scan`, `review`, `take`, `snooze`, `settings`, `empty`).

## Code map

| Folder | What's there |
|--------|--------------|
| `PillBox/Models` | SwiftData models: `Medication` (schedule), `Bottle` (one label, own expiration), `Prescriber`, `DoseLog` |
| `PillBox/Logic` | `Schedule.swift` (dose times, parts of the day, hours-apart rules, snooze limits), `Expiry.swift`, `LabelReader.swift` (Vision), `LabelParser.swift` (turns label text into fields) |
| `PillBox/Services` | `ReminderService.swift` (AlarmKit alarms, backup notifications, expiration warnings, alarm buttons), `AppModel.swift` (navigation, mark taken, snooze) |
| `PillBox/Views` | One file per screen |
| `PillBox/Demo` | Demo data and the sample label text |
| `Shared` | Day parts and pill colors (kept separate for a future Apple Watch app) |
| `Tools` | `make-assets` draws the sample labels and app icon; `screenshots.sh`; `sign-simulator-build.sh` (see the simulator note above) |

## Not built yet

- Apple Watch app. AlarmKit alarms and the backup notifications already show on a paired watch.
- Sending to the prescriber automatically, without the person tapping send. That needs a server and a texting service.
- Android.
