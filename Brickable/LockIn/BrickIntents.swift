//
//  BrickIntents.swift
//  Brickable
//
//  App Intents that flip the lock without the app being on screen.
//
//  These exist so a Shortcuts *personal automation* can be triggered by an NFC
//  tag: tap the card anywhere in the OS and the shield goes up, no app launch
//  and no notification to dismiss. Shortcuts recognises the card by its hardware
//  UID, so the identifier written by `provisionCard` isn't consulted on this
//  path — the in-app scan in `LockManager.tapCard()` is unchanged and still
//  verifies it.
//
//  `openAppWhenRun = false` is the whole point: the intent runs in a background
//  launch of the app. Mutating ManagedSettings from there is fine — it's the same
//  thing the DeviceActivity monitor extension does when the timeout fires.
//

import AppIntents
import FamilyControls

extension Notification.Name {
    /// Posted after an intent changes the lock. Only meaningful when the app is
    /// already running — an intent that arrives while Lock In is on screen would
    /// otherwise leave the header showing the old state, since no foregrounding
    /// happens to trigger `LockManager.refresh()`.
    static let brickableLockDidChange = Notification.Name("brickable.lock.didChange")
}

enum BrickIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notAuthorized
    case nothingSelected

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAuthorized:
            return "Brickable doesn't have Screen Time access yet. Open the app and grant it."
        case .nothingSelected:
            return "Nothing is set to be blocked. Open Brickable and choose some apps first."
        }
    }
}

/// Refuse to raise the shield when the lock can't actually work.
///
/// Only guards the locking direction: dropping a shield that is already up must
/// never depend on a permission, or revoking Screen Time access mid-lock would
/// strand the block with no way out.
@MainActor
private func assertLockUsable() throws {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
        throw BrickIntentError.notAuthorized
    }
    guard !SharedLockStore.selection.isEmpty else {
        throw BrickIntentError.nothingSelected
    }
}

/// Raise the shield and announce it. Shared by both intents so a tap gets the
/// same notification whichever one the card is wired to.
@MainActor
private func lockAndAnnounce() throws -> IntentDialog {
    let minutes = SharedLockStore.autoUnlockMinutes
    let outcome = try LockCoordinator.lock()

    LockNotifier.lockedIn(minutes: minutes, until: outcome.state.autoUnlockAt)
    NotificationCenter.default.post(name: .brickableLockDidChange, object: nil)

    return outcome.timeoutScheduled
        ? "Locked in for \(LockNotifier.durationDescription(minutes))."
        : "Locked in. The auto-unlock timer didn't arm, so your card is the only way out."
}

/// Drop the shield and announce it.
@MainActor
private func unlockAndAnnounce() -> IntentDialog {
    LockCoordinator.unlock()

    LockNotifier.unlocked()
    NotificationCenter.default.post(name: .brickableLockDidChange, object: nil)

    return "Unlocked."
}

// MARK: - Lock only

/// Raise the shield. Deliberately one-directional, so an NFC automation built on
/// it can be tapped twice without accidentally letting you back out — and so the
/// shortcut can't be run by hand as an escape hatch.
struct StartBrickIntent: AppIntent {
    static var title: LocalizedStringResource = "Brick My Phone"
    static var description = IntentDescription(
        "Blocks your chosen apps straight away, without opening Brickable. Tapping again leaves the block in place."
    )

    /// Runs in the background — no app launch, which is what makes an NFC tap
    /// feel instant.
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Heal a lock whose timeout elapsed while nothing was running, so an
        // expired flag can't make this read as "already locked in".
        LockCoordinator.reconcile()

        guard !SharedLockStore.lockState.isLocked else {
            return .result(dialog: "Already locked in.")
        }

        try assertLockUsable()
        return .result(dialog: try lockAndAnnounce())
    }
}

// MARK: - Toggle

/// Same flip a card tap performs in the app: locked becomes unlocked and back.
///
/// Convenient, but worth knowing that any intent in Shortcuts can also be run by
/// hand from the Shortcuts app, so wiring a tag to this one means there is a way
/// out of the block that doesn't involve the physical card. Use
/// `StartBrickIntent` instead if that matters.
struct ToggleBrickIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Brick"
    static var description = IntentDescription(
        "Blocks your chosen apps if they're free, unblocks them if they're blocked — without opening Brickable."
    )

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Decide the direction from the healed state, exactly as the in-app tap
        // does — `LockManager.refresh()` reconciles on every foreground, so a
        // lock the timeout already released reads as unlocked there too, and this
        // tap should start a fresh one rather than "unlock" what is already off.
        LockCoordinator.reconcile()

        if SharedLockStore.lockState.isLocked {
            return .result(dialog: unlockAndAnnounce())
        }

        try assertLockUsable()
        return .result(dialog: try lockAndAnnounce())
    }
}

// MARK: - Siri phrases

struct BrickableShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBrickIntent(),
            phrases: [
                "Brick my phone with \(.applicationName)",
                "Lock in with \(.applicationName)"
            ],
            shortTitle: "Brick My Phone",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: ToggleBrickIntent(),
            phrases: [
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Toggle Brick",
            systemImageName: "lock.rotation"
        )
    }
}
