# Prompt Log: MEDI (PillBox)

DU Hacksgiving, November 21–22, 2026. Built with Claude Code (Claude Opus 5.5) in this repository.

- **What this file is:** every prompt we sent the AI agent, in order, copied word for word from the Claude Code session record. Typos are left as typed.
- **Times:** Eastern Time.
- **What happened next:** each prompt has a short note on what it led to, with the commit where there is one.
- **The AI's untouched first version:** saved in [`original-app-no-edits/`](original-app-no-edits/), an exact copy of the first commit, `b78e83d`.

## Contents

1. [Initial build prompt](#1-initial-build-prompt)
2. [Clarifications before the build](#2-clarifications-before-the-build)
3. [Follow-up prompts by phase](#3-follow-up-prompts-by-phase)
4. [Prompts about React Native and Expo](#4-prompts-about-react-native-and-expo)
5. [Manual interventions and why](#5-manual-interventions-and-why)

---

## 1. Initial build prompt

**Nov 21, 12:40 PM.** The same text is in [`SPEC.md`](SPEC.md).

> I want to build an app for mobile devices with a smartwatch integration. use the DU hacksgiving repo. The app is about emdication reminders. To use the App, people can take photos or upload photos of the label on their medication bottles that contains the information about the name of the medication, the amount, and the time and frequency it should be taken. The user can upload as many medications as they need to take. the app should be bale tpo identify : name of medication, dosage, when to take time and day, expiration date. once the user uploads all theri medications the app creates a virtual pill box/calendar that lists what medicatons have to be taken for each day as well as when each medication should be taken ( i.e morning, evening, night) user should be able to put in exact times if they want to. when it is time for the meds to be taen on the day of. the app should send a big notification to the users phone and watch, the notification should appear big on the lockscreen and not go away until the user confirms that they have taken their meds by clicking on the notification or opening the app and hitting a confirm taken button. The confirm taken screen should list all the meds for that time and day, as well as the confirm button. The app should also keep track of medication expiration dates and warn users when the meds are 1 month from expiration, then again 2 weeks from expiration, then again 1 week from expiration, and the day of expiration. It should include a warning for any meds that have expired nd urge the user to upload a new bottle label to confirm that they have gotten a new dose. for each medication users must upload the original bottle label so even if they have two of the same meds they have combined, the app can know if there is a difference in expiration. There can also be an option to add a medical practitioner contact who prescribes the medication and when the meds are near expiring or are running low, the app can notify the medical practitioner. if the user is already on their phone when the notification to take their meds pops up, it should cover their current activity like a screen time reminder does, however, there should be the option to silence the notifciaton until a certain time if the user is in the mdidle of something really important, however, the user cannot remvoe the notifiaton entorly and must select a time for it to come back that is on the same day and in the same dya period (i.e. if it is a morning medicaiton they cant push the notificaton to 1pm.). The app should also recognize if certain meds require a specific number of hours apart and use that to help determine when in the day to remind the user to take them.

## 2. Clarifications before the build

Before writing any code, the agent asked three questions: which platform, how labels get read, and when the demo was due.

**Question 1: platform.** The agent compared two options:
- **iPhone + Apple Watch in Swift**, using AlarmKit for lock-screen alarms, Vision for reading labels and a real Watch app.
- **iPhone + Android with Expo (React Native).** One codebase, but the alarms, label reading and Watch app would all need native add-ons. That means it couldn't run in Expo Go, and the Watch part would still be Swift.

It also warned that on iPhone only Screen Time can cover another app. The closest a normal app can get is an alarm-style alert.

| Time | Prompt | What it led to |
|---|---|---|
| 12:42 PM | > iPhone + Android | The agent moved on to question 2, about reading labels: on the phone only, or with an AI service that sends the photo off the phone. |
| 12:46 PM | > wait lets actually do it for iphone native built in swift. and lets do option one on the phone only | Platform changed to native iPhone (Swift). Labels are read on the phone only (Apple Vision plus a rule-based parser, no AI service). |
| 12:48 PM | > this is due in 6 hours and we would like the demo to be built in the next hour or 2 so we can bring the screens into figma and manually adjust the ui. Once we have the basic screens and ui sent back to you to implement, we can keep making it work. | Deadline and workflow set: build every screen quickly, hand screenshots to Figma, then implement the team's redesign. |
| 12:52 PM | *(stopped the agent while it was presenting a plan that included an Apple Watch app)* | |
| 12:52 PM | > go ahead without the watch integration for now | The Watch app was dropped. AlarmKit alarms still show on a paired Apple Watch. |

## 3. Follow-up prompts by phase

### Phase A: first build and hand-off to Figma (Nov 21, 1:30–1:54 PM)

| Time | Prompt | What it led to |
|---|---|---|
| 1:30 PM | > Commit and push | First working version committed: `b78e83d` "Add PillBox: medication reminder iPhone app". This is the version in `original-app-no-edits/`. |
| 1:34 PM | > send all screens to a new figma file | 18 app screenshots placed in a new Figma file as iPhone-size frames. |
| 1:38 PM | > Rebuild main screens | The agent started rebuilding the screens as editable Figma layers. We stopped it at 1:46 PM. |
| 1:46 PM | > bring screenshots to figma and we will build functional screens from that | Screenshots kept as images. Our team redesigned the screens by hand in Figma. |
| 1:54 PM | > how should i run this on my phone in expo go | Explained that Expo Go can't run a native Swift app, and gave the Xcode steps instead. See [section 4](#4-prompts-about-react-native-and-expo). |

### Phase B: building our Figma redesign (3:16–4:29 PM)

| Time | Prompt | What it led to |
|---|---|---|
| 3:16 PM | > look at the figma file pillbox app screens and the frame holding the screens called main tabs updated. update the current UI to match the main tab screens in that frame collection. | Stopped by us at 3:19 PM to narrow the scope. |
| 3:21 PM | > change the first screen to onboading home in the working demo. update the current screens to match the ones titled "first screen" and "onboarding home" in the fimga file | The welcome screen and empty Home built from Figma. The app is now branded MEDI. |
| 3:34 PM | > Yes, add Karla | Approved downloading the Karla font (Google Fonts, SIL Open Font License) to match the design. |
| 3:39 PM | > once the user reachs the onboarding home screen and clicks the add pil icon. they should be taken to the screen titled "take scan page" in figma where they can actually scan their medication and slowly rotate the bottoe,  medi app should fill in the detaisl of the medicstion from the label and each info field should turn green when it is scanned. when all info is collected, the screen should chsnge to the one  in fogma titled "confirm info page" the user has the abiltiy to edit any fo the info and if they are happy with it they click the add to pillbox button which sends them to the scren titled "screen for when medication has been added and the user is choosing what to do next ". if they click add another they are sent back tot the scan screen and if they click done they see their medication in the pillbox screen . The medication will also appear on their home screen in the tab of the day and time it should be taken at. The pillbox screens should match the ones in the Figma file called pillbox base, pillbox specific view, and if a medication is expiring soon, refer to the expiring version of pillbox base for how that should be displayed. | Built the add flow (live scan with fields turning green, confirm page, "added" page), the pill box grid and detail card, and medicines showing up on Home. |
| 3:59 PM | > Change the info screen to the updated one we made in Figma | Info tab built from the Figma "07 Info" frame. We interrupted at 4:02 PM to add the next request. |
| 4:06 PM | > make it so that the red label for pils expering soon only turns red when it is 1 week before expiratiopn | Compartments turn red only within a week of expiry. Later changed to orange and red (7:03 PM). |
| 4:16 PM | > commit and push it | `454d502` "Redesign as MEDI: welcome, Home, add flow, pill box and Info". |
| 4:17 PM | > update the three screens that changed in figma | Onboarding home and scan page rebuilt to the revised frames. The welcome screen needed no change. |
| 4:24 PM | > Yes, update both | Confirm page and pill detail card rebuilt to the newer frames. |
| 4:29 PM | > Commit and push | `0d6f853` "Match the revised Figma screens: onboarding, scan, confirm and pill detail". |

### Phase C: testing on a real iPhone (4:31–6:09 PM)

| Time | Prompt | What it led to |
|---|---|---|
| 4:31 PM | > how should i tet this oj ym iphone wit xcode | Step-by-step Xcode install instructions, plus a list of what to test that the simulator couldn't. |
| 4:32 PM | > Yes, once plugged in | The agent built and signed the app for the phone. |
| 4:35 PM | > developer mode is on | |
| 4:37 PM | > Signed in, retry | |
| 4:39 PM | > Trusted, open it | First run on the phone. |
| 4:50 PM | > 1. The scan should have given information as to the name of the patient so it should auto-update in the info tab. <br>2. The contact provider does not work because there is no way to add the provider's email or contact info. Add a field for the provider's contact info in the info tab and grey out the contact provider until contact information is given. <br>3. The scanner should be able to complete the info it needs from multiple different photos; for instance, if I have different photos of multiple angles of my bottle. <br>4. The pill images in the overview cards of the pills in the pillbox main view should be line-drawing-style outlines of what the pill actually looks like. | The patient name is read from the label, provider contact fields added (reversed at 5:34 PM), up to 10 photos of one bottle are merged, and pill line drawings come from the label's description line. |
| 5:09 PM | > Commit and push | `ee84854` "Read patient names and pill looks, merge photos, gate provider contact". |
| 5:10 PM | > update the screens now to match the ones in the frame titled color pallete | Every screen recoloured to the Figma "Color pallete" frame. |
| 5:34 PM | > all looks good, keep the info screen simple like in the Figma. for contact provider. if you click text it should pull up the text screen with a blank recipient field that you fill in and the drafted message in the text box like the Apple default. for email, it should do the same. This way, users can manually write in the recipient and don't have to add it into the app. if the user does not imput a specific time to take the pill then it should have either morning, afternoon.e vening, or night in the time field | Provider fields removed. Contact now opens Apple's text or email composer with a blank "To" field and the refill request already written. The time shows the part of the day when no exact time is set. |
| 5:42 PM | > Commit and push | `9673a0d` "Apply the Color pallete look, simplify provider contact, show parts of the day". |
| 5:43 PM | > install it on my iphone, it's plugged in | |
| 5:45 PM | > can the version on my phone go from the begining and reset all the progess? i just need to test everything we updated but for the folllowing runs i want progress aved. does that make snese | The agent explained that a reset means removing the app, and that later installs keep the data. |
| 5:46 PM | > Yes, reset it | |
| 5:46 PM | > Trusted, open it | |
| 5:48 PM | > why can t the scan recognize prscrbr and the attached name on the bottle as the fill in info for provider in the app | The parser now reads abbreviated prescriber lines (PRSCRBR, PRESCR), names in "LAST, FIRST MD" order, and NP and PA-C titles. |
| 5:58 PM | > Why is there an emergency contact option? We don't have that in Figma. also update the home screen app icon to be the one titled app icon on blush. | App icon replaced with the "App icon on blush" frame. The agent explained where the emergency contact came from. |
| 6:04 PM | > Remove it | Emergency contact removed. |
| 6:09 PM | > It's plugged in | |
| 6:09 PM | > reset the data on my phone version so i can run it frokm the top | |

### Phase D: scanner accuracy and alarm polish (6:29–7:47 PM)

| Time | Prompt | What it led to |
|---|---|---|
| 6:29 PM | > the pill bottle scan is still a little inaccurate sometimes. here are screenshots of recent attempts. how can we make the scanner as accurate as possible | We attached screenshots of real scans. The scanner now votes across camera reads (a field is accepted once two reads agree), checks names against 387 drug names, gives that list to Vision as custom words, and reads times only from the directions line. |
| 6:56 PM | > its plugged in. reset the data and run it on my phpne | |
| 6:57 PM | > Trusted it | |
| 7:03 PM | > Change the expiring soon pill indicator red box color on the pillbox to an orange until it is actually expired. Then the icon card should become red. This way people dont think that their medications are expired before they actually are. also for the pill take alarm. there is an option to slide to stop it. remove the option to stop it or make it so that slide to stop takes them immediately to the app, where they have to confirm they have taken the med, and they can't close the screen until they do. also remove the little text on each pill that says "finish the whole course" | Orange within a week, red once expired. iOS won't let an app remove "slide to stop", so sliding now opens a confirm screen that can't be closed until the dose is taken or snoozed. That screen comes back after a quit. "Finish the whole course" removed. |
| 7:13 PM | > it is plugge din, run it from the begining | |
| 7:14 PM | > Trusted it | |
| 7:20 PM | > this is great, can we change the alarm that comes on when someone is already on their phone to take up the full screen? it is too smal at the top, something like an alarm card that takes up most of the scree or an alarm notfi that goes in the center of the screen rather than jsut the top | iOS draws that banner itself, so it can't be resized. Instead, the full-screen take screen appears the moment an alarm rings while MEDI is open, and tapping the banner from another app opens it. |
| 7:31 PM | > Commit and push | `bdbc33c` "Sharpen label scanning, warn before expiry in orange, lock the alarm flow". |
| 7:32 PM | > make the new version work on my iphone. reset fromthe beginign so i can work through the whole flow | |
| 7:33 PM | > Trusted it | |
| 7:35 PM | > this is great. on ethe home screen durign onbaordign when it says to click the plus button to scan a new med. can you add a glowing green circle around the plus where they should add so people dont think they ened to click the pus button in the onboarding message | Pulsing green ring around the + tab while there are no medicines. It holds still when Reduce Motion is on. |
| 7:37 PM | > Commit and push | `529c72a` "Point new users to the + tab with a glowing ring". |
| 7:38 PM | > reset my phone so i can see the onboarding ring | |
| 7:38 PM | > Trusted it | |
| 7:39 PM | > make the sun in the explanation on the onboarding screen near the add pill button point to the addpil button at the bottom so it looks like he is holding an arrow that points to it | The sun's raised arm was redrawn holding a green arrow that points at the + tab. |
| 7:45 PM | > Commit and push | `7db80db` "Have the onboarding sun point an arrow at the + tab". |
| 7:46 PM | > reset my phone so i can see the pointing sun | |
| 7:47 PM | > Trusted it | |

### Phase E: explaining the app, and a snooze bug (7:48–8:54 PM)

| Time | Prompt | What it led to |
|---|---|---|
| 7:48 PM | > explain the engineerign stack that makes this app work | Walkthrough of the stack: SwiftUI, SwiftData, VisionKit and Vision, the rule-based parser, AlarmKit, App Intents, UserNotifications and MessageUI. |
| 7:49 PM | > make the one-page diagram for the judges | Started. We stopped it at 7:55 PM to ask about a bug. |
| 7:55 PM | > why does the alamr feature not always work when i snooze | Two causes found. A snoozed test reminder never got a new alarm. Snoozing while the alarm was still ringing could fail silently. |
| 7:55 PM | > is the github repo updated? | Sent while the agent was still working. Yes: GitHub `main` was at the latest commit, `7db80db`. |
| 7:57 PM | > so if i tap snooze and set an alarm to test the alarm, the alarm should still come up | Confirmed that it wouldn't, with the version on the phone at the time. |
| 8:03 PM | > yes fix both and put it on my phone. | Both fixed. Also fixed the Settings row being hidden under the bottom bar. Tested in the simulator: a snoozed test alarm rang again on time. Installed on the phone. |
| 8:25 PM | > commt, push, send to phone from begining | `dad7692` "Make snoozed alarms ring again; show the Settings row on Info", then a fresh install. |
| 8:26 PM | > Trusted it | |
| 8:28 PM | > make the one-page diagram for the judges | One-page engineering diagram published for the judges. |
| 8:52 PM | > reset the demo for my hppme | |
| 8:52 PM | > It's plugged in | |
| 8:53 PM | > Trusted it | |
| 8:54 PM | > Try again | App opened fresh for the demo. |

### Phase F: submission (Nov 22)

| Time | Prompt | What it led to |
|---|---|---|
| 6:41 PM | > can you commit a version called original app no edits to the repo so the grades see the raw AI output? do not change anything abou tthe final polished version | `a1e133d` added `original-app-no-edits/`, an exact copy of the first commit. The finished app is unchanged. |
| 7:01 PM | > make me a prompt log including the below Your initial build prompt to the agent<br><br>* Any follow-up prompts or clarifications during the phases<br>* Prompts where you asked AI to explain React Native or Expo concepts<br>* Notes on any manual interventions you made and why | This file. |

## 4. Prompts about React Native and Expo

MEDI isn't a React Native or Expo app. After seeing the trade-offs, we switched to native Swift 6 minutes into the project. Two moments touched on Expo:

1. **The platform question (12:41 PM).** The agent explained that an Expo (React Native) version would cover iPhone and Android with one codebase. But lock-screen alarms, on-device label reading and a Watch app would each need native modules. A build with native modules can't run in Expo Go, so it would need a custom development build. The Watch app would still have to be written in Swift. We first answered "iPhone + Android", then switched to native Swift at 12:46 PM.

2. **"how should i run this on my phone in expo go" (1:54 PM).** The agent explained:
   - Expo Go only runs apps written in React Native with Expo. It can't load a native SwiftUI app.
   - Moving MEDI to Expo would mean rewriting it, and AlarmKit's lock-screen alarms don't work in Expo Go.
   - So it gave the steps to install from Xcode instead: plug in the phone, turn on Developer Mode, pick the phone as the run destination, trust the developer certificate.

Other prompts where we asked the AI to explain something were about the native stack, not React Native:
- 4:31 PM: testing on an iPhone with Xcode.
- 6:29 PM: making the scanner accurate.
- 7:20 PM: why the unlocked-phone alarm banner can't be resized.
- 7:48 PM: the engineering stack.
- 7:55 PM: the snooze bug.

## 5. Manual interventions and why

Every code commit in this repository came out of the AI session. No Swift code was edited by hand. The only commits made by hand are [`SPEC.md`](SPEC.md) and [`openreview.md`](openreview.md), uploaded through GitHub's website. Our hands-on work was decisions, design, device setup and testing:

- **Changed the platform to native iPhone (12:46 PM).** We had first chosen iPhone + Android. The comparison showed that the alarms, label reading and Watch app would all need native add-ons in Expo, which was too much to finish in 6 hours.
- **Kept label reading on the phone.** We chose on-device reading over an AI service. Photos of health information never leave the phone, it works offline, and there's no API key or server to manage.
- **Dropped the Apple Watch app (12:52 PM).** We stopped the agent's plan to cut scope for the deadline. Alarms still appear on a paired Watch through AlarmKit.
- **Redesigned the UI by hand in Figma.** We stopped the agent from rebuilding the screens as Figma layers (1:46 PM) because we wanted to design them ourselves from the screenshots. We made the MEDI brand, the "Main tabs UPDATED" screens, the "Color pallete" frame, the onboarding suns and the "App icon on blush" icon, then had the agent build each frame.
- **Narrowed the scope while building (3:19 PM, 4:02 PM).** We interrupted the agent to have it build only the frames we had finished, and to add the expiry-colour change mid-task.
- **Approved the Karla font download (3:34 PM).** The agent asks before downloading anything, and the design needed Karla.
- **Set up the iPhone ourselves.** iOS requires a person to do these steps, so the agent couldn't:
  - plug in the phone
  - turn on Developer Mode
  - sign in to our Apple account in Xcode
  - trust the developer profile again after every reset
- **Tested with real pill bottles.** The simulator has no camera. Scanning real labels showed misreads from glare, text from behind the bottle being picked up, and abbreviated prescriber lines. We sent screenshots (6:29 PM) so the agent could fix the scanner.
- **Caught design mismatches.** We noticed the emergency contact wasn't in our Figma and had it removed (5:58–6:04 PM).
- **Reversed our own earlier request.** We had asked for provider contact fields (4:50 PM), then decided the Info screen should stay as simple as the Figma. So contact now opens the phone's own text or email composer (5:34 PM).
- **Found the snooze bug by testing on the phone (7:55 PM).** Then we had it fixed and retested.
- **Added the specification and a code review by hand on Nov 22.** We uploaded `SPEC.md` (our initial prompt) and `openreview.md` (a review of the app against that spec) through GitHub.
- **Kept the AI's first version for grading (Nov 22).** We asked for `original-app-no-edits/`, so the raw first output can be compared with the finished app.
