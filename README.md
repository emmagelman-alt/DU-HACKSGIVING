# PillBox — medication reminders that don't let you forget

PillBox is an iPhone app (SwiftUI, iOS 26) built for DU Hacksgiving.

1. **Scan each bottle's label.** Tap **+** and hold the bottle up to the camera, turning it slowly. The app reads the label live on the phone (VisionKit and Vision) and each detail turns green as it's found: name, dosage, time, expiration date and provider. It also keeps the quantity, refills, Rx number, pharmacy, the patient's name (which fills in your name on the Info tab if it's empty) and the pill's description (shape, score line, colour and imprint). The provider is found under the full or shortened wordings pharmacies print (PRESCRIBER, PRSCRBR, PRESCR, PRES, DR., PRESCRIBED BY), even when the name is on the next line or written "LAST, FIRST MD". Nurse practitioners and physician assistants keep their title (for example "Ann Lee, NP") instead of getting "Dr.". The camera reads the label many times a second and any one reading can be off (glare, a curved label, text behind the bottle), so each reading votes and a detail only turns green once two readings agree; a later majority can still correct it. Drug names are checked against a built-in list of about 390 generic and brand names (`PillBox/Logic/KnownDrugs.swift`), so a near miss like "Quillichi" is corrected to "Quillichew ER", and release letters such as ER, XR and ODT stay in capitals. The time of day comes only from the directions line ("Chew 2 tablets by mouth once daily in the morning"), not from warnings or the MAX DAILY DOSE line. No camera handy? Pick photos instead: choose several photos of the same bottle from different sides and the app combines what it reads from each, adding another photo until every detail is found.
2. **Check the details.** Once everything is read, the confirm screen shows it. Tap any line to change it, then **Add to pillbox**. If the label doesn't give an exact time, the time reads **Morning**, **Afternoon**, **Evening** or **Night**, and the reminder rings at that part of the day's time (8 AM, 1 PM, 6 PM or 9:30 PM, changeable in Settings). The Time pencil switches between parts of the day and exact clock times. Every bottle is saved on its own, even two bottles of the same medicine, so each one's expiration date is tracked. A second bottle of a medication you already have joins that medication's schedule, so you don't get double reminders.
3. **Pill box and Home.** The pill box has a compartment for each medication, with a line drawing of the pill itself (round, oval, oblong, capsule, softgel and more, with its score line and imprint) taken from the label's description. You can change the shape under **Dosage** on the confirm screen. A compartment turns orange when a bottle expires within a week, and red only once it has actually expired, so nobody mistakes a still-good bottle for an expired one. Tap one to see its details, change any of them with its pencil, delete it or contact the provider. **Contact provider** asks **Text** or **Email**, then opens Apple's message or email screen with the refill request already written and the To field empty, so you type in the provider's number or address yourself. MEDI never needs to store it. Home lists the chosen day's dose times with the medications to take at each. "Every 8 hours" and "12 hours apart" rules space the doses automatically.
4. **Reminders you can't ignore.**
   - At each dose time an **AlarmKit alarm** fills the Lock Screen and rings even when the phone is on Silent or in a Focus. It also shows on a paired Apple Watch.
   - When the phone is unlocked and in use, iOS shows the alarm as a banner at the top instead. Apple doesn't let apps make that banner bigger or move it. Tapping the banner opens MEDI straight to the full-screen confirm page, and if MEDI is already open when the alarm rings, it covers the screen with that page at once.
   - The alarm has a **Taken** button. iOS always adds its own **slide to stop**, which can't be removed, so sliding it opens MEDI on the confirm screen instead (after Face ID if the phone is locked). That screen can't be closed until you confirm the dose or snooze it. If you stop the alarm but don't open the app, or close the app, the confirm screen is waiting the next time MEDI opens, and the backup reminders keep coming.
   - Backup notifications repeat (at +5, 10, 15, 20, 30, 45, 60 and 90 minutes) until the dose is confirmed.
   - If you're using the app when a dose comes due, a full-screen **"Time for your meds"** screen covers it. That screen lists every med due at that time and has one confirm button.
   - **Snooze** makes you pick a time later the same day, inside the same part of the day: a morning dose can't be pushed past 11:59 AM. There's no way to dismiss the reminder for good.
5. **Expiration warnings** go out 1 month, 2 weeks and 1 week before each bottle's date, and on the day itself. Expired bottles get a red warning that asks you to scan your new bottle.
6. **Prescriber contact.** Add the doctor for each medication. When a bottle is expiring or running low, PillBox writes a refill request that you send by text or email, adding the recipient yourself.
7. **Info tab.** Your health summary in one place: insurance, conditions, allergies, current and past medications, providers and pharmacy. Each provider has a **Message** button that writes the refill request for whichever of their medications needs it most and opens it as a text or email. Tap any section to edit it. A medication you delete from the pill box moves to Past medications.

Photos and health details never leave the phone.

## Run it

1. Open `PillBox.xcodeproj` in Xcode 26.
2. Choose the **PillBox** scheme and an iPhone simulator (or your iPhone).
3. Press Run. With no medications saved, the app opens on the MEDI welcome screen. Tap **START** to go to Home.
4. To load the demo medications, open the **Info** tab (ⓘ in the bottom bar), scroll to **More → Settings**, then **Demo → Load demo medications**. This also fills in a sample health profile.

To run it on your own iPhone, change **Signing & Capabilities → Team** to your Apple account.

To try the reminders: Info tab → **More → Settings** → **Send a test reminder in 1 minute**, then lock the phone.

> **Simulator note:** Xcode signs simulator apps without a team, and iOS 26 ignores alarm buttons (Taken, slide to stop) from an app with no team. So the PillBox scheme runs `Tools/sign-simulator-build.sh` after each build, which re-signs the simulator app with your Apple Development certificate for the project's team. If the alarm buttons do nothing in the simulator, check that your certificate is in Keychain Access and that **Signing & Capabilities → Team** is set. Builds for a real iPhone don't need this.

The simulator can't send texts or email, so **Text** opens the Messages app with the request filled in instead of the in-app message screen, and **Email** offers to copy the message. On an iPhone both open Apple's compose screen inside MEDI (Email opens your default mail app if Mail isn't set up).

To try label reading in the simulator (which has no camera): tap **+**, then **Try a sample label**. The label slides past as if the bottle were turning and the fields turn green one by one. The photo button on the scan page also lets you pick up to 10 photos (for example the images in `design/sample-labels/`, or several shots of one bottle) and reads them in order. On an iPhone the + tab opens the live camera.

> If you build from the command line, keep the build folder outside `~/Documents`. iCloud adds file attributes there that break code signing. For example: `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/PillBox`.

## Screens for Figma

Every screen is in [`design/screens/`](design/screens). Files ending in `b` or `c` are the same screen scrolled down.

The team's redesign (the app is now called MEDI) is in Figma, in the section "Main tabs UPDATED". Built so far: the welcome screen, Home (empty and with medications), the bottom bar (Home, +, Pill box, Info), the add flow ("take scan page", "confirm info page" and the "added" screen), the pill box ("pillbox base", the expiring version and "pill specific view") and Info ("07 Info"). The Info tab adds a **More** card at the bottom, which isn't in the Figma frame, for Settings, Alerts, editing your info and adding a provider. The take-medication, snooze, settings, provider and refill-message screens still use the first design. The colours come from the Figma section "Color pallete": deep purple text and icons, a pink-to-white background, frosted glass cards, yellow buttons, orange for the selected day and tab and for bottles expiring within a week, and red for expired bottles and Delete. They're defined once in `PillBox/Views/MediDesign.swift` (`Medi`, `MediBackground` and `.mediCard()`). The redesign uses the Karla font, which is bundled in `PillBox/Fonts` under the SIL Open Font License (`Karla-OFL.txt`) and registered in `Config/PillBox-Info.plist`.

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
| 13 | Home before any medication is added ("onboarding home") |
| 14 | MEDI welcome screen ("first screen") |

To retake them after UI changes, build and install the app on a booted simulator, load the demo data once, and run `Tools/screenshots.sh <simulator-udid>`. The app opens straight to any screen when launched with `-screen <name>` (`today`, `pillbox`, `meds`, `med`, `prescriber`, `message`, `alerts`, `scan`, `review`, `take`, `snooze`, `settings`, `empty`, `welcome`).

## Code map

| Folder | What's there |
|--------|--------------|
| `PillBox/Models` | SwiftData models: `Medication` (schedule), `Bottle` (one label, own expiration), `Prescriber`, `DoseLog` |
| `PillBox/Logic` | `Schedule.swift` (dose times, parts of the day, hours-apart rules, snooze limits), `Expiry.swift`, `LabelReader.swift` (Vision), `LabelParser.swift` (turns label text into fields), `ScanSession.swift` (votes across camera readings and photos), `KnownDrugs.swift` (drug names and misread correction) |
| `PillBox/Services` | `ReminderService.swift` (AlarmKit alarms, backup notifications, expiration warnings, alarm buttons), `AppModel.swift` (navigation, mark taken, snooze) |
| `PillBox/Views` | One file per screen |
| `PillBox/Demo` | Demo data and the sample label text |
| `Shared` | Day parts and pill colors (kept separate for a future Apple Watch app) |
| `Tools` | `make-assets` draws the sample labels; `flatten-app-icon.swift` turns the Figma "App icon on blush" export into the square iOS icon; `screenshots.sh`; `sign-simulator-build.sh` (see the simulator note above) |

## Not built yet

- Apple Watch app. AlarmKit alarms and the backup notifications already show on a paired watch.
- Sending to the prescriber automatically, without the person tapping send. That needs a server and a texting service.
- Android.
