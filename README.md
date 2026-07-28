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

## Tests

```sh
xcodebuild -scheme Brickable -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Covers the Pomodoro phase cycle, settings encoding, lock state, and the streak
calculation — which is a deliberate port of the Django `user_stats` view,
including its quirk that the current streak reads 0 until a session is logged
today. `PomodoroStatsTests` pins that behaviour so the two stay in agreement.
