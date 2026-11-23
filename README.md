# MEDI — medication reminders that don't let you forget

MEDI is an iPhone app (SwiftUI, iOS 26) built for DU Hacksgiving on November 21–22, 2026. Scan the label on each pill bottle and MEDI fills in the medicine, dose, times and expiration date, builds a pill box, and rings an alarm at each dose that stays until you confirm you took it. Everything runs on the phone: there's no server, account or AI service.

- **See it without installing:** a [walkthrough of every screen](https://emmagelman-alt.github.io/15-113-portoflio/medi/index.html) and [how it works](https://emmagelman-alt.github.io/15-113-portoflio/medi/how-it-works.html).
- **How it was built:** [`PROMPT_LOG.md`](PROMPT_LOG.md) has every prompt sent to the AI agent, and [`SPEC.md`](SPEC.md) is the original brief.
- **The raw AI version:** [`original-app-no-edits/`](original-app-no-edits) is the first version Claude Code built, before our Figma redesign.

The Xcode project and code still use the working name **PillBox**, and that's also the name under the app's icon on the home screen.

## Set it up

### What you need

- A Mac with **Xcode 26** or later, free from the Mac App Store. AlarmKit needs the iOS 26 SDK that comes with it.
- To run it on a phone: an **iPhone on iOS 26** or later, a cable, and an Apple Account. A free account works.
- Nothing else. There are no packages to install and no keys or server to set up. The Karla font is bundled.

### 1. Get the code

```bash
git clone https://github.com/emmagelman-alt/DU-HACKSGIVING.git
```

Open `DU-HACKSGIVING/PillBox.xcodeproj` in Xcode. That's the finished app.

### 2. Run it in the simulator

1. In the bar at the top of Xcode, choose the **PillBox** scheme and an iPhone simulator on iOS 26, such as iPhone 17.
2. Press **Run** (⌘R). The simulator doesn't need any signing changes.
3. The app opens on the MEDI welcome screen. Tap **START**, then allow alarms and notifications.
4. **Load the demo:** open the **Info** tab (ⓘ in the bottom bar), scroll to **More → Settings**, then tap **Demo → Load demo medications**. This adds made-up medicines, dose history and a health profile.
5. **Try a scan:** the simulator has no camera, so tap **+**, then **Try a sample label**. The label slides past as if the bottle were turning, and the fields turn green one by one. The photo button also lets you pick up to 10 photos, such as the images in `design/sample-labels/`.
6. **Try a reminder:** in **Settings**, tap **Send a test reminder in 1 minute**, then lock the simulator (**Device → Lock**, or ⌘L).

> **Alarm buttons in the simulator:** Xcode signs simulator apps without a team, and iOS 26 ignores alarm buttons (**Taken**, slide to stop) from an app with no team. So the PillBox scheme runs `Tools/sign-simulator-build.sh` after each build, which re-signs the app with an Apple Development certificate for the project's team. If you aren't on that team, the build still works, but those two buttons do nothing in the simulator. To fix that, set **Team** to your own (see the next section) and run once on a phone so Xcode creates your certificate, or just test the alarm on a phone.

The simulator can't send texts or email. **Text** opens the Messages app with the request filled in, and **Email** offers to copy the message. On an iPhone both open Apple's compose screen inside MEDI.

### 3. Run it on your iPhone

1. Plug the iPhone into the Mac, unlock it, and tap **Trust This Computer**.
2. In Xcode, click the **PillBox** project, then the **PillBox** target, then **Signing & Capabilities**:
   - **Team:** choose your Apple Account. If it isn't listed, add it in **Xcode → Settings → Accounts**.
   - **Bundle Identifier:** change `com.emmagelman.PillBox` to your own, for example `com.yourname.PillBox`. A bundle identifier belongs to one team, so Xcode can't use this one for yours.
3. At the top of Xcode, choose your iPhone as the run destination and press **Run**.
4. **First time only:**
   - On the iPhone, go to **Settings → Privacy & Security → Developer Mode** and turn it on. The phone restarts and asks you to confirm. The option only appears after the phone has been connected to Xcode once. Then press **Run** again.
   - If the phone says **Untrusted Developer**, go to **Settings → General → VPN & Device Management**, tap your developer certificate, tap **Trust**, and open the app.
5. Tap **START** and allow alarms and notifications. Allow the camera the first time you tap **+**.

Some things to know:
- **Free Apple accounts:** the app stops opening after 7 days. Press **Run** again to reinstall it. You can also only have 3 apps installed this way at once.
- **Your data:** installing over the app keeps your medicines. Deleting the app erases them.
- **Command-line builds:** keep the build folder outside `~/Documents`. iCloud adds file attributes there that break code signing. For example: `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/PillBox`.

### Running the original version

Open `original-app-no-edits/PillBox.xcodeproj` and run it the same way. It has the same bundle identifier as MEDI, so on the same simulator or phone it replaces MEDI. Use a different simulator for it, or give it its own bundle identifier.

## What it does

1. **Scan each bottle's label.**
   - Tap **+** and hold the bottle up to the camera, turning it slowly. The app reads the label live on the phone (VisionKit and Vision).
   - Each detail turns green as it's found: name, dosage, time, expiration date and provider.
   - It also keeps:
     - the quantity, refills, Rx number and pharmacy
     - the patient's name, which fills in your name on the Info tab if it's empty
     - the pill's description: shape, score line, colour and imprint
   - **The provider:** it's found under the full or shortened wordings pharmacies print (PRESCRIBER, PRSCRBR, PRESCR, PRES, DR., PRESCRIBED BY), even when the name is on the next line or written "LAST, FIRST MD". Nurse practitioners and physician assistants keep their title (for example "Ann Lee, NP") instead of getting "Dr.".
   - **Voting:** the camera reads the label many times a second, and any one reading can be off (glare, a curved label, text behind the bottle). So each reading votes, and a detail only turns green once two readings agree. A later majority can still correct it.
   - **Drug names** are checked against a built-in list of about 390 generic and brand names (`PillBox/Logic/KnownDrugs.swift`), so a one-letter misread like "Lisinoprll" is corrected to "Lisinopril". Release letters such as ER, XR and ODT stay in capitals.
   - **The time of day** comes only from the directions line ("Take 1 tablet by mouth every morning"), not from warnings or other text on the label.
   - **No camera handy?** Pick photos instead. Choose several photos of the same bottle from different sides and the app combines what it reads from each, adding another photo until every detail is found.
2. **Check the details.**
   - Once everything is read, the confirm screen shows it. Tap any line to change it, then **Add to pillbox**.
   - If the label doesn't give an exact time, the time reads **Morning**, **Afternoon**, **Evening** or **Night**. The reminder rings at that part of the day's time: 8 AM, 1 PM, 6 PM or 9:30 PM, which you can change in Settings. The Time pencil switches between parts of the day and exact clock times.
   - Every bottle is saved on its own, even two bottles of the same medicine, so each one's expiration date is tracked.
   - A second bottle of a medication you already have joins that medication's schedule, so you don't get double reminders.
3. **Pill box and Home.**
   - **Compartments:** the pill box has one for each medication, with a line drawing of the pill itself (round, oval, oblong, capsule, softgel and more, with its score line and imprint) taken from the label's description. You can change the shape under **Dosage** on the confirm screen.
   - **Expiry colours:** a compartment turns orange when a bottle expires within a week, and red only once it has actually expired, so nobody mistakes a still-good bottle for an expired one.
   - **Details:** tap a compartment to see its details, change any of them with its pencil, delete it or contact the provider.
   - **Contact provider** asks **Text** or **Email**. It then opens Apple's message or email screen with the refill request already written and the To field empty, so you type in the provider's number or address yourself. MEDI never needs to store it.
   - **Onboarding:** before any medication is added, Home shows the greeting and a glowing green ring around the **+** tab. The second sun holds a green arrow pointing at it, so it's clear which + to tap.
   - **Home** lists the chosen day's dose times with the medications to take at each. "Every 8 hours" and "12 hours apart" rules space the doses automatically.
4. **Reminders you can't ignore.**
   - **On the Lock Screen:** at each dose time an AlarmKit alarm fills the screen and rings even when the phone is on Silent or in a Focus. It also shows on a paired Apple Watch.
   - **On an unlocked phone:** iOS shows the alarm as a banner at the top. Apple doesn't let apps make that banner bigger or move it. Tapping the banner opens MEDI straight to the full-screen confirm page.
   - **While MEDI is open:** a full-screen **"Time for your meds"** screen covers it as soon as a dose is due. It lists every med due at that time and has one confirm button.
   - **Taken and slide to stop:** the alarm has a **Taken** button. iOS always adds its own **slide to stop**, which can't be removed, so sliding it opens MEDI on the confirm screen (after Face ID if the phone is locked).
   - **The confirm screen can't be closed** until you confirm the dose or snooze it. If you stop the alarm but don't open the app, or close the app, the confirm screen is waiting the next time MEDI opens.
   - **Backup notifications** repeat at +5, 10, 15, 20, 30, 45, 60 and 90 minutes until the dose is confirmed.
   - **Snooze** makes you pick a time later the same day, inside the same part of the day: a morning dose can't be pushed past 11:59 AM. There's no way to dismiss the reminder for good.
5. **Expiration warnings** go out 1 month, 2 weeks and 1 week before each bottle's date, and on the day itself. Expired bottles get a red warning that asks you to scan your new bottle.
6. **Refill requests.** When a bottle is expiring or running low, MEDI writes a refill request with the Rx number, and you send it by text or email, adding the recipient yourself.
7. **Info tab.**
   - Your health summary in one place: insurance, conditions, allergies, current and past medications, providers and pharmacy.
   - Each provider has a **Message** button. It writes the refill request for whichever of their medications needs it most and opens it as a text or email.
   - Tap any section to edit it. A medication you delete from the pill box moves to Past medications.

Photos and health details never leave the phone.

## Design

The team redesigned the app in Figma, in the section "Main tabs UPDATED", and renamed it MEDI.

**Built from Figma:**
- the welcome screen
- Home, empty and with medications
- the bottom bar: Home, +, Pill box, Info
- the add flow: "take scan page", "confirm info page" and the "added" screen
- the pill box: "pillbox base", the expiring version and "pill specific view"
- Info ("07 Info")

**Other screens:**
- The Info tab adds a **More** card at the bottom for Settings, Alerts, editing your info and adding a provider. It isn't in the Figma frame.
- The take-medication, snooze, settings, provider and refill-message screens keep the first design's layout, in the new colours.

**Colours:** from the Figma section "Color pallete":
- deep purple text and icons
- a pink-to-white background and frosted glass cards
- yellow buttons
- orange for the selected day and tab, and for bottles expiring within a week
- red for expired bottles and Delete

They're defined once in `PillBox/Views/MediDesign.swift` (`Medi`, `MediBackground` and `.mediCard()`).

**Font:** Karla, bundled in `PillBox/Fonts` under the SIL Open Font License (`Karla-OFL.txt`) and registered in `Config/PillBox-Info.plist`.

### First-design screenshots

[`design/screens/`](design/screens) has the screenshots of the first design, before the MEDI redesign. The team brought these into Figma. Files ending in `b` or `c` are the same screen scrolled down.

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
| 13 | Today before any medication is added |

**Retaking screenshots:**
1. Build and install the app on a booted simulator.
2. Load the demo data once.
3. Run `Tools/screenshots.sh <simulator-udid>`. This overwrites the files in `design/screens/` with the current design.

The app opens straight to any screen when launched with `-screen <name>`: `pillbox`, `meds`, `med`, `prescriber`, `message`, `alerts`, `scan`, `review`, `take`, `snooze`, `settings`, `empty` or `welcome`. Add `-inMemory` to start with no saved data and `-seedDemoData` to load the demo.

## Code map

| Folder | What's there |
|--------|--------------|
| `PillBox/Models` | SwiftData models: `Medication` (schedule), `Bottle` (one label, own expiration), `Prescriber`, `DoseLog` |
| `PillBox/Logic` | `Schedule.swift` (dose times, parts of the day, hours-apart rules, snooze limits), `Expiry.swift`, `LabelReader.swift` (Vision), `LabelParser.swift` (turns label text into fields), `ScanSession.swift` (votes across camera readings and photos), `KnownDrugs.swift` (drug names and misread correction) |
| `PillBox/Services` | `ReminderService.swift` (AlarmKit alarms, backup notifications, expiration warnings, alarm buttons), `AppModel.swift` (navigation, mark taken, snooze) |
| `PillBox/Views` | One file per screen. `MediDesign.swift` holds the MEDI colours, bottom bar and onboarding sun |
| `PillBox/Demo` | Demo data and the sample label text |
| `Shared` | Day parts and pill colors (kept separate for a future Apple Watch app) |
| `Tools` | `make-assets` draws the sample labels; `flatten-app-icon.swift` turns the Figma "App icon on blush" export into the square iOS icon; `screenshots.sh`; `sign-simulator-build.sh` (see the simulator note above) |
| `original-app-no-edits` | The first AI-built version, unchanged. Xcode doesn't build it as part of MEDI |

## Not built yet

- Apple Watch app. AlarmKit alarms and the backup notifications already show on a paired watch.
- Sending to the prescriber automatically, without the person tapping send. That needs a server and a texting service.
- Android.
