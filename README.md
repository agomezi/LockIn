# Brickable

A personal iPhone app combining two things:

- **Lock In** — a Brick-style app blocker. Tap an NFC card to shield a chosen set
  of apps and categories via Screen Time, tap it again to release. A configurable
  auto-unlock timer runs as a fallback.
- **Pomodoro** — a focus timer with daily progress and streaks, kept
  field-compatible with the Django backend in
  [`agomezi/PomodoroTimer`](https://github.com/agomezi/PomodoroTimer).

iOS 17+, SwiftUI, iPhone only.

## Getting set up

The Xcode project is **generated** — `project.yml` is the source of truth, so
there is no `.xcodeproj` in this repo.

```sh
brew install xcodegen

cp Config/Signing.example.xcconfig Config/Signing.xcconfig
# put your Apple Developer Team ID in that file

xcodegen generate
open Brickable.xcodeproj
```

`Config/Signing.xcconfig` is gitignored so the team identifier stays local.

### Signing requirements

Running on a device needs a **paid Apple Developer Program** membership. The
Family Controls and NFC Tag Reading capabilities are not available to free
personal teams — Xcode rejects the provisioning profile outright.

## Layout

| Path | What's in it |
|---|---|
| `Brickable/Shared/` | App Group state, shield control, auto-unlock scheduling — compiled into the app *and* all three extensions |
| `Brickable/LockIn/` | Screen Time authorization, NFC card handling, the Lock In screen |
| `Brickable/Pomodoro/` | Timer engine, SwiftData progress, stats, settings, views |
| `ShieldConfigurationExtension/` | How the block screen looks |
| `ShieldActionExtension/` | What its buttons do — close or defer only, never unlock |
| `DeviceActivityMonitorExtension/` | Clears the shield when the auto-unlock timer expires |
| `Config/` | Info.plists and entitlements for all four targets |

## The NFC card

Any blank **NTAG213/215** tag works. *Set Up Card* writes a fixed identifier to
it once; every tap after that toggles the lock, with the direction decided from
shared state rather than from the card, so the two can't drift out of sync.

Mifare Classic tags do **not** work — iPhones can't read them.

### Tapping the card without opening the app

`Brickable/LockIn/BrickIntents.swift` exposes two App Intents that flip the lock
in a background launch of the app — no UI, no notification to dismiss:

| Intent | What it does |
|---|---|
| **Brick My Phone** | Raises the shield. Tapping again leaves it up. |
| **Toggle Brick** | Same flip as an in-app card tap. |

Either one posts a local notification — *Locked in for 1 hour · Unlocks at 7:32 PM,
or tap your card again* — because a Shortcuts automation runs the intent silently
and its spoken dialog only surfaces when Siri was the one asking.

Wire one to the card with a Shortcuts automation, on the phone:

1. **Shortcuts → Automation → + → NFC → Scan**, hold the card against the phone,
   name it.
2. Add the **Toggle Brick** action (search "Brick") — or **Brick My Phone** for a
   lock-only tap.
3. Turn **Ask Before Running** off and pick **Run Immediately**.

After that a tap anywhere in iOS flips the lock in about a second. Allow
notifications when the app asks, or the tap does its job with nothing to show for
it.

Two things worth knowing:

- **The screen has to be on and unlocked.** Third-party apps can't read NFC on a
  sleeping or locked phone — Express Mode is Wallet/HomeKit only — so there is no
  way to make a tap work from a pocket.
- Shortcuts matches the card by its **hardware UID**, not by the identifier that
  *Set Up Card* wrote, so the two paths are independent and the in-app scan still
  verifies the payload.

**Brick My Phone** is the stricter option: any shortcut can also be run by hand
from the Shortcuts app, so automating **Toggle Brick** means there is a way out of
the block that doesn't need the physical card. Unlocking in the app, the
auto-unlock timer, and Siri ("Hey Siri, brick my phone") all still work either
way.

The automation stores the intent's identifier, so reinstalling or updating the app
keeps it working — but renaming `StartBrickIntent` / `ToggleBrickIntent` breaks it
and the automation has to be rebuilt.

## Tests

```sh
xcodebuild -scheme Brickable -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Covers the Pomodoro phase cycle, settings encoding, lock state, and the streak
calculation — which is a deliberate port of the Django `user_stats` view,
including its quirk that the current streak reads 0 until a session is logged
today. `PomodoroStatsTests` pins that behaviour so the two stay in agreement.
